package handler

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type UserHandler struct {
	userRepo        *repo.UserRepo
	wallpaperRepo   *repo.WallpaperRepo
	interactionRepo *repo.InteractionRepo
}

func NewUserHandler(ur *repo.UserRepo, wr *repo.WallpaperRepo, ir *repo.InteractionRepo) *UserHandler {
	return &UserHandler{
		userRepo:        ur,
		wallpaperRepo:   wr,
		interactionRepo: ir,
	}
}

func (h *UserHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	user, err := h.userRepo.GetByID(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to get user", "error", err, "user_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if user == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	response.OK(w, user)
}

func (h *UserHandler) GetWallpapers(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	currentUserID := middleware.GetUserID(r.Context())
	isOwner := currentUserID == id

	opts := repo.ListOptions{
		Cursor: cursor,
		Limit:  fetchLimit,
		UserID: id,
	}
	if isOwner {
		opts.IncludeAllActive = true
	} else {
		opts.Status = model.WallpaperStatusPublished
	}

	items, err := h.wallpaperRepo.List(r.Context(), opts)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list user wallpapers",
			"error", err, "user_id", id)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	response.OK(w, map[string]any{
		"items":       items,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}

func (h *UserHandler) GetFavorites(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	cursor, limit := parseCursorLimit(r)
	fetchLimit := limit + 1

	items, err := h.interactionRepo.ListFavorites(r.Context(), userID, cursor, fetchLimit)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list favorites",
			"error", err, "user_id", userID)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	response.OK(w, map[string]any{
		"items":       items,
		"next_cursor": nextCursor,
		"has_more":    hasMore,
	})
}

func parseCursorLimit(r *http.Request) (int64, int) {
	var cursor int64
	if raw := r.URL.Query().Get("cursor"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err == nil {
			cursor = v
		}
	}

	limit := 20
	if raw := r.URL.Query().Get("limit"); raw != "" {
		v, err := strconv.Atoi(raw)
		if err == nil {
			limit = v
		}
	}
	if limit <= 0 || limit > 50 {
		limit = 20
	}

	return cursor, limit
}
