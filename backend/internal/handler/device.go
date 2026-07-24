package handler

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type DeviceHandler struct {
	deviceRepo      *repo.DeviceRepo
	eventRepo       *repo.EventRepo
	wallpaperRepo   *repo.WallpaperRepo
	coinRepo        *repo.CoinRepo
	interactionRepo *repo.InteractionRepo
}

func NewDeviceHandler(deviceRepo *repo.DeviceRepo, eventRepo *repo.EventRepo, wallpaperRepo *repo.WallpaperRepo, coinRepo *repo.CoinRepo, interactionRepo *repo.InteractionRepo) *DeviceHandler {
	return &DeviceHandler{
		deviceRepo:      deviceRepo,
		eventRepo:       eventRepo,
		wallpaperRepo:   wallpaperRepo,
		coinRepo:        coinRepo,
		interactionRepo: interactionRepo,
	}
}

func (h *DeviceHandler) ListDevices(w http.ResponseWriter, r *http.Request) {
	// Returns active devices enriched with a per-device wallpaper count.
	// Used by the /wallpapers-for hub page; variant generation paths
	// still call ListAll directly when they need every device.
	devices, err := h.deviceRepo.ListActiveWithCounts(r.Context())
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, devices)
}

// GetDeviceBySlug returns the device profile + a total wallpaper count
// for the device-specific landing page (/wallpapers-for/:slug).
func (h *DeviceHandler) GetDeviceBySlug(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")
	if slug == "" {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	device, err := h.deviceRepo.GetBySlug(r.Context(), slug)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if device == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	count, err := h.deviceRepo.CountWallpapersForDevice(r.Context(), device.ID, parseWallpaperExclusions(r))
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"device":          device,
		"wallpaper_count": count,
	})
}

// ListWallpapersForDevice paginates published wallpapers that have a
// variant for the given device slug. Cursor is the last wallpaper id
// from the previous page (newest-first ordering).
func (h *DeviceHandler) ListWallpapersForDevice(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")
	if slug == "" {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	device, err := h.deviceRepo.GetBySlug(r.Context(), slug)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if device == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	cursor, _ := strconv.ParseInt(r.URL.Query().Get("cursor"), 10, 64)
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	items, err := h.deviceRepo.ListWallpapersForDevice(r.Context(), device.ID, cursor, limit, parseWallpaperExclusions(r))
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	var nextCursor int64
	hasMore := len(items) == limit
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	response.OK(w, map[string]any{
		"items":       items,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}
