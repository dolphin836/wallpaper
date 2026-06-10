package handler

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/wallpaper/backend/internal/cache"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

// categoriesTTL can be generous: categories are seeded in init.sql and have
// no mutation endpoint, so the cache only ever lags a manual SQL edit.
const categoriesTTL = 10 * time.Minute

type CategoryHandler struct {
	categoryRepo *repo.CategoryRepo
	cache        *cache.Cache
}

func NewCategoryHandler(categoryRepo *repo.CategoryRepo, c *cache.Cache) *CategoryHandler {
	return &CategoryHandler{categoryRepo: categoryRepo, cache: c}
}

func (h *CategoryHandler) List(w http.ResponseWriter, r *http.Request) {
	if h.cache != nil {
		var cached []model.Category
		if err := h.cache.Get(r.Context(), cache.CategoriesKey(), &cached); err == nil {
			response.OK(w, cached)
			return
		}
	}

	categories, err := h.categoryRepo.List(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list categories", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	if h.cache != nil {
		if err := h.cache.Set(r.Context(), cache.CategoriesKey(), categories, categoriesTTL); err != nil {
			slog.WarnContext(r.Context(), "cache categories failed (non-fatal)", "error", err)
		}
	}
	response.OK(w, categories)
}
