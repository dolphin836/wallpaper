package response

import (
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/errcode"
)

type Response struct {
	Code    int         `json:"code"`
	Message string      `json:"message"`
	Data    interface{} `json:"data"`
}

func JSON(w http.ResponseWriter, httpStatus int, ec *errcode.ErrCode, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(httpStatus)
	resp := Response{Code: ec.Code, Message: ec.Message, Data: data}
	if err := json.NewEncoder(w).Encode(resp); err != nil {
		slog.Error("failed to encode response", slog.String("error", err.Error()))
	}
}

func OK(w http.ResponseWriter, data interface{}) {
	JSON(w, http.StatusOK, errcode.Success, data)
}

func Error(w http.ResponseWriter, httpStatus int, ec *errcode.ErrCode) {
	JSON(w, httpStatus, ec, nil)
}
