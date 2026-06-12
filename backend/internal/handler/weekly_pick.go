package handler

import (
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type WeeklyPickHandler struct {
	weeklyRepo     *repo.WeeklyPickRepo
	collectionRepo *repo.CollectionRepo
}

func NewWeeklyPickHandler(wpr *repo.WeeklyPickRepo, cr *repo.CollectionRepo) *WeeklyPickHandler {
	return &WeeklyPickHandler{weeklyRepo: wpr, collectionRepo: cr}
}

// Current returns the latest weekly slate alongside the most recent
// editor-curated theme collections. The Home page reads both from this
// one endpoint so first paint is a single network round-trip.
func (h *WeeklyPickHandler) Current(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	year, week, err := h.weeklyRepo.LatestWeek(ctx)
	if err != nil && !repo.IsNotFound(err) {
		slog.ErrorContext(ctx, "weekly: latest week failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	var picks []repo.WeeklyPicked
	if year != 0 {
		picks, err = h.weeklyRepo.ListByWeek(ctx, year, week)
		if err != nil {
			slog.ErrorContext(ctx, "weekly: list by week failed", "error", err)
			response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
			return
		}
	}

	themes, err := h.collectionRepo.ListThemeCollections(ctx, 3)
	if err != nil {
		// Theme collections are a nice-to-have; an empty list still
		// renders the Home page (just the picks rail).
		slog.WarnContext(ctx, "weekly: list themes failed", "error", err)
		themes = nil
	}
	localizeCollections(requestLang(r), themes)

	response.OK(w, map[string]any{
		"year":   year,
		"week":   week,
		"picks":  picks,
		"themes": themes,
	})
}

// Archive returns every past weekly slate, newest first. Used by the
// /weekly-picks page.
func (h *WeeklyPickHandler) Archive(w http.ResponseWriter, r *http.Request) {
	limit := 50
	if raw := r.URL.Query().Get("limit"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v > 0 && v <= 200 {
			limit = v
		}
	}
	entries, err := h.weeklyRepo.Archive(r.Context(), limit)
	if err != nil {
		slog.ErrorContext(r.Context(), "weekly: archive failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, entries)
}

// ByWeek returns the 10 picks for a specific (year, week). 404 when the
// slate doesn't exist.
func (h *WeeklyPickHandler) ByWeek(w http.ResponseWriter, r *http.Request) {
	year, _ := strconv.ParseInt(chi.URLParam(r, "year"), 10, 16)
	week, _ := strconv.ParseInt(chi.URLParam(r, "week"), 10, 16)
	if year <= 0 || week <= 0 || week > 53 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	picks, err := h.weeklyRepo.ListByWeek(r.Context(), int16(year), int16(week))
	if err != nil {
		slog.ErrorContext(r.Context(), "weekly: by week failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if len(picks) == 0 {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}
	response.OK(w, map[string]any{"year": year, "week": week, "picks": picks})
}
