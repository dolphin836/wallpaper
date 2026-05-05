package handler

import (
	"log/slog"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type TagHandler struct {
	tagRepo *repo.TagRepo
}

func NewTagHandler(tagRepo *repo.TagRepo) *TagHandler {
	return &TagHandler{tagRepo: tagRepo}
}

func (h *TagHandler) Popular(w http.ResponseWriter, r *http.Request) {
	tags, err := h.tagRepo.Popular(r.Context(), 50)
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list popular tags", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, tags)
}
