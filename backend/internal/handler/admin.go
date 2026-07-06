package handler

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"mime"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

type AdminHandler struct {
	adminRepo      *repo.AdminRepo
	userRepo       *repo.UserRepo
	coinRepo       *repo.CoinRepo
	wallpaperRepo  *repo.WallpaperRepo
	collectionRepo *repo.CollectionRepo
	reportRepo     *repo.ReportRepo
	workerJobRepo  *repo.WorkerJobRepo
	categoryRepo   *repo.CategoryRepo
	analyticsRepo  *repo.AnalyticsRepo
	loginLogRepo   *repo.LoginLogRepo
	llmUsageRepo   *repo.LLMUsageRepo
	weeklyPickRepo *repo.WeeklyPickRepo
	eventRepo      *repo.EventRepo
	storage        *storage.Storage
	wallpaperSvc   *service.WallpaperService // needed for Reprocess (Kafka re-publish)

	storageCacheMu sync.Mutex
	storageCache   *storage.BucketUsage
	storageCacheAt time.Time
}

func NewAdminHandler(
	adminRepo *repo.AdminRepo,
	userRepo *repo.UserRepo,
	coinRepo *repo.CoinRepo,
	wallpaperRepo *repo.WallpaperRepo,
	collectionRepo *repo.CollectionRepo,
	reportRepo *repo.ReportRepo,
	workerJobRepo *repo.WorkerJobRepo,
	categoryRepo *repo.CategoryRepo,
	analyticsRepo *repo.AnalyticsRepo,
	loginLogRepo *repo.LoginLogRepo,
	llmUsageRepo *repo.LLMUsageRepo,
	weeklyPickRepo *repo.WeeklyPickRepo,
	eventRepo *repo.EventRepo,
	store *storage.Storage,
	wallpaperSvc *service.WallpaperService,
) *AdminHandler {
	return &AdminHandler{
		adminRepo:      adminRepo,
		userRepo:       userRepo,
		coinRepo:       coinRepo,
		wallpaperRepo:  wallpaperRepo,
		collectionRepo: collectionRepo,
		reportRepo:     reportRepo,
		workerJobRepo:  workerJobRepo,
		categoryRepo:   categoryRepo,
		analyticsRepo:  analyticsRepo,
		loginLogRepo:   loginLogRepo,
		llmUsageRepo:   llmUsageRepo,
		weeklyPickRepo: weeklyPickRepo,
		eventRepo:      eventRepo,
		storage:        store,
		wallpaperSvc:   wallpaperSvc,
	}
}

// ─── helpers ─────────────────────────────────────────────────────────────

func parseIntDefault(s string, def int) int {
	if s == "" {
		return def
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	return n
}

func parseInt64Default(s string, def int64) int64 {
	if s == "" {
		return def
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		return def
	}
	return n
}

func parsePage(q map[string][]string) (int, int) {
	page := 1
	if v, ok := q["page"]; ok && len(v) > 0 {
		page = parseIntDefault(v[0], 1)
	}
	if page < 1 {
		page = 1
	}
	limit := 20
	if v, ok := q["limit"]; ok && len(v) > 0 {
		limit = parseIntDefault(v[0], 20)
	}
	if limit < 1 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	return page, limit
}

// ─── dashboard ───────────────────────────────────────────────────────────

func (h *AdminHandler) GetOverview(w http.ResponseWriter, r *http.Request) {
	stats, err := h.adminRepo.Overview(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "admin overview failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, stats)
}

type seriesResp struct {
	Users      []repo.DailyPoint `json:"users"`
	Wallpapers []repo.DailyPoint `json:"wallpapers"`
	Events     []repo.DailyPoint `json:"events"`
	Days       int               `json:"days"`
}

func (h *AdminHandler) GetSeries(w http.ResponseWriter, r *http.Request) {
	days := parseIntDefault(r.URL.Query().Get("days"), 30)
	users, err := h.adminRepo.DailySeries(r.Context(), "users", days)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin series users failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	wp, err := h.adminRepo.DailySeries(r.Context(), "wallpapers", days)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin series wallpapers failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	ev, err := h.adminRepo.DailySeries(r.Context(), "events", days)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin series events failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, seriesResp{Users: users, Wallpapers: wp, Events: ev, Days: days})
}

type topResp struct {
	Top        []repo.TopWallpaper  `json:"top"`
	Categories []repo.CategoryCount `json:"categories"`
}

func (h *AdminHandler) GetTops(w http.ResponseWriter, r *http.Request) {
	by := r.URL.Query().Get("by")
	limit := parseIntDefault(r.URL.Query().Get("limit"), 10)
	top, err := h.adminRepo.TopWallpapers(r.Context(), by, limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin top wallpapers failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	cats, err := h.adminRepo.CategoryDistribution(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "admin category dist failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, topResp{Top: top, Categories: cats})
}

// ─── wallpapers ──────────────────────────────────────────────────────────

func (h *AdminHandler) ListWallpapers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	status := int16(parseIntDefault(q.Get("status"), -1))
	categoryID := parseInt64Default(q.Get("category_id"), 0)
	userID := parseInt64Default(q.Get("user_id"), 0)

	rows, total, err := h.wallpaperRepo.AdminList(r.Context(), repo.AdminWallpaperListOpts{
		Search:      q.Get("search"),
		Status:      status,
		CategoryID:  categoryID,
		UserID:      userID,
		QualityFlag: q.Get("quality_flag"),
		Offset:      (page - 1) * limit,
		Limit:       limit,
		Sort:        q.Get("sort"),
	})
	if err != nil {
		slog.ErrorContext(r.Context(), "admin wallpapers list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

type adminUpdateWallpaperReq struct {
	Title       *string `json:"title"`
	Description *string `json:"description"`
	CategoryID  *int64  `json:"category_id"`
	Status      *int16  `json:"status"`
}

func (h *AdminHandler) UpdateWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminUpdateWallpaperReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.wallpaperRepo.AdminUpdate(r.Context(), id, repo.AdminWallpaperUpdate{
		Title:       req.Title,
		Description: req.Description,
		CategoryID:  req.CategoryID,
		Status:      req.Status,
	}); err != nil {
		slog.ErrorContext(r.Context(), "admin wallpaper update failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	// Publishing via the edit form is an approval too — pay the upload
	// reward here as well (GrantUploadReward is idempotent per wallpaper).
	if req.Status != nil && *req.Status == model.WallpaperStatusPublished {
		h.wallpaperSvc.GrantUploadReward(r.Context(), id)
	}
	response.OK(w, nil)
}

// ApproveQuality clears a wallpaper's quality_flag back to 'ok' (the
// admin reviewed the LLM's call and disagreed) and triggers a reprocess
// so the device variants — which qcheck dropped when it first flagged
// the row — get regenerated. Cleanup of the previously-dropped variants
// is a no-op since they were already removed; the worker's
// cleanupOldArtifacts at the top of processImage just runs against an
// empty set.
func (h *AdminHandler) ApproveQuality(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.wallpaperRepo.SetQualityFlag(r.Context(), id, "ok", "approved by admin"); err != nil {
		slog.ErrorContext(r.Context(), "approve quality: set flag failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if ec := h.wallpaperSvc.Reprocess(r.Context(), id); ec != nil {
		slog.ErrorContext(r.Context(), "approve quality: reprocess failed", "id", id, "error", ec)
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, nil)
}

// ─── review queue ─────────────────────────────────────────────────────
// Uploads now land in WallpaperStatusPendingReview after processing.
// Admin uses these three endpoints to drain the queue.

func (h *AdminHandler) ListReviewQueue(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	rows, total, err := h.wallpaperRepo.ReviewQueue(r.Context(), limit, (page-1)*limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin review queue list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

func (h *AdminHandler) ApproveReview(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if ec := h.wallpaperSvc.ApproveReview(r.Context(), id); ec != nil {
		slog.ErrorContext(r.Context(), "admin approve review failed", "id", id)
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, nil)
}

type adminRejectReviewReq struct {
	Reason string `json:"reason"`
}

func (h *AdminHandler) RejectReview(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminRejectReviewReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		reason = "Rejected by admin"
	}
	if len(reason) > 280 {
		reason = reason[:280]
	}
	if err := h.wallpaperRepo.AdminReject(r.Context(), id, reason); err != nil {
		slog.ErrorContext(r.Context(), "admin reject review failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

// ReprocessWallpaper re-queues a stuck or failed wallpaper through the
// image worker. Flips status back to processing and re-publishes the
// original wallpaper.uploaded Kafka event with the same object key, so
// the next worker pick reruns variant generation + thumb/preview.
func (h *AdminHandler) ReprocessWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if ec := h.wallpaperSvc.Reprocess(r.Context(), id); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		} else if ec.Code == errcode.ErrInvalidParam.Code {
			status = http.StatusBadRequest
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *AdminHandler) DeleteWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.wallpaperRepo.Delete(r.Context(), id); err != nil {
		slog.ErrorContext(r.Context(), "admin wallpaper delete failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

// Sentinel errors from hardDeleteOne so the single-id endpoint can keep
// returning 404/400 while the batch endpoint reports them per id.
var (
	errHardDeleteNotFound = errors.New("wallpaper not found")
	errHardDeleteStatus   = errors.New("status not eligible for hard delete (soft-delete first)")
)

// HardDeleteWallpaper physically removes a wallpaper row, its children and
// its MinIO objects. Restricted to rows that are already off the public
// surface — status=removed (soft-deleted), status=duplicate or
// status=rejected. Trying to hard-delete a live (published / processing /
// failed) row is rejected, so an admin has to soft-delete first if they
// really mean to nuke it. The two-step path keeps an accidental click from
// atomically destroying a live wallpaper plus every like/favorite/download
// attached to it.
func (h *AdminHandler) HardDeleteWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	switch err := h.hardDeleteOne(r.Context(), id); {
	case errors.Is(err, errHardDeleteNotFound):
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
	case errors.Is(err, errHardDeleteStatus):
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
	case err != nil:
		slog.ErrorContext(r.Context(), "admin hard-delete failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
	default:
		response.OK(w, nil)
	}
}

// hardDeleteOne enforces the status gate and removes one wallpaper row, its
// children and its MinIO objects. Shared by the single and batch endpoints.
//
// MinIO deletions are best-effort: if a key is missing or the storage
// layer hiccups, we log and continue. The DB cleanup already committed,
// so the row + children are gone either way; an orphaned object will
// just sit in MinIO until the next cleanup sweep.
func (h *AdminHandler) hardDeleteOne(ctx context.Context, id int64) error {
	// GetByID filters out status=removed, so we need a raw lookup that sees
	// every status — hard-delete operates on rows the public API has already
	// hidden.
	existing, err := h.wallpaperRepo.GetByIDAnyStatus(ctx, id)
	if err != nil {
		return fmt.Errorf("lookup: %w", err)
	}
	if existing == nil {
		return errHardDeleteNotFound
	}
	if existing.Status != model.WallpaperStatusRemoved &&
		existing.Status != model.WallpaperStatusDuplicate &&
		existing.Status != model.WallpaperStatusRejected {
		return errHardDeleteStatus
	}

	deleted, err := h.wallpaperRepo.AdminHardDelete(ctx, id)
	if err != nil {
		return fmt.Errorf("hard delete: %w", err)
	}
	wp := deleted.Wallpaper

	// Build the full MinIO object list from every URL the wallpaper
	// touched: the original upload, the thumb / preview / dynamic
	// frames generated by the worker, and every device variant.
	// Anything still referencing a URL gets a best-effort Delete —
	// failures log and continue so a transient MinIO hiccup doesn't
	// strand the DB cleanup (which already committed).
	objectURLs := []string{wp.OriginalURL, wp.ThumbURL, wp.PreviewURL}
	if wp.FrameURLs != "" {
		for _, u := range strings.Split(wp.FrameURLs, ",") {
			if u = strings.TrimSpace(u); u != "" {
				objectURLs = append(objectURLs, u)
			}
		}
	}
	objectURLs = append(objectURLs, deleted.VariantURLs...)
	for _, url := range objectURLs {
		key := h.storage.ObjectKeyFromURL(url)
		if key == "" {
			continue
		}
		if err := h.storage.Delete(ctx, key); err != nil {
			slog.WarnContext(ctx, "minio delete failed (continuing)", "key", key, "error", err)
		}
	}

	slog.InfoContext(ctx, "wallpaper hard-deleted",
		"id", id, "slug", wp.Slug,
		"variant_count", len(deleted.VariantURLs),
		"object_count", len(objectURLs))
	return nil
}

// BatchWallpapers applies one moderation action to up to 100 wallpapers in
// a single call, powering the admin list's multi-select toolbar. Each id is
// processed independently — one failure doesn't abort the rest — and the
// response reports both buckets so the UI can say "12 done, 2 failed".
func (h *AdminHandler) BatchWallpapers(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IDs    []int64 `json:"ids"`
		Action string  `json:"action"` // delete | hard_delete | approve_review | reject_review
		Reason string  `json:"reason"` // reject_review only
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if len(req.IDs) == 0 || len(req.IDs) > 100 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	reason := strings.TrimSpace(req.Reason)
	if reason == "" {
		reason = "Rejected by admin"
	}
	if len(reason) > 280 {
		reason = reason[:280]
	}

	var apply func(ctx context.Context, id int64) error
	switch req.Action {
	case "delete":
		apply = h.wallpaperRepo.Delete
	case "hard_delete":
		apply = h.hardDeleteOne
	case "approve_review":
		apply = func(ctx context.Context, id int64) error {
			if ec := h.wallpaperSvc.ApproveReview(ctx, id); ec != nil {
				return errors.New(ec.Message)
			}
			return nil
		}
	case "reject_review":
		apply = func(ctx context.Context, id int64) error {
			return h.wallpaperRepo.AdminReject(ctx, id, reason)
		}
	default:
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	type batchFailure struct {
		ID    int64  `json:"id"`
		Error string `json:"error"`
	}
	succeeded := make([]int64, 0, len(req.IDs))
	failed := make([]batchFailure, 0)
	seen := make(map[int64]bool, len(req.IDs))
	for _, id := range req.IDs {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		if err := apply(r.Context(), id); err != nil {
			slog.WarnContext(r.Context(), "admin batch action failed",
				"action", req.Action, "id", id, "error", err)
			failed = append(failed, batchFailure{ID: id, Error: err.Error()})
			continue
		}
		succeeded = append(succeeded, id)
	}

	slog.InfoContext(r.Context(), "admin batch action done",
		"action", req.Action, "succeeded", len(succeeded), "failed", len(failed))
	response.OK(w, map[string]any{
		"succeeded": succeeded,
		"failed":    failed,
	})
}

// ─── collections ─────────────────────────────────────────────────────────

func (h *AdminHandler) ListCollections(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	var isPublic *bool
	if v := q.Get("is_public"); v != "" {
		b := v == "true" || v == "1"
		isPublic = &b
	}
	var kind *int
	if v := q.Get("kind"); v != "" {
		k := parseIntDefault(v, -1)
		if k >= 0 {
			kind = &k
		}
	}

	rows, total, err := h.collectionRepo.AdminList(r.Context(), repo.AdminCollectionListOpts{
		Search:   q.Get("search"),
		OwnerID:  parseInt64Default(q.Get("user_id"), 0),
		IsPublic: isPublic,
		Kind:     kind,
		Offset:   (page - 1) * limit,
		Limit:    limit,
		Sort:     q.Get("sort"),
	})
	if err != nil {
		slog.ErrorContext(r.Context(), "admin collections list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

type adminUpdateCollectionReq struct {
	Title        *string  `json:"title"`
	Description  *string  `json:"description"`
	IsPublic     *bool    `json:"is_public"`
	Kind         *int16   `json:"kind"`
	Year         *int16   `json:"year"`
	Week         *int16   `json:"week"`
	AccentColor  *string  `json:"accent_color"`
	WallpaperIDs *[]int64 `json:"wallpaper_ids"`
}

type adminCreateCollectionReq struct {
	Title        string  `json:"title"`
	Description  string  `json:"description"`
	IsPublic     *bool   `json:"is_public"`
	Kind         int16   `json:"kind"`
	Year         int16   `json:"year"`
	Week         int16   `json:"week"`
	AccentColor  string  `json:"accent_color"`
	OwnerID      int64   `json:"owner_id"`
	WallpaperIDs []int64 `json:"wallpaper_ids"`
}

func (h *AdminHandler) UpdateCollection(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminUpdateCollectionReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if req.Kind != nil {
		if *req.Kind < 0 || *req.Kind > 1 {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
		if *req.Kind == 1 && req.Week != nil && (*req.Week < 1 || *req.Week > 53) {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
	}
	if req.WallpaperIDs != nil {
		strict := req.Kind != nil && *req.Kind == 1
		if ec := h.validateCollectionWallpaperIDs(r.Context(), *req.WallpaperIDs, strict); ec != nil {
			response.Error(w, http.StatusBadRequest, ec)
			return
		}
	}
	if err := h.collectionRepo.AdminUpdate(r.Context(), id, repo.AdminCollectionUpdate{
		Title:        req.Title,
		Description:  req.Description,
		IsPublic:     req.IsPublic,
		Kind:         req.Kind,
		Year:         req.Year,
		Week:         req.Week,
		AccentColor:  req.AccentColor,
		WallpaperIDs: req.WallpaperIDs,
	}); err != nil {
		slog.ErrorContext(r.Context(), "admin collection update failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

func (h *AdminHandler) GetCollection(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	detail, err := h.collectionRepo.AdminGet(r.Context(), id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		slog.ErrorContext(r.Context(), "admin collection get failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, detail)
}

func (h *AdminHandler) CreateCollection(w http.ResponseWriter, r *http.Request) {
	var req adminCreateCollectionReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	title := strings.TrimSpace(req.Title)
	if title == "" || len([]rune(title)) > 100 || req.Kind < 0 || req.Kind > 1 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if req.Kind == 1 && (req.Week < 1 || req.Week > 53 || req.Year <= 0) {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	isPublic := true
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}
	ownerID := req.OwnerID
	if ownerID <= 0 {
		ownerID = middleware.GetUserID(r.Context())
	}
	if ownerID <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if ec := h.validateCollectionWallpaperIDs(r.Context(), req.WallpaperIDs, req.Kind == 1); ec != nil {
		response.Error(w, http.StatusBadRequest, ec)
		return
	}
	col := &model.Collection{
		UserID:      ownerID,
		Title:       title,
		Description: strings.TrimSpace(req.Description),
		IsPublic:    isPublic,
		Kind:        req.Kind,
		Year:        req.Year,
		Week:        req.Week,
		AccentColor: strings.TrimSpace(req.AccentColor),
	}
	if err := h.collectionRepo.AdminCreate(r.Context(), col, req.WallpaperIDs); err != nil {
		slog.ErrorContext(r.Context(), "admin collection create failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.JSON(w, http.StatusCreated, errcode.Success, col)
}

func (h *AdminHandler) DeleteCollection(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.collectionRepo.AdminDelete(r.Context(), id); err != nil {
		slog.ErrorContext(r.Context(), "admin collection delete failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

func (h *AdminHandler) validateCollectionWallpaperIDs(ctx context.Context, ids []int64, strictQuality bool) *errcode.ErrCode {
	seen := map[int64]bool{}
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		wp, err := h.wallpaperRepo.GetByIDAnyStatus(ctx, id)
		if err != nil || wp == nil {
			return errcode.ErrNotFound
		}
		if wp.Status != model.WallpaperStatusPublished {
			return &errcode.ErrCode{Code: 40010, Message: "wallpaper is not published"}
		}
		if strictQuality && wp.QualityFlag != "" && wp.QualityFlag != "ok" {
			return &errcode.ErrCode{Code: 40011, Message: "wallpaper has not passed quality review"}
		}
		if strictQuality && (wp.ThumbURL == "" || wp.PreviewURL == "") {
			return &errcode.ErrCode{Code: 40012, Message: "wallpaper is not suitable for a featured collection"}
		}
	}
	return nil
}

// ─── users ───────────────────────────────────────────────────────────────

func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	status := parseIntDefault(q.Get("status"), -1)
	rows, total, err := h.userRepo.AdminListUsers(r.Context(), q.Get("search"), status, (page-1)*limit, limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin users list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

type adminGrantCoinsReq struct {
	Amount      int64  `json:"amount"`
	Description string `json:"description"`
}

func (h *AdminHandler) GrantUserCoins(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	var req adminGrantCoinsReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if req.Amount <= 0 || req.Amount > 1_000_000 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	desc := strings.TrimSpace(req.Description)
	if desc == "" {
		desc = "系统赠送"
	}
	if len([]rune(desc)) > 256 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	user, err := h.userRepo.GetByID(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin grant coins lookup failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if user == nil || user.ID <= 0 {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	adminID := middleware.GetUserID(r.Context())
	balance, err := h.coinRepo.Transfer(
		r.Context(),
		repo.SystemUserID,
		id,
		req.Amount,
		model.CoinTxAdminGrant,
		model.CoinTxAdminGrant,
		adminID,
		desc,
		desc,
	)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin grant coins failed",
			"user_id", id, "admin_id", adminID, "amount", req.Amount, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"user_id": id,
		"amount":  req.Amount,
		"balance": balance,
	})
}

type adminSetAdminReq struct {
	IsAdmin bool `json:"is_admin"`
}

func (h *AdminHandler) SetUserAdmin(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminSetAdminReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	// Don't allow self-demote — admin would lock themselves out.
	if !req.IsAdmin && id == middleware.GetUserID(r.Context()) {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.userRepo.AdminSetAdmin(r.Context(), id, req.IsAdmin); err != nil {
		slog.ErrorContext(r.Context(), "admin set is_admin failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

type adminSetStatusReq struct {
	Status int16 `json:"status"`
}

func (h *AdminHandler) SetUserStatus(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminSetStatusReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if id == middleware.GetUserID(r.Context()) && req.Status != 1 {
		// don't let admin ban themselves
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.userRepo.AdminSetStatus(r.Context(), id, req.Status); err != nil {
		slog.ErrorContext(r.Context(), "admin set status failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
}

// ─── reports ─────────────────────────────────────────────────────────────

func (h *AdminHandler) ListReports(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	status := int16(parseIntDefault(q.Get("status"), -1))
	rows, total, err := h.reportRepo.AdminList(r.Context(), repo.AdminReportListOpts{
		Status: status,
		Offset: (page - 1) * limit,
		Limit:  limit,
	})
	if err != nil {
		slog.ErrorContext(r.Context(), "admin reports list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

type adminResolveReportReq struct {
	Status              int16 `json:"status"`                 // 1=resolved, 2=rejected
	RemoveWallpaper     bool  `json:"remove_wallpaper"`       // also soft-delete the wallpaper
	ResolveAllForTarget bool  `json:"resolve_all_for_target"` // close every report on this wallpaper
}

func (h *AdminHandler) ResolveReport(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminResolveReportReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if req.Status != model.ReportStatusResolved && req.Status != model.ReportStatusRejected {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	rep, err := h.reportRepo.AdminGetByID(r.Context(), id)
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		slog.ErrorContext(r.Context(), "admin report get failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	if req.RemoveWallpaper && rep.WallpaperID > 0 {
		if err := h.wallpaperRepo.Delete(r.Context(), rep.WallpaperID); err != nil {
			slog.ErrorContext(r.Context(), "admin report -> wallpaper delete failed",
				"report_id", id, "wallpaper_id", rep.WallpaperID, "error", err)
		}
	}
	if err := h.reportRepo.AdminSetStatus(r.Context(), id, req.Status); err != nil {
		slog.ErrorContext(r.Context(), "admin report status update failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if req.ResolveAllForTarget && rep.WallpaperID > 0 {
		// Mark every still-open report on the same wallpaper as resolved
		// so the queue doesn't have duplicates lingering.
		_ = h.reportRepo.AdminResolveAllForWallpaper(r.Context(), rep.WallpaperID, req.Status)
	}
	response.OK(w, nil)
}

// ─── storage usage ───────────────────────────────────────────────────────

// GetStorage returns MinIO bucket totals + per-prefix breakdown. Walking the
// bucket is O(n) over objects (≈12k today), so we memoize the result for 5
// minutes; pass ?refresh=1 to force a fresh scan.
func (h *AdminHandler) GetStorage(w http.ResponseWriter, r *http.Request) {
	const ttl = 5 * time.Minute
	refresh := r.URL.Query().Get("refresh") == "1"

	// Disk usage is cheap (statfs, O(1)) and changes constantly, so we
	// query it every call — never cached. Failure is non-fatal; we just
	// omit the field and let the frontend hide the section.
	disk, diskErr := storage.Disk("/")
	if diskErr != nil {
		slog.WarnContext(r.Context(), "disk stat failed", "error", diskErr)
	}

	h.storageCacheMu.Lock()
	if !refresh && h.storageCache != nil && time.Since(h.storageCacheAt) < ttl {
		usage := h.storageCache
		age := time.Since(h.storageCacheAt)
		h.storageCacheMu.Unlock()
		response.OK(w, map[string]any{
			"usage":     usage,
			"disk":      disk,
			"cached":    true,
			"age_ms":    age.Milliseconds(),
			"refreshed": h.storageCacheAt.UTC(),
		})
		return
	}
	h.storageCacheMu.Unlock()

	// Walk the bucket outside the lock so concurrent reads aren't blocked.
	// Bucket scans against the internal MinIO endpoint take a couple seconds.
	usage, err := h.storage.Stats(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "storage stats failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	h.storageCacheMu.Lock()
	h.storageCache = usage
	h.storageCacheAt = time.Now()
	at := h.storageCacheAt
	h.storageCacheMu.Unlock()

	response.OK(w, map[string]any{
		"usage":     usage,
		"disk":      disk,
		"cached":    false,
		"age_ms":    0,
		"refreshed": at.UTC(),
	})
}

// ─── workers ─────────────────────────────────────────────────────────────

func (h *AdminHandler) WorkerSummary(w http.ResponseWriter, r *http.Request) {
	// Sweep ghosts before reporting: any "running" row older than 30 minutes
	// is the worker crashing/being killed before it called Finish(). We flip
	// it to failed so the dashboard shows accurate numbers.
	_ = h.workerJobRepo.SweepStale(r.Context(), 30*time.Minute)
	summary, err := h.workerJobRepo.Summary(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "worker summary failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"summary": summary})
}

func (h *AdminHandler) WorkerJobs(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	jobs, err := h.workerJobRepo.List(r.Context(), repo.WorkerJobListOpts{
		Worker: q.Get("worker"),
		Status: q.Get("status"),
		Limit:  parseIntDefault(q.Get("limit"), 100),
		Cursor: parseInt64Default(q.Get("cursor"), 0),
	})
	if err != nil {
		slog.ErrorContext(r.Context(), "worker jobs list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"items": jobs})
}

// extMIME mirrors the upload handler's table — needed because the admin
// AI-upload path does its own multipart parsing.
var aiUploadExtMIME = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
	".heic": "image/heic",
	".heif": "image/heif",
}

// UploadAIWallpaper accepts a multipart upload from cmd/aigen and
// publishes the file through the regular WallpaperService.Upload flow
// with is_ai_generated = true. Admin-only — the surrounding /admin
// route group enforces that already. The user_id on the row is the
// admin's own id (same as a normal upload by them).
func (h *AdminHandler) UploadAIWallpaper(w http.ResponseWriter, r *http.Request) {
	// 30 MB matches the public upload cap; AI generations are tiny in
	// practice (~3 MB for a 4K PNG) but we don't need a special limit.
	const maxAIUpload = 30 << 20
	if err := r.ParseMultipartForm(maxAIUpload); err != nil {
		slog.ErrorContext(r.Context(), "admin AI upload: parse form failed", "error", err)
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	defer file.Close()

	fileType := header.Header.Get("Content-Type")
	if fileType == "" || fileType == "application/octet-stream" {
		ext := strings.ToLower(filepath.Ext(header.Filename))
		if ct := mime.TypeByExtension(ext); ct != "" {
			fileType = ct
		} else if ct, ok := aiUploadExtMIME[ext]; ok {
			fileType = ct
		}
	}

	var categoryID int64
	if raw := r.FormValue("category_id"); raw != "" {
		if v, perr := strconv.ParseInt(raw, 10, 64); perr == nil {
			categoryID = v
		}
	}

	userID := middleware.GetUserID(r.Context())
	wp, ec := h.wallpaperSvc.Upload(r.Context(), userID, service.UploadRequest{
		Title:         r.FormValue("title"),
		Description:   r.FormValue("description"),
		CategoryID:    categoryID,
		File:          file,
		FileSize:      header.Size,
		FileType:      fileType,
		FileName:      header.Filename,
		IsAIGenerated: true,
	})
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.JSON(w, http.StatusCreated, errcode.Success, wp)
}

// ─── Weekly picks ─────────────────────────────────────────────────────

func parseWeeklyRoute(r *http.Request) (int16, int16, bool) {
	year, err := strconv.Atoi(chi.URLParam(r, "year"))
	if err != nil || year <= 0 || year > 9999 {
		return 0, 0, false
	}
	week, err := strconv.Atoi(chi.URLParam(r, "week"))
	if err != nil || week < 1 || week > 53 {
		return 0, 0, false
	}
	return int16(year), int16(week), true
}

// ListWeeklyPickWeeks returns every (year, week) that has a slate, newest
// first, with the hero thumb / title attached. Drives the admin Weekly
// Picks index.
func (h *AdminHandler) ListWeeklyPickWeeks(w http.ResponseWriter, r *http.Request) {
	weeks, err := h.weeklyPickRepo.ListAllWeeks(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "list weekly weeks", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, weeks)
}

// GetWeeklyPickWeek returns the 10 picks for a specific (year, week),
// including is_hero markers. Used to render the admin edit view.
func (h *AdminHandler) GetWeeklyPickWeek(w http.ResponseWriter, r *http.Request) {
	year, week, ok := parseWeeklyRoute(r)
	if !ok {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	picks, err := h.weeklyPickRepo.ListByWeek(r.Context(), year, week)
	if err != nil {
		slog.ErrorContext(r.Context(), "list weekly", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"year": year, "week": week, "picks": picks})
}

type adminSaveWeeklyPickWeekReq struct {
	WallpaperIDs    []int64 `json:"wallpaper_ids"`
	HeroWallpaperID int64   `json:"hero_wallpaper_id"`
}

// SaveWeeklyPickWeek replaces one week's full slate in display order.
// This is the manual curation path: admins choose the exact wallpapers,
// order, and hero.
func (h *AdminHandler) SaveWeeklyPickWeek(w http.ResponseWriter, r *http.Request) {
	year, week, ok := parseWeeklyRoute(r)
	if !ok {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var req adminSaveWeeklyPickWeekReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	ids := dedupeInt64(req.WallpaperIDs)
	if len(ids) == 0 || len(ids) > 20 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if req.HeroWallpaperID == 0 {
		req.HeroWallpaperID = ids[0]
	}
	heroInSlate := false
	for _, id := range ids {
		if id == req.HeroWallpaperID {
			heroInSlate = true
			break
		}
	}
	if !heroInSlate {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	for _, id := range ids {
		if ec := h.validateWeeklyPickWallpaper(r.Context(), id); ec != nil {
			response.Error(w, http.StatusBadRequest, ec)
			return
		}
	}
	if err := h.weeklyPickRepo.Insert(r.Context(), year, week, ids); err != nil {
		slog.ErrorContext(r.Context(), "save weekly slate", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if err := h.weeklyPickRepo.SetHero(r.Context(), year, week, req.HeroWallpaperID); err != nil {
		slog.ErrorContext(r.Context(), "save weekly hero", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"ok": true})
}

// SetWeeklyPickHero flips the hero flag for one wallpaper inside a week.
// Body: {"wallpaper_id": <int64>}. The repo runs the swap in a transaction
// so the partial unique index can never see two TRUE rows at once.
func (h *AdminHandler) SetWeeklyPickHero(w http.ResponseWriter, r *http.Request) {
	year, week, ok := parseWeeklyRoute(r)
	if !ok {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var body struct {
		WallpaperID int64 `json:"wallpaper_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.WallpaperID == 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.weeklyPickRepo.SetHero(r.Context(), year, week, body.WallpaperID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		slog.ErrorContext(r.Context(), "set weekly hero", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"ok": true})
}

// AddWeeklyPick appends a single wallpaper to a week's slate at the end.
// Body: {"wallpaper_id": N}. Returns 409 if the wallpaper is already in
// the slate (duplicate per the UNIQUE (year, week, wallpaper_id)
// constraint).
func (h *AdminHandler) AddWeeklyPick(w http.ResponseWriter, r *http.Request) {
	year, week, ok := parseWeeklyRoute(r)
	if !ok {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	var body struct {
		WallpaperID int64 `json:"wallpaper_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil || body.WallpaperID == 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if ec := h.validateWeeklyPickWallpaper(r.Context(), body.WallpaperID); ec != nil {
		status := http.StatusBadRequest
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	if err := h.weeklyPickRepo.AddPick(r.Context(), year, week, body.WallpaperID); err != nil {
		if errors.Is(err, repo.ErrAlreadyPicked) {
			response.Error(w, http.StatusConflict, &errcode.ErrCode{Code: 40902, Message: "wallpaper is already in this week's slate"})
			return
		}
		slog.ErrorContext(r.Context(), "add weekly pick", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"ok": true})
}

// RemoveWeeklyPick deletes one wallpaper from a week's slate. If the
// removed pick was the hero, the repo promotes the next-lowest sort_order
// to hero automatically.
func (h *AdminHandler) RemoveWeeklyPick(w http.ResponseWriter, r *http.Request) {
	year, week, ok := parseWeeklyRoute(r)
	if !ok {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	wallpaperID, err := strconv.ParseInt(chi.URLParam(r, "wallpaperId"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if err := h.weeklyPickRepo.RemovePick(r.Context(), year, week, wallpaperID); err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
			return
		}
		slog.ErrorContext(r.Context(), "remove weekly pick", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{"ok": true})
}

func (h *AdminHandler) validateWeeklyPickWallpaper(ctx context.Context, id int64) *errcode.ErrCode {
	wp, err := h.wallpaperRepo.GetByIDAnyStatus(ctx, id)
	if err != nil || wp == nil {
		return errcode.ErrNotFound
	}
	if wp.Status != model.WallpaperStatusPublished {
		return &errcode.ErrCode{Code: 40010, Message: "wallpaper is not published"}
	}
	if wp.QualityFlag != "" && wp.QualityFlag != "ok" {
		return &errcode.ErrCode{Code: 40011, Message: "wallpaper has not passed quality review"}
	}
	if wp.ThumbURL == "" || wp.PreviewURL == "" || wp.Width <= 0 || wp.Height <= 0 ||
		int64(wp.Width)*int64(wp.Height) < 2000000 || min(wp.Width, wp.Height) < 900 {
		return &errcode.ErrCode{Code: 40012, Message: "wallpaper is not suitable for weekly picks"}
	}
	return nil
}

func dedupeInt64(ids []int64) []int64 {
	out := make([]int64, 0, len(ids))
	seen := make(map[int64]bool, len(ids))
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}
