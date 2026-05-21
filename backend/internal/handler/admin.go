package handler

import (
	"encoding/json"
	"errors"
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
	wallpaperRepo  *repo.WallpaperRepo
	collectionRepo *repo.CollectionRepo
	reportRepo     *repo.ReportRepo
	workerJobRepo  *repo.WorkerJobRepo
	categoryRepo   *repo.CategoryRepo
	analyticsRepo  *repo.AnalyticsRepo
	llmUsageRepo   *repo.LLMUsageRepo
	storage        *storage.Storage
	wallpaperSvc   *service.WallpaperService // needed for Reprocess (Kafka re-publish)

	storageCacheMu sync.Mutex
	storageCache   *storage.BucketUsage
	storageCacheAt time.Time
}

func NewAdminHandler(
	adminRepo *repo.AdminRepo,
	userRepo *repo.UserRepo,
	wallpaperRepo *repo.WallpaperRepo,
	collectionRepo *repo.CollectionRepo,
	reportRepo *repo.ReportRepo,
	workerJobRepo *repo.WorkerJobRepo,
	categoryRepo *repo.CategoryRepo,
	analyticsRepo *repo.AnalyticsRepo,
	llmUsageRepo *repo.LLMUsageRepo,
	store *storage.Storage,
	wallpaperSvc *service.WallpaperService,
) *AdminHandler {
	return &AdminHandler{
		adminRepo:      adminRepo,
		userRepo:       userRepo,
		wallpaperRepo:  wallpaperRepo,
		collectionRepo: collectionRepo,
		reportRepo:     reportRepo,
		workerJobRepo:  workerJobRepo,
		categoryRepo:   categoryRepo,
		analyticsRepo:  analyticsRepo,
		llmUsageRepo:   llmUsageRepo,
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

// HardDeleteWallpaper physically removes a wallpaper row, its children and
// its MinIO objects. Restricted to rows that are already off the public
// surface — status=removed (soft-deleted) or status=duplicate. Trying to
// hard-delete a live (published / processing / failed) row is rejected,
// so an admin has to soft-delete first if they really mean to nuke it.
// The two-step path keeps an accidental click from atomically destroying
// a live wallpaper plus every like/favorite/download attached to it.
//
// MinIO deletions are best-effort: if a key is missing or the storage
// layer hiccups, we log and continue. The DB cleanup already committed,
// so the row + children are gone either way; an orphaned object will
// just sit in MinIO until the next cleanup sweep.
func (h *AdminHandler) HardDeleteWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	// GetByID filters out status=removed, so we need a raw lookup that sees
	// every status — hard-delete operates on rows the public API has already
	// hidden.
	existing, err := h.wallpaperRepo.GetByIDAnyStatus(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin hard-delete lookup failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if existing == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	if existing.Status != model.WallpaperStatusRemoved && existing.Status != model.WallpaperStatusDuplicate {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	deleted, err := h.wallpaperRepo.AdminHardDelete(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin hard-delete failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
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
		if err := h.storage.Delete(r.Context(), key); err != nil {
			slog.WarnContext(r.Context(), "minio delete failed (continuing)", "key", key, "error", err)
		}
	}

	slog.InfoContext(r.Context(), "wallpaper hard-deleted",
		"id", id, "slug", wp.Slug,
		"variant_count", len(deleted.VariantURLs),
		"object_count", len(objectURLs))
	response.OK(w, nil)
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

	rows, total, err := h.collectionRepo.AdminList(r.Context(), repo.AdminCollectionListOpts{
		Search:   q.Get("search"),
		OwnerID:  parseInt64Default(q.Get("user_id"), 0),
		IsPublic: isPublic,
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
	Title       *string `json:"title"`
	Description *string `json:"description"`
	IsPublic    *bool   `json:"is_public"`
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
	if err := h.collectionRepo.AdminUpdate(r.Context(), id, repo.AdminCollectionUpdate{
		Title:       req.Title,
		Description: req.Description,
		IsPublic:    req.IsPublic,
	}); err != nil {
		slog.ErrorContext(r.Context(), "admin collection update failed", "id", id, "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, nil)
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
	Status              int16 `json:"status"`                // 1=resolved, 2=rejected
	RemoveWallpaper     bool  `json:"remove_wallpaper"`      // also soft-delete the wallpaper
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
