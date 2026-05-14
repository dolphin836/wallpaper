package middleware

import (
	"context"
	"log/slog"
	"net/http"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	jwtpkg "github.com/wallpaper/backend/internal/pkg/jwt"
	"github.com/wallpaper/backend/internal/repo"
)

// AdminAuth requires a valid JWT *and* users.is_admin = true. Issues 401 for
// missing/invalid tokens and 403 for valid but non-admin users so the admin
// frontend can distinguish "log in" vs "you can't enter here" without parsing
// the JWT itself.
func AdminAuth(jwtSecret string, users *repo.UserRepo) func(http.Handler) http.Handler {
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

			isAdmin, err := users.IsAdmin(r.Context(), claims.UserID)
			if err != nil {
				slog.ErrorContext(r.Context(), "admin auth: is_admin lookup failed",
					"user_id", claims.UserID, "error", err)
				writeErrCode(w, errcode.ErrInternal)
				return
			}
			if !isAdmin {
				writeErrCode(w, errcode.ErrForbidden)
				return
			}

			ctx := context.WithValue(r.Context(), UserIDKey, claims.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
