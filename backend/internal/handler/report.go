package handler

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type ReportHandler struct {
	reportRepo    *repo.ReportRepo
	wallpaperRepo *repo.WallpaperRepo
}

func NewReportHandler(reportRepo *repo.ReportRepo, wallpaperRepo *repo.WallpaperRepo) *ReportHandler {
	return &ReportHandler{reportRepo: reportRepo, wallpaperRepo: wallpaperRepo}
}

var validReportReasons = map[string]bool{
	"nsfw":        true,
	"copyright":   true,
	"spam":        true,
	"low_quality": true,
	"other":       true,
}

type createReportRequest struct {
	Reason string `json:"reason"`
	Note   string `json:"note"`
}

func (h *ReportHandler) Create(w http.ResponseWriter, r *http.Request) {
	wallpaperID, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || wallpaperID <= 0 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}

	var req createReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	req.Reason = strings.ToLower(strings.TrimSpace(req.Reason))
	if !validReportReasons[req.Reason] {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if len(req.Note) > 2000 {
		req.Note = req.Note[:2000]
	}

	wp, err := h.wallpaperRepo.GetByID(r.Context(), wallpaperID)
	if err != nil {
		slog.ErrorContext(r.Context(), "report: lookup wallpaper failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	if wp == nil {
		response.Error(w, http.StatusNotFound, errcode.ErrNotFound)
		return
	}

	userID := middleware.GetUserID(r.Context())
	if userID == 0 {
		response.Error(w, http.StatusUnauthorized, errcode.ErrUnauthorized)
		return
	}

	report := &model.Report{
		WallpaperID:    wallpaperID,
		ReporterUserID: userID,
		Reason:         req.Reason,
		Note:           req.Note,
		Status:         model.ReportStatusOpen,
	}
	if err := h.reportRepo.Create(r.Context(), report); err != nil {
		// Unique constraint = already reported with the same reason; treat as
		// idempotent success so the user sees consistent UI without retrying.
		if errors.Is(err, gorm.ErrDuplicatedKey) || isDuplicateKeyErr(err) {
			response.OK(w, nil)
			return
		}
		slog.ErrorContext(r.Context(), "report: create failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	slog.InfoContext(r.Context(), "report created",
		"wallpaper_id", wallpaperID,
		"reporter_user_id", userID,
		"reason", req.Reason,
	)
	response.OK(w, nil)
}

func isDuplicateKeyErr(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "duplicate key") || strings.Contains(s, "SQLSTATE 23505")
}
