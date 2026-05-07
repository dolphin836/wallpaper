package handler

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type DeviceHandler struct {
	deviceRepo    *repo.DeviceRepo
	eventRepo     *repo.EventRepo
	wallpaperRepo *repo.WallpaperRepo
	coinRepo      *repo.CoinRepo
}

func NewDeviceHandler(deviceRepo *repo.DeviceRepo, eventRepo *repo.EventRepo, wallpaperRepo *repo.WallpaperRepo, coinRepo *repo.CoinRepo) *DeviceHandler {
	return &DeviceHandler{
		deviceRepo:    deviceRepo,
		eventRepo:     eventRepo,
		wallpaperRepo: wallpaperRepo,
		coinRepo:      coinRepo,
	}
}

func (h *DeviceHandler) ListDevices(w http.ResponseWriter, r *http.Request) {
	devices, err := h.deviceRepo.ListAll(r.Context())
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, devices)
}

func (h *DeviceHandler) ListVariants(w http.ResponseWriter, r *http.Request) {
	wallpaperID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	variants, err := h.deviceRepo.ListVariantsByWallpaper(r.Context(), wallpaperID)
	if err != nil {
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, variants)
}

func (h *DeviceHandler) DownloadVariant(w http.ResponseWriter, r *http.Request) {
	wallpaperID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	variantID, err := strconv.ParseInt(chi.URLParam(r, "vid"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	variant, err := h.deviceRepo.GetVariant(r.Context(), variantID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get variant", "error", err, "variant_id", variantID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if variant == nil || variant.WallpaperID != wallpaperID {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	userID := middleware.GetUserID(r.Context())

	wp, err := h.wallpaperRepo.GetByID(r.Context(), wallpaperID)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get wallpaper for coin check", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	isOwner := wp != nil && wp.UserID == userID
	if !isOwner && wp != nil {
		if _, err := h.coinRepo.Transfer(r.Context(), userID, wp.UserID, 1,
			"download_cost", "download_earned", wallpaperID,
			"Download wallpaper variant", "Wallpaper variant downloaded by others"); err != nil {
			response.Error(w, http.StatusPaymentRequired, errcode.ErrInsufficientCoins)
			return
		}
	}

	if err := h.deviceRepo.IncrementVariantDownload(r.Context(), variantID); err != nil {
		slog.ErrorContext(r.Context(), "failed to increment variant download count", "error", err, "variant_id", variantID)
	}

	if err := h.eventRepo.Record(r.Context(), wallpaperID, "variant_download", userID, &variantID); err != nil {
		slog.ErrorContext(r.Context(), "failed to record variant download event", "error", err, "wallpaper_id", wallpaperID, "variant_id", variantID)
	}

	http.Redirect(w, r, variant.URL, http.StatusFound)
}
