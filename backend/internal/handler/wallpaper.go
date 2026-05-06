package handler

import (
	"log/slog"
	"net/http"
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

type WallpaperHandler struct {
	wallpaperSvc *service.WallpaperService
}

func NewWallpaperHandler(wallpaperSvc *service.WallpaperService) *WallpaperHandler {
	return &WallpaperHandler{wallpaperSvc: wallpaperSvc}
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

	req := service.UploadRequest{
		Title:       r.FormValue("title"),
		Description: r.FormValue("description"),
		CategoryID:  categoryID,
		Tags:        tags,
		File:        file,
		FileSize:    header.Size,
		FileType:    header.Header.Get("Content-Type"),
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
	if limit <= 0 || limit > 50 {
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

	var deviceWidth, deviceHeight int
	if raw := q.Get("device_width"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err == nil {
			deviceWidth = v
		}
	}
	if raw := q.Get("device_height"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err == nil {
			deviceHeight = v
		}
	}

	opts := repo.ListOptions{
		Cursor:       cursor,
		Limit:        limit,
		CategoryID:   categoryID,
		Sort:         q.Get("sort"),
		Search:       q.Get("search"),
		DeviceWidth:  deviceWidth,
		DeviceHeight: deviceHeight,
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
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())

	detail, ec := h.wallpaperSvc.Get(r.Context(), id, userID)
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, detail)
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
	if ec := h.wallpaperSvc.Like(r.Context(), userID, id); ec != nil {
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
	if ec := h.wallpaperSvc.Favorite(r.Context(), userID, id); ec != nil {
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

	url, ec := h.wallpaperSvc.Download(r.Context(), id)
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	http.Redirect(w, r, url, http.StatusFound)
}
