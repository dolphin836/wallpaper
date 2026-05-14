package handler

import (
	"log/slog"
	"math"
	"net/http"
	"sort"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type RecommendHandler struct {
	wallpaperRepo *repo.WallpaperRepo
}

func NewRecommendHandler(wpRepo *repo.WallpaperRepo) *RecommendHandler {
	return &RecommendHandler{wallpaperRepo: wpRepo}
}

const (
	similarDefaultLimit = 12
	similarMaxLimit     = 24
	// Max possible distance between two 24-bit colors in linear RGB.
	maxRGBDist = 441.673 // sqrt(255^2 * 3)
	// Color and tag weights; sum to 1.0. Tag overlap is a stronger signal so it
	// outweighs raw color similarity.
	weightColor = 0.45
	weightTag   = 0.55
	// Beyond this many shared tags, additional overlap doesn't add much signal.
	tagOverlapCap = 4
)

func (h *RecommendHandler) Similar(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || id <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	limit := similarDefaultLimit
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 && v <= similarMaxLimit {
			limit = v
		}
	}

	target, err := h.wallpaperRepo.GetByID(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "similar: get target failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if target == nil || target.Status != model.WallpaperStatusPublished {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	candidates, err := h.wallpaperRepo.ListPublishedColors(r.Context(), id)
	if err != nil {
		slog.ErrorContext(r.Context(), "similar: list candidates failed", "error", err)
		response.OK(w, []model.Wallpaper{})
		return
	}
	if len(candidates) == 0 {
		response.OK(w, []model.Wallpaper{})
		return
	}

	tagOverlap, err := h.wallpaperRepo.TagOverlapWith(r.Context(), id)
	if err != nil {
		// Tag enrichment is optional; color-only ranking still produces a useful result.
		slog.WarnContext(r.Context(), "similar: tag overlap failed", "error", err)
		tagOverlap = map[int64]int{}
	}

	targetRGB, ok := parseHexColor(target.DominantColor)
	type scored struct {
		id    int64
		score float64
	}
	scoredList := make([]scored, 0, len(candidates))
	for _, c := range candidates {
		colorScore := 0.0
		if ok {
			if cRGB, cok := parseHexColor(c.DominantColor); cok {
				dist := rgbDistance(targetRGB, cRGB)
				colorScore = 1 - dist/maxRGBDist
				if colorScore < 0 {
					colorScore = 0
				}
			}
		}
		tagScore := math.Min(float64(tagOverlap[c.ID])/tagOverlapCap, 1.0)
		score := weightColor*colorScore + weightTag*tagScore
		scoredList = append(scoredList, scored{c.ID, score})
	}
	sort.Slice(scoredList, func(i, j int) bool { return scoredList[i].score > scoredList[j].score })
	if len(scoredList) > limit {
		scoredList = scoredList[:limit]
	}

	topIDs := make([]int64, len(scoredList))
	for i, s := range scoredList {
		topIDs[i] = s.id
	}
	results, err := h.wallpaperRepo.GetByIDs(r.Context(), topIDs)
	if err != nil {
		slog.ErrorContext(r.Context(), "similar: get by ids failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	byID := make(map[int64]model.Wallpaper, len(results))
	for _, wp := range results {
		byID[wp.ID] = wp
	}
	ordered := make([]model.Wallpaper, 0, len(topIDs))
	for _, id := range topIDs {
		if wp, ok := byID[id]; ok {
			ordered = append(ordered, wp)
		}
	}
	response.OK(w, ordered)
}

// parseHexColor accepts "#RRGGBB" and returns r,g,b in [0,255].
func parseHexColor(s string) ([3]int, bool) {
	if len(s) != 7 || s[0] != '#' {
		return [3]int{}, false
	}
	r, errR := strconv.ParseInt(s[1:3], 16, 32)
	g, errG := strconv.ParseInt(s[3:5], 16, 32)
	b, errB := strconv.ParseInt(s[5:7], 16, 32)
	if errR != nil || errG != nil || errB != nil {
		return [3]int{}, false
	}
	return [3]int{int(r), int(g), int(b)}, true
}

func rgbDistance(a, b [3]int) float64 {
	dr := float64(a[0] - b[0])
	dg := float64(a[1] - b[1])
	db := float64(a[2] - b[2])
	return math.Sqrt(dr*dr + dg*dg + db*db)
}
