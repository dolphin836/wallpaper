package handler

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/tus/tusd/v2/pkg/filestore"
	tusd "github.com/tus/tusd/v2/pkg/handler"

	"github.com/wallpaper/backend/internal/pkg/jwt"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

// Resumable video uploads via the tus.io protocol. Lives at
// /api/v1/uploads/tus/* — the trailing path is the per-upload ID
// (POST creates one, subsequent PATCH/HEAD/DELETE address it). The
// existing multipart upload at /wallpapers stays for image uploads;
// only video uploads route through here so the MVP avoids
// rewriting the image path.
//
// Lifecycle:
//   1. Browser opens upload by POSTing Upload-Length + Upload-Metadata
//      headers (no body). preCreate verifies the JWT, validates size
//      and Content-Type, stashes user_id into MetaData.
//   2. Browser PATCHes chunks until offset == length. tusd writes
//      them to the local filestore (tmpDir/<id>). Pauses + retries
//      are native to the protocol.
//   3. On completion tusd emits an event on CompleteUploads;
//      completionLoop streams the assembled file into MinIO, asks
//      the service to create the wallpaper row + fire the
//      wallpaper.transcode Kafka event, then deletes the tus
//      tempfiles.

const (
	tusBasePath     = "/api/v1/uploads/tus"
	tusMaxSize      = 200 * 1024 * 1024 // 200 MiB hard cap per upload
	tusMetaUserID   = "user_id"
	tusMetaFiletype = "filetype"
	tusMetaFilename = "filename"
)

type TusHandler struct {
	handler   *tusd.Handler
	svc       *service.WallpaperService
	wpRepo    *repo.WallpaperRepo
	storage   *storage.Storage
	jwtSecret string
	tmpDir    string
}

func NewTusHandler(
	svc *service.WallpaperService,
	wpRepo *repo.WallpaperRepo,
	st *storage.Storage,
	jwtSecret string,
	tmpDir string,
) (*TusHandler, error) {
	if tmpDir == "" {
		tmpDir = filepath.Join(os.TempDir(), "wpe-tus")
	}
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		return nil, fmt.Errorf("mkdir tus tmp dir %q: %w", tmpDir, err)
	}
	store := filestore.New(tmpDir)
	composer := tusd.NewStoreComposer()
	store.UseIn(composer)

	h := &TusHandler{
		svc: svc, wpRepo: wpRepo, storage: st,
		jwtSecret: jwtSecret, tmpDir: tmpDir,
	}

	tusH, err := tusd.NewHandler(tusd.Config{
		BasePath:                tusBasePath + "/",
		StoreComposer:           composer,
		MaxSize:                 tusMaxSize,
		DisableDownload:         true,
		NotifyCompleteUploads:   true,
		PreUploadCreateCallback: h.preCreate,
		// Trust X-Forwarded-Host / X-Forwarded-Proto set by Caddy.
		// Without this tusd would build the Location header from the
		// container-internal URL (http://api:8080/...) and the browser
		// would reject the cross-protocol PATCH with a Mixed Content
		// error — even though the original request came over HTTPS.
		RespectForwardedHeaders: true,
	})
	if err != nil {
		return nil, fmt.Errorf("tus handler: %w", err)
	}
	h.handler = tusH

	go h.completionLoop()
	return h, nil
}

// ServeHTTP routes the request to the underlying tusd handler. Chi
// already strips the route prefix down to the per-upload ID.
func (h *TusHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.handler.ServeHTTP(w, r)
}

// preCreate fires on the initial POST that opens an upload. We use it
// to authenticate the user, validate size + content type, and stash
// the user_id into the upload's MetaData so the completion handler
// (which runs without an HTTP request) can attribute the upload.
func (h *TusHandler) preCreate(event tusd.HookEvent) (tusd.HTTPResponse, tusd.FileInfoChanges, error) {
	// Re-verify the JWT. The chi Auth middleware also rejects
	// anonymous traffic before it ever reaches the tusd handler, but
	// the request context isn't propagated to tusd hooks so we
	// re-parse the Authorization header to pull user_id.
	auth := event.HTTPRequest.Header.Get("Authorization")
	tokenStr, ok := strings.CutPrefix(auth, "Bearer ")
	if !ok {
		return tusd.HTTPResponse{StatusCode: http.StatusUnauthorized, Body: "missing bearer token"}, tusd.FileInfoChanges{}, fmt.Errorf("missing bearer")
	}
	claims, err := jwt.ParseToken(tokenStr, h.jwtSecret)
	if err != nil {
		return tusd.HTTPResponse{StatusCode: http.StatusUnauthorized, Body: "invalid token"}, tusd.FileInfoChanges{}, fmt.Errorf("invalid token: %w", err)
	}

	if event.Upload.Size > tusMaxSize {
		return tusd.HTTPResponse{
			StatusCode: http.StatusRequestEntityTooLarge,
			Body:       fmt.Sprintf("video must be ≤%d bytes", tusMaxSize),
		}, tusd.FileInfoChanges{}, fmt.Errorf("oversize: %d", event.Upload.Size)
	}

	filetype := event.Upload.MetaData[tusMetaFiletype]
	if !strings.HasPrefix(filetype, "video/") {
		return tusd.HTTPResponse{
			StatusCode: http.StatusBadRequest,
			Body:       "only video/* uploads are accepted on this endpoint",
		}, tusd.FileInfoChanges{}, fmt.Errorf("non-video filetype %q", filetype)
	}

	// Merge user_id into the upload's persisted metadata. We preserve
	// any client-supplied filename / filetype rather than overwriting.
	merged := tusd.MetaData{
		tusMetaUserID:   strconv.FormatInt(claims.UserID, 10),
		tusMetaFiletype: filetype,
	}
	if name := event.Upload.MetaData[tusMetaFilename]; name != "" {
		merged[tusMetaFilename] = name
	}
	return tusd.HTTPResponse{}, tusd.FileInfoChanges{MetaData: merged}, nil
}

// completionLoop drains CompleteUploads, pushes each finished file
// from local disk into MinIO, creates a wallpaper row, fires
// wallpaper.transcode, and cleans up the tus tempfiles.
func (h *TusHandler) completionLoop() {
	for event := range h.handler.CompleteUploads {
		uploadID := event.Upload.ID
		userIDStr := event.Upload.MetaData[tusMetaUserID]
		userID, _ := strconv.ParseInt(userIDStr, 10, 64)
		if userID <= 0 {
			slog.Error("tus: completed upload missing user_id meta", "upload_id", uploadID)
			h.cleanup(uploadID)
			continue
		}
		filename := event.Upload.MetaData[tusMetaFilename]
		if filename == "" {
			filename = uploadID + ".mp4"
		}
		filetype := event.Upload.MetaData[tusMetaFiletype]
		if filetype == "" {
			filetype = "video/mp4"
		}
		// Detach the timeout from the inbound request — the request
		// context is already done by the time completion fires.
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		err := h.handleComplete(ctx, uploadID, userID, filename, filetype, event.Upload.Size)
		cancel()
		if err != nil {
			// Preserve the assembled file on disk so an operator can
			// re-trigger ingest manually (e.g. via a CLI) rather than
			// asking the user to re-upload the whole thing. Cleanup
			// only on the happy path. The tus_data volume sweeps
			// stale leftovers when it's resized; this isn't a leak.
			slog.Error("tus: handle complete failed — preserving file for manual recovery",
				"upload_id", uploadID, "user_id", userID, "error", err,
				"file", filepath.Join(h.tmpDir, uploadID))
			continue
		}
		h.cleanup(uploadID)
	}
}

func (h *TusHandler) handleComplete(ctx context.Context, uploadID string, userID int64, filename, filetype string, size int64) error {
	// tusd filestore writes the assembled bytes at tmpDir/<id> with
	// no extension, and a sibling .info file holds JSON metadata.
	tusPath := filepath.Join(h.tmpDir, uploadID)
	f, err := os.Open(tusPath)
	if err != nil {
		return fmt.Errorf("open tus file: %w", err)
	}
	defer f.Close()

	ext := strings.ToLower(filepath.Ext(filename))
	if ext == "" {
		ext = ".mp4"
	}
	objectKey := fmt.Sprintf("originals/%s/%s%s",
		time.Now().UTC().Format("2006/01/02"),
		uuid.New().String(), ext,
	)
	if err := h.storage.Upload(ctx, objectKey, f, size, filetype); err != nil {
		return fmt.Errorf("minio upload: %w", err)
	}

	if _, ec := h.svc.IngestVideoUpload(ctx, userID, service.IngestVideoUploadRequest{
		ObjectKey: objectKey,
		FileSize:  size,
		FileType:  filetype,
		FileName:  filename,
	}); ec != nil {
		return fmt.Errorf("ingest video: %s", ec.Message)
	}
	return nil
}

func (h *TusHandler) cleanup(uploadID string) {
	base := filepath.Join(h.tmpDir, uploadID)
	_ = os.Remove(base)
	_ = os.Remove(base + ".info")
}
