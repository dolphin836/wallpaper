package handler

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"log/slog"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

type CollectionHandler struct {
	collectionSvc   *service.CollectionService
	interactionRepo *repo.InteractionRepo
}

func NewCollectionHandler(collectionSvc *service.CollectionService, interactionRepo *repo.InteractionRepo) *CollectionHandler {
	return &CollectionHandler{collectionSvc: collectionSvc, interactionRepo: interactionRepo}
}

type createCollectionRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	IsPublic    *bool  `json:"is_public"`
}

type updateCollectionRequest struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	IsPublic    *bool  `json:"is_public"`
}

type addWallpaperRequest struct {
	WallpaperID int64 `json:"wallpaper_id"`
}

func (h *CollectionHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}

	isPublic := true
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}

	userID := middleware.GetUserID(r.Context())
	c, ec := h.collectionSvc.Create(r.Context(), userID, req.Title, req.Description, isPublic)
	if ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrInvalidParam.Code {
			status = http.StatusBadRequest
		}
		response.Error(w, status, ec)
		return
	}
	response.JSON(w, http.StatusCreated, errcode.Success, c)
}

func (h *CollectionHandler) List(w http.ResponseWriter, r *http.Request) {
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

	userID := middleware.GetUserID(r.Context())
	resp, ec := h.collectionSvc.List(r.Context(), cursor, limit, userID)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, resp)
}

func (h *CollectionHandler) Get(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	detail, ec := h.collectionSvc.Get(r.Context(), id, userID)
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

func (h *CollectionHandler) Update(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	var req updateCollectionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}

	isPublic := true
	if req.IsPublic != nil {
		isPublic = *req.IsPublic
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.Update(r.Context(), id, userID, req.Title, req.Description, isPublic); ec != nil {
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

func (h *CollectionHandler) Delete(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.Delete(r.Context(), id, userID); ec != nil {
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

func (h *CollectionHandler) AddWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	var req addWallpaperRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	if req.WallpaperID <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.AddWallpaper(r.Context(), id, req.WallpaperID, userID); ec != nil {
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

func (h *CollectionHandler) RemoveWallpaper(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	wid, err := strconv.ParseInt(chi.URLParam(r, "wid"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.RemoveWallpaper(r.Context(), id, wid, userID); ec != nil {
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

func (h *CollectionHandler) Like(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.Like(r.Context(), userID, id); ec != nil {
		status := http.StatusInternalServerError
		if ec.Code == errcode.ErrNotFound.Code {
			status = http.StatusNotFound
		}
		response.Error(w, status, ec)
		return
	}
	response.OK(w, nil)
}

func (h *CollectionHandler) Unlike(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if ec := h.collectionSvc.Unlike(r.Context(), userID, id); ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, nil)
}

func (h *CollectionHandler) ListWallpapers(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

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

	resp, ec := h.collectionSvc.ListWallpapers(r.Context(), id, cursor, limit)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	currentUserID := middleware.GetUserID(r.Context())

	type wallpaperWithStatus struct {
		model.Wallpaper
		IsLiked      bool `json:"is_liked"`
		IsFavorited  bool `json:"is_favorited"`
		IsDownloaded bool `json:"is_downloaded"`
	}

	items := make([]wallpaperWithStatus, len(resp.Items))
	wpIDs := make([]int64, len(resp.Items))
	for i := range resp.Items {
		if currentUserID <= 0 || currentUserID != resp.Items[i].UserID {
			resp.Items[i].OriginalURL = ""
		}
		wpIDs[i] = resp.Items[i].ID
		items[i] = wallpaperWithStatus{Wallpaper: resp.Items[i]}
	}

	if currentUserID > 0 && len(wpIDs) > 0 {
		if likedMap, err := h.interactionRepo.BatchIsLiked(r.Context(), currentUserID, wpIDs); err != nil {
			slog.ErrorContext(r.Context(), "batch check likes failed", "error", err)
		} else {
			for i := range items {
				items[i].IsLiked = likedMap[items[i].ID]
			}
		}
		if favMap, err := h.interactionRepo.BatchIsFavorited(r.Context(), currentUserID, wpIDs); err != nil {
			slog.ErrorContext(r.Context(), "batch check favorites failed", "error", err)
		} else {
			for i := range items {
				items[i].IsFavorited = favMap[items[i].ID]
			}
		}
		if dlMap, err := h.interactionRepo.BatchHasDownloaded(r.Context(), currentUserID, wpIDs); err != nil {
			slog.ErrorContext(r.Context(), "batch check downloads failed", "error", err)
		} else {
			for i := range items {
				items[i].IsDownloaded = dlMap[items[i].ID]
			}
		}
	}

	response.OK(w, map[string]any{
		"items":       items,
		"next_cursor": resp.NextCursor,
		"has_more":    resp.HasMore,
	})
}

func (h *CollectionHandler) ListMyCollections(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	items, ec := h.collectionSvc.ListUserCollections(r.Context(), userID)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, items)
}

func (h *CollectionHandler) ListUserCollections(w http.ResponseWriter, r *http.Request) {
	ownerID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

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

	resp, ec := h.collectionSvc.ListByUser(r.Context(), ownerID, cursor, limit)
	if ec != nil {
		response.Error(w, http.StatusInternalServerError, ec)
		return
	}
	response.OK(w, resp)
}
