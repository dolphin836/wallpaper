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
	deviceRepo *repo.DeviceRepo
}

func NewDeviceHandler(deviceRepo *repo.DeviceRepo) *DeviceHandler {
	return &DeviceHandler{deviceRepo: deviceRepo}
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
