package middleware

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	jwtpkg "github.com/wallpaper/backend/internal/pkg/jwt"
)

type contextKey string

const UserIDKey contextKey = "user_id"

func Auth(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token, ok := extractBearerToken(r)
			if !ok {
				writeErrCode(w, errcode.ErrUnauthorized)
				return
			}

			claims, err := jwtpkg.ParseToken(token, jwtSecret)
			if err != nil {
				writeErrCode(w, errcode.ErrUnauthorized)
				return
			}

			ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func OptionalAuth(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			token, ok := extractBearerToken(r)
			if !ok {
				next.ServeHTTP(w, r)
				return
			}

			claims, err := jwtpkg.ParseToken(token, jwtSecret)
			if err != nil {
				next.ServeHTTP(w, r)
				return
			}

			ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

func GetUserID(ctx context.Context) int64 {
	v := ctx.Value(UserIDKey)
	if v == nil {
		return 0
	}
	id, ok := v.(int64)
	if !ok {
		return 0
	}
	return id
}

func extractBearerToken(r *http.Request) (string, bool) {
	auth := r.Header.Get("Authorization")
	if auth == "" {
		return "", false
	}
	parts := strings.SplitN(auth, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return "", false
	}
	return parts[1], true
}

func writeErrCode(w http.ResponseWriter, ec *errcode.ErrCode) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(ec.Code / 100)
	if err := json.NewEncoder(w).Encode(ec); err != nil {
		slog.Error("failed to write error response", "error", err)
	}
}
