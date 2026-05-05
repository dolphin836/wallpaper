package handler

import (
	"encoding/json"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/service"
)

type AuthHandler struct {
	authSvc *service.AuthService
}

func NewAuthHandler(authSvc *service.AuthService) *AuthHandler {
	return &AuthHandler{authSvc: authSvc}
}

func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req service.RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		response.Error(w, http.StatusBadRequest, errcode.ErrBadRequest)
		return
	}
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
	response.OK(w, resp)
}
