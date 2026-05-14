package handler

import (
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"strings"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

type AnalyticsHandler struct {
	repo *repo.AnalyticsRepo
}

func NewAnalyticsHandler(r *repo.AnalyticsRepo) *AnalyticsHandler {
	return &AnalyticsHandler{repo: r}
}

type trackRequest struct {
	SessionID string          `json:"session_id"`
	Type      string          `json:"type"`
	Path      string          `json:"path"`
	Referrer  string          `json:"referrer"`
	Props     json.RawMessage `json:"props"`
}

func (h *AnalyticsHandler) Track(w http.ResponseWriter, r *http.Request) {
	var req trackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	req.Type = strings.TrimSpace(req.Type)
	req.SessionID = strings.TrimSpace(req.SessionID)
	if req.SessionID == "" || req.Type == "" || len(req.SessionID) > 64 || len(req.Type) > 64 {
		response.Error(w, http.StatusBadRequest, errcode.ErrInvalidParam)
		return
	}
	if len(req.Props) == 0 || string(req.Props) == "null" {
		req.Props = json.RawMessage("{}")
	}

	event := &model.AnalyticsEvent{
		SessionID: req.SessionID,
		UserID:    middleware.GetUserID(r.Context()),
		EventType: req.Type,
		Path:      truncate(req.Path, 512),
		Referrer:  truncate(req.Referrer, 512),
		UserAgent: truncate(r.UserAgent(), 512),
		IP:        clientIP(r),
		Props:     req.Props,
	}

	if err := h.repo.Create(r.Context(), event); err != nil {
		// Telemetry must never break user-facing flows. Log + swallow.
		slog.WarnContext(r.Context(), "analytics: create failed", "error", err, "type", req.Type)
	}
	response.OK(w, nil)
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}

func clientIP(r *http.Request) string {
	if v := r.Header.Get("X-Forwarded-For"); v != "" {
		if i := strings.Index(v, ","); i > 0 {
			v = v[:i]
		}
		return strings.TrimSpace(v)
	}
	if v := r.Header.Get("X-Real-IP"); v != "" {
		return v
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
