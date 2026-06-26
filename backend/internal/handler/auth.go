package handler

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

type AuthHandler struct {
	authSvc      *service.AuthService
	loginLogRepo *repo.LoginLogRepo
}

func NewAuthHandler(authSvc *service.AuthService, loginLogRepo *repo.LoginLogRepo) *AuthHandler {
	return &AuthHandler{authSvc: authSvc, loginLogRepo: loginLogRepo}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req service.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	referrer := requestReferrer(r, req.Referrer)
	req.Client = requestClient(r, req.Client)
	req.Referrer = referrer
	req.Source = registrationSource(req.Source, referrer)
	req.LandingPath = truncate(strings.TrimSpace(req.LandingPath), 512)
	req.IP = truncate(clientIP(r), 64)
	req.UserAgent = truncate(r.UserAgent(), 512)
	req.Country = requestCountry(r)
	resp, ec := h.authSvc.Register(r.Context(), req)
	if ec != nil {
		response.Error(w, http.StatusBadRequest, ec)
		return
	}
	response.OK(w, resp)
}

func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req service.LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
	resp, ec := h.authSvc.Login(r.Context(), req)
	if ec != nil {
		status := http.StatusBadRequest
		if ec.Code == errcode.ErrUnauthorized.Code || ec.Code == errcode.ErrWrongPassword.Code {
			status = http.StatusUnauthorized
		}
		response.Error(w, status, ec)
		return
	}
	if h.loginLogRepo != nil && resp.User != nil {
		log := &model.LoginLog{
			UserID:    resp.User.ID,
			Client:    requestClient(r, req.Client),
			IP:        truncate(clientIP(r), 64),
			UserAgent: truncate(r.UserAgent(), 512),
			Country:   requestCountry(r),
		}
		if err := h.loginLogRepo.Create(r.Context(), log); err != nil {
			slog.WarnContext(r.Context(), "auth: record login log failed", "error", err, "user_id", resp.User.ID)
		}
	}
	response.OK(w, resp)
}
