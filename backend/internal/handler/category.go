package handler

import (
	"log/slog"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type CategoryHandler struct {
	categoryRepo *repo.CategoryRepo
}

func NewCategoryHandler(categoryRepo *repo.CategoryRepo) *CategoryHandler {
	return &CategoryHandler{categoryRepo: categoryRepo}
}

func (h *CategoryHandler) List(w http.ResponseWriter, r *http.Request) {
	categories, err := h.categoryRepo.List(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "failed to list categories", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, categories)
}
