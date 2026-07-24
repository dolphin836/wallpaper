package handler

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/service"
)

const (
	mediaSessionCookie = "wpe_media_session"
	mediaViewTTL       = 5 * time.Minute
	mediaVideoViewTTL  = 30 * time.Minute
	mediaDownloadTTL   = 10 * time.Minute
)

type mediaClaims struct {
	WallpaperID int64  `json:"w"`
	Kind        string `json:"k"`
	Mode        string `json:"m"`
	ExpiresAt   int64  `json:"e"`
}

type MediaHandler struct {
	wallpaperSvc *service.WallpaperService
	storage      *storage.Storage
	secret       []byte
	publicOrigin string
	now          func() time.Time
}

func NewMediaHandler(wallpaperSvc *service.WallpaperService, store *storage.Storage, secret, publicOrigin string) *MediaHandler {
	return &MediaHandler{
		wallpaperSvc: wallpaperSvc,
		storage:      store,
		secret:       []byte(secret),
		publicOrigin: strings.TrimRight(publicOrigin, "/"),
		now:          time.Now,
	}
}

// EnsureViewSession creates an anonymous, HTTP-only browser session. It is
// intentionally independent of login: signed original views work for every
// visitor, while copied URLs fail outside the browser session that received
// them.
func (h *MediaHandler) EnsureViewSession(w http.ResponseWriter, r *http.Request) (string, error) {
	if cookie, err := r.Cookie(mediaSessionCookie); err == nil && validMediaSession(cookie.Value) {
		return cookie.Value, nil
	}
	random := make([]byte, 24)
	if _, err := rand.Read(random); err != nil {
		return "", fmt.Errorf("generate media session: %w", err)
	}
	session := base64.RawURLEncoding.EncodeToString(random)
	expires := h.now().Add(24 * time.Hour)
	http.SetCookie(w, &http.Cookie{
		Name:     mediaSessionCookie,
		Value:    session,
		Path:     "/",
		Expires:  expires,
		MaxAge:   int((24 * time.Hour).Seconds()),
		HttpOnly: true,
		Secure:   requestIsSecure(r),
		SameSite: http.SameSiteLaxMode,
	})
	return session, nil
}

func validMediaSession(value string) bool {
	if len(value) < 24 || len(value) > 128 {
		return false
	}
	_, err := base64.RawURLEncoding.DecodeString(value)
	return err == nil
}

func requestIsSecure(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	proto := strings.TrimSpace(strings.Split(r.Header.Get("X-Forwarded-Proto"), ",")[0])
	return strings.EqualFold(proto, "https")
}

func (h *MediaHandler) DecorateOriginal(r *http.Request, session string, wp *model.Wallpaper) error {
	if wp == nil || wp.OriginalURL == "" {
		return nil
	}
	ttl := mediaViewTTL
	if strings.HasPrefix(strings.ToLower(wp.FileType), "video/") {
		ttl = mediaVideoViewTTL
	}
	viewURL, err := h.signedURL(r, mediaClaims{
		WallpaperID: wp.ID,
		Kind:        service.MediaKindOriginal,
		Mode:        "view",
		ExpiresAt:   h.now().Add(ttl).Unix(),
	}, session, mediaFilename(wp.ID, wp.OriginalURL, wp.FileType))
	if err != nil {
		return err
	}
	wp.OriginalURL = viewURL
	return nil
}

func (h *MediaHandler) SignedArchiveOriginal(r *http.Request, session string, wallpaperID int64, rawURL string) (string, error) {
	if rawURL == "" {
		return "", nil
	}
	return h.signedURL(r, mediaClaims{
		WallpaperID: wallpaperID,
		Kind:        service.MediaKindOriginal,
		Mode:        "view",
		ExpiresAt:   h.now().Add(mediaViewTTL).Unix(),
	}, session, mediaFilename(wallpaperID, rawURL, ""))
}

func (h *MediaHandler) DownloadURL(r *http.Request, wp *model.Wallpaper) (string, error) {
	return h.signedURL(r, mediaClaims{
		WallpaperID: wp.ID,
		Kind:        service.MediaKindOriginal,
		Mode:        "download",
		ExpiresAt:   h.now().Add(mediaDownloadTTL).Unix(),
	}, "", mediaFilename(wp.ID, wp.OriginalURL, wp.FileType))
}

func (h *MediaHandler) signedURL(r *http.Request, claims mediaClaims, session, filename string) (string, error) {
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("marshal media claims: %w", err)
	}
	encoded := base64.RawURLEncoding.EncodeToString(payload)
	signature := h.signature(encoded, session)
	token := encoded + "." + base64.RawURLEncoding.EncodeToString(signature)
	return h.origin(r) + "/api/v1/media/" + url.PathEscape(token) + "/" + url.PathEscape(filename), nil
}

func (h *MediaHandler) signature(payload, session string) []byte {
	mac := hmac.New(sha256.New, h.secret)
	_, _ = io.WriteString(mac, "wallpaper-media-v1\n")
	_, _ = io.WriteString(mac, session)
	_, _ = io.WriteString(mac, "\n")
	_, _ = io.WriteString(mac, payload)
	return mac.Sum(nil)
}

func (h *MediaHandler) origin(r *http.Request) string {
	if isLocalRequestHost(r.Host) || h.publicOrigin == "" {
		scheme := "http"
		if requestIsSecure(r) {
			scheme = "https"
		}
		return scheme + "://" + r.Host
	}
	return h.publicOrigin
}

func isLocalRequestHost(host string) bool {
	host = strings.ToLower(host)
	return strings.HasPrefix(host, "localhost:") || strings.HasPrefix(host, "127.0.0.1:") || host == "localhost" || host == "127.0.0.1"
}

func mediaFilename(wallpaperID int64, rawURL, contentType string) string {
	ext := ""
	if parsed, err := url.Parse(rawURL); err == nil {
		ext = path.Ext(parsed.Path)
	}
	if ext == "" && contentType != "" {
		if exts, _ := mime.ExtensionsByType(contentType); len(exts) > 0 {
			ext = exts[0]
		}
	}
	if ext == "" {
		ext = ".bin"
	}
	return fmt.Sprintf("wallpaper_%d%s", wallpaperID, ext)
}

func (h *MediaHandler) Serve(w http.ResponseWriter, r *http.Request) {
	claims, err := h.verifyRequestToken(r)
	if err != nil {
		http.Error(w, "media link is invalid or expired", http.StatusForbidden)
		return
	}
	asset, ec := h.wallpaperSvc.ResolveMediaAsset(r.Context(), claims.WallpaperID, claims.Kind)
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		http.Error(w, http.StatusText(status), status)
		return
	}
	info, err := h.storage.StatObject(r.Context(), asset.ObjectKey)
	if err != nil {
		slog.ErrorContext(r.Context(), "stat protected media failed", "error", err, "wallpaper_id", claims.WallpaperID)
		http.Error(w, "media unavailable", http.StatusNotFound)
		return
	}

	contentType := asset.ContentType
	if contentType == "" {
		contentType = info.ContentType
	}
	if contentType == "" {
		contentType = "application/octet-stream"
	}
	disposition := "inline"
	if claims.Mode == "download" {
		disposition = "attachment"
	}
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("Cache-Control", "private, no-store, max-age=0")
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disposition, map[string]string{"filename": asset.Filename}))
	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Cross-Origin-Resource-Policy", "same-site")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("X-Robots-Tag", "noindex, noimageindex")
	if info.ETag != "" {
		w.Header().Set("ETag", strconv.Quote(info.ETag))
	}
	if !info.LastModified.IsZero() {
		w.Header().Set("Last-Modified", info.LastModified.UTC().Format(http.TimeFormat))
	}

	start, end, partial, err := parseSingleByteRange(r.Header.Get("Range"), info.Size)
	if err != nil {
		w.Header().Set("Content-Range", fmt.Sprintf("bytes */%d", info.Size))
		http.Error(w, "invalid range", http.StatusRequestedRangeNotSatisfiable)
		return
	}
	length := info.Size
	if partial {
		length = end - start + 1
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, info.Size))
		w.Header().Set("Content-Length", strconv.FormatInt(length, 10))
		w.WriteHeader(http.StatusPartialContent)
	} else {
		w.Header().Set("Content-Length", strconv.FormatInt(length, 10))
	}
	if r.Method == http.MethodHead {
		return
	}

	var reader io.ReadCloser
	if partial {
		reader, err = h.storage.GetObjectRange(r.Context(), asset.ObjectKey, start, end)
	} else {
		reader, err = h.storage.GetObject(r.Context(), asset.ObjectKey)
	}
	if err != nil {
		slog.ErrorContext(r.Context(), "open protected media failed", "error", err, "wallpaper_id", claims.WallpaperID)
		return
	}
	defer reader.Close()
	if _, err := io.CopyN(w, reader, length); err != nil && !errors.Is(err, r.Context().Err()) {
		slog.WarnContext(r.Context(), "stream protected media interrupted", "error", err, "wallpaper_id", claims.WallpaperID)
	}
}

func (h *MediaHandler) verifyRequestToken(r *http.Request) (*mediaClaims, error) {
	token := chi.URLParam(r, "token")
	payload, encodedSignature, ok := strings.Cut(token, ".")
	if !ok || payload == "" || encodedSignature == "" {
		return nil, errors.New("malformed media token")
	}
	rawClaims, err := base64.RawURLEncoding.DecodeString(payload)
	if err != nil {
		return nil, err
	}
	var claims mediaClaims
	if err := json.Unmarshal(rawClaims, &claims); err != nil {
		return nil, err
	}
	if claims.Mode != "view" && claims.Mode != "download" {
		return nil, errors.New("invalid media mode")
	}
	if claims.Kind != service.MediaKindOriginal {
		return nil, errors.New("invalid media kind")
	}
	if claims.WallpaperID <= 0 || claims.ExpiresAt <= h.now().Unix() {
		return nil, errors.New("expired media token")
	}
	session := ""
	if claims.Mode == "view" {
		cookie, err := r.Cookie(mediaSessionCookie)
		if err != nil || !validMediaSession(cookie.Value) {
			return nil, errors.New("missing media session")
		}
		session = cookie.Value
	}
	actualSignature, err := base64.RawURLEncoding.DecodeString(encodedSignature)
	if err != nil {
		return nil, err
	}
	if !hmac.Equal(actualSignature, h.signature(payload, session)) {
		return nil, errors.New("invalid media signature")
	}
	return &claims, nil
}

func parseSingleByteRange(header string, size int64) (start, end int64, partial bool, err error) {
	if header == "" {
		return 0, size - 1, false, nil
	}
	if size <= 0 || !strings.HasPrefix(header, "bytes=") || strings.Contains(header, ",") {
		return 0, 0, false, errors.New("unsupported range")
	}
	raw := strings.TrimSpace(strings.TrimPrefix(header, "bytes="))
	left, right, ok := strings.Cut(raw, "-")
	if !ok {
		return 0, 0, false, errors.New("malformed range")
	}
	if left == "" {
		suffix, parseErr := strconv.ParseInt(right, 10, 64)
		if parseErr != nil || suffix <= 0 {
			return 0, 0, false, errors.New("invalid suffix range")
		}
		if suffix > size {
			suffix = size
		}
		return size - suffix, size - 1, true, nil
	}
	start, err = strconv.ParseInt(left, 10, 64)
	if err != nil || start < 0 || start >= size {
		return 0, 0, false, errors.New("invalid range start")
	}
	end = size - 1
	if right != "" {
		end, err = strconv.ParseInt(right, 10, 64)
		if err != nil || end < start {
			return 0, 0, false, errors.New("invalid range end")
		}
		if end >= size {
			end = size - 1
		}
	}
	return start, end, true, nil
}
