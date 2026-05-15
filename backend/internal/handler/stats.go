package handler

import (
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

// StatsHandler serves the public masthead counts used by Discover's header
// strip. Wallpapers + collections only — anything else lives on the admin
// dashboard. Cached in-process for 60s so opening Discover doesn't fan two
// extra count queries on every page load.
type StatsHandler struct {
	wallpaperRepo  *repo.WallpaperRepo
	collectionRepo *repo.CollectionRepo

	mu       sync.Mutex
	cached   statsResponse
	cachedAt time.Time
}

func NewStatsHandler(wp *repo.WallpaperRepo, cl *repo.CollectionRepo) *StatsHandler {
	return &StatsHandler{wallpaperRepo: wp, collectionRepo: cl}
}

type statsResponse struct {
	Wallpapers  int64 `json:"wallpapers"`
	Collections int64 `json:"collections"`
}

func (h *StatsHandler) Get(w http.ResponseWriter, r *http.Request) {
	const ttl = 60 * time.Second
	h.mu.Lock()
	if !h.cachedAt.IsZero() && time.Since(h.cachedAt) < ttl {
		resp := h.cached
		h.mu.Unlock()
		response.OK(w, resp)
		return
	}
	h.mu.Unlock()

	wpCount, err := h.wallpaperRepo.Count(r.Context(), repo.ListOptions{Status: model.WallpaperStatusPublished})
	if err != nil {
		slog.ErrorContext(r.Context(), "stats: wallpaper count failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	collCount, err := h.collectionRepo.CountPublic(r.Context())
	if err != nil {
		slog.ErrorContext(r.Context(), "stats: collection count failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	resp := statsResponse{Wallpapers: wpCount, Collections: collCount}

	h.mu.Lock()
	h.cached = resp
	h.cachedAt = time.Now()
	h.mu.Unlock()

	response.OK(w, resp)
}
