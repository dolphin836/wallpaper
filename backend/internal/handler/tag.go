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

// popularTagsTTL trades a few minutes of staleness on the tag cloud for
// skipping the wallpaper_tags aggregate on every page load.
const popularTagsTTL = 5 * time.Minute

type TagHandler struct {
	tagRepo *repo.TagRepo
	cache   *cache.Cache
}

func NewTagHandler(tagRepo *repo.TagRepo, c *cache.Cache) *TagHandler {
	return &TagHandler{tagRepo: tagRepo, cache: c}
}

func (h *TagHandler) Popular(w http.ResponseWriter, r *http.Request) {
	lang := requestLang(r)
	if h.cache != nil {
		var cached []model.Tag
		if err := h.cache.Get(r.Context(), cache.PopularTagsKey(lang), &cached); err == nil {
			response.OK(w, cached)
			return
		}
	}

	tags, err := h.tagRepo.Popular(r.Context(), 50)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list popular tags", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	localizeTags(lang, tags)

	if h.cache != nil {
		if err := h.cache.Set(r.Context(), cache.PopularTagsKey(lang), tags, popularTagsTTL); err != nil {
			slog.WarnContext(r.Context(), "cache popular tags failed (non-fatal)", "error", err)
		}
	}
	response.OK(w, tags)
}
