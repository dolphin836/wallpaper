package handler

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
)

func (h *AdminHandler) ListLoginLogs(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	page, limit := parsePage(q)
	client := normalizeClient(q.Get("client"))

	rows, total, err := h.loginLogRepo.AdminList(r.Context(), client, (page-1)*limit, limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin login logs list failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit,
	})
}

func (h *AdminHandler) GetWallpaperTraffic(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	q := r.URL.Query()
	page, limit := parsePage(q)
	eventType := q.Get("event_type")
	switch eventType {
	case "", "view", "like", "favorite", "download":
	default:
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	rows, total, summary, err := h.eventRepo.AdminListWallpaperTraffic(r.Context(), id, eventType, (page-1)*limit, limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "admin wallpaper traffic failed", "error", err, "wallpaper_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"items": rows, "total": total, "page": page, "limit": limit, "summary": summary,
	})
}
