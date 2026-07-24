package handler

import (
	"log/slog"
	"mime"
	"net/http"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

const maxUploadSize = 200 << 20

var extMIME = map[string]string{
	".heic": "image/heic",
	".heif": "image/heif",
	".avif": "image/avif",
}

type WallpaperHandler struct {
	wallpaperSvc *service.WallpaperService
	mediaHandler *MediaHandler
}

func NewWallpaperHandler(wallpaperSvc *service.WallpaperService, mediaHandler *MediaHandler) *WallpaperHandler {
	return &WallpaperHandler{wallpaperSvc: wallpaperSvc, mediaHandler: mediaHandler}
}

func (h *WallpaperHandler) Upload(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseMultipartForm(maxUploadSize); err != nil {
		slog.ErrorContext(r.Context(), "parse multipart form failed", "error", err)
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		slog.ErrorContext(r.Context(), "get form file failed", "error", err)
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	defer func() {
		if err := file.Close(); err != nil {
			slog.ErrorContext(r.Context(), "failed to close uploaded file", "error", err)
		}
	}()

	var categoryID int64
	if raw := r.FormValue("category_id"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
		categoryID = v
	}

	var tags []string
	if raw := r.FormValue("tags"); raw != "" {
		for _, t := range strings.Split(raw, ",") {
			t = strings.TrimSpace(t)
			if t != "" {
				tags = append(tags, t)
			}
		}
	}

	userID := middleware.GetUserID(r.Context())

	fileType := header.Header.Get("Content-Type")
	if fileType == "" || fileType == "application/octet-stream" {
		ext := strings.ToLower(filepath.Ext(header.Filename))
		if ct := mime.TypeByExtension(ext); ct != "" {
			fileType = ct
		} else if ct, ok := extMIME[ext]; ok {
			fileType = ct
		}
	}

	req := service.UploadRequest{
		Title:       r.FormValue("title"),
		Description: r.FormValue("description"),
		CategoryID:  categoryID,
		Tags:        tags,
		File:        file,
		FileSize:    header.Size,
		FileType:    fileType,
		FileName:    header.Filename,
	}

	wp, ec := h.wallpaperSvc.Upload(r.Context(), userID, req)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.JSON(w, http.StatusCreated, errcode.Success, wp)
}

func (h *WallpaperHandler) List(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()

	var cursor int64
	if raw := q.Get("cursor"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
		cursor = v
	}

	limit := 20
	if raw := q.Get("limit"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err != nil {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
		limit = v
	}
	if limit <= 0 || limit > 200 {
		limit = 20
	}

	var categoryID int64
	if raw := q.Get("category_id"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
			return
		}
		categoryID = v
	}

	deviceWidth, deviceHeight := parseWallpaperDeviceRequirement(r)

	opts := repo.ListOptions{
		Cursor:         cursor,
		Limit:          limit,
		CategoryID:     categoryID,
		Sort:           q.Get("sort"),
		Search:         q.Get("search"),
		DeviceWidth:    deviceWidth,
		DeviceHeight:   deviceHeight,
		IncludeDynamic: q.Get("include_dynamic") == "true",
		DynamicOnly:    q.Get("dynamic_only") == "true",
		AIOnly:         q.Get("ai_only") == "true",
		VideoOnly:      q.Get("video_only") == "true",
		ExcludeDynamic: q.Get("exclude_dynamic") == "true",
		ExcludeVideo:   q.Get("exclude_video") == "true",
	}

	userID := middleware.GetUserID(r.Context())
	resp, ec := h.wallpaperSvc.List(r.Context(), opts, userID)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, resp)
}

func (h *WallpaperHandler) Get(w http.ResponseWriter, r *http.Request) {
	idOrSlug := chi.URLParam(r, "id")
	if idOrSlug == "" {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())

	detail, ec := h.wallpaperSvc.GetBySlug(r.Context(), idOrSlug, userID, requestEventMeta(r, "", ""))
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	mediaSession, err := h.mediaHandler.EnsureViewSession(w, r)
	if err != nil {
		slog.ErrorContext(r.Context(), "create anonymous media session failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if err := h.mediaHandler.DecorateOriginal(r, mediaSession, &detail.Wallpaper); err != nil {
		slog.ErrorContext(r.Context(), "sign original view failed", "error", err, "wallpaper_id", detail.ID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	localizeTags(requestLang(r), detail.Tags)
	response.OK(w, detail)
}

func (h *WallpaperHandler) GetEngagements(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	result, ec := h.wallpaperSvc.GetEngagements(r.Context(), id)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, result)
}

func (h *WallpaperHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())

	if ec := h.wallpaperSvc.Delete(r.Context(), id, userID); ec != nil {
		status := http.StatusInternalServerError
		switch ec.Code {
		case errcode.ErrNotFound.Code:
			status = http.StatusNotFound
		case errcode.ErrForbidden.Code:
			status = http.StatusForbidden
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *WallpaperHandler) Like(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.wallpaperSvc.Like(r.Context(), userID, id, requestEventMeta(r, "", "")); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *WallpaperHandler) Unlike(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.wallpaperSvc.Unlike(r.Context(), userID, id); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *WallpaperHandler) Favorite(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.wallpaperSvc.Favorite(r.Context(), userID, id, requestEventMeta(r, "", "")); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *WallpaperHandler) Unfavorite(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.wallpaperSvc.Unfavorite(r.Context(), userID, id); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *WallpaperHandler) Download(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())

	// Older clients still send ?width=&height= hints; they are accepted
	// and ignored — downloads always return the original now.
	wp, ec := h.wallpaperSvc.Download(r.Context(), id, userID, requestEventMeta(r, "", ""))
	if ec != nil {
		status := http.StatusInternalServerError
		switch ec.Code {
		case errcode.ErrNotFound.Code:
			status = http.StatusNotFound
		case errcode.ErrInsufficientCoins.Code:
			status = http.StatusPaymentRequired
		}
		response.Error(w, status, ec)
		return
	}
	url, err := h.mediaHandler.DownloadURL(r, wp)
	if err != nil {
		slog.ErrorContext(r.Context(), "sign original download failed", "error", err, "wallpaper_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	http.Redirect(w, r, url, http.StatusFound)
}

// ListSupportedDevices returns the device profiles a wallpaper can be
// downloaded for (original covers the device resolution). Drives the detail
// page's device picker. Empty for dynamic/video wallpapers.
func (h *WallpaperHandler) ListSupportedDevices(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	devices, ec := h.wallpaperSvc.ListSupportedDevices(r.Context(), id)
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, devices)
}

// DownloadForDevice charges the download and returns a JSON {url} sized for the
// given device, generating the variant on first request. The {vid} path slot
// carries the device id (the web client downloads by device, not variant id).
func (h *WallpaperHandler) DownloadForDevice(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	deviceID, err := strconv.ParseInt(chi.URLParam(r, "vid"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	userID := middleware.GetUserID(r.Context())
	wp, ec := h.wallpaperSvc.DownloadForDevice(r.Context(), id, deviceID, userID, requestEventMeta(r, "", ""))
	if ec != nil {
		status := http.StatusInternalServerError
		switch ec.Code {
		case errcode.ErrNotFound.Code:
			status = http.StatusNotFound
		case errcode.ErrInsufficientCoins.Code:
			status = http.StatusPaymentRequired
		}
		response.Error(w, status, ec)
		return
	}
	url, err := h.mediaHandler.DownloadURL(r, wp)
	if err != nil {
		slog.ErrorContext(r.Context(), "sign device download failed", "error", err, "wallpaper_id", id, "device_id", deviceID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]string{"url": url})
}
