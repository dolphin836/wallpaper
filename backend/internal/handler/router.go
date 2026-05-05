package handler

import (
	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/wallpaper/backend/internal/middleware"
)

type Deps struct {
	AuthHandler      *AuthHandler
	WallpaperHandler *WallpaperHandler
	CategoryHandler  *CategoryHandler
	TagHandler       *TagHandler
	UserHandler      *UserHandler
	DeviceHandler    *DeviceHandler
	JWTSecret        string
}

func NewRouter(deps Deps) *chi.Mux {
	r := chi.NewRouter()

	r.Use(chimiddleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recovery)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	limiter := middleware.NewRateLimiter(10, 30)
	r.Use(limiter.Handler)

	r.Route("/api/v1", func(r chi.Router) {
		r.Post("/auth/register", deps.AuthHandler.Register)
		r.Post("/auth/login", deps.AuthHandler.Login)

		r.Get("/categories", deps.CategoryHandler.List)
		r.Get("/tags", deps.TagHandler.Popular)
		r.Get("/devices", deps.DeviceHandler.ListDevices)

		r.Group(func(r chi.Router) {
			r.Use(middleware.OptionalAuth(deps.JWTSecret))
			r.Get("/wallpapers", deps.WallpaperHandler.List)
			r.Get("/wallpapers/{id}", deps.WallpaperHandler.Get)
			r.Get("/wallpapers/{id}/download", deps.WallpaperHandler.Download)
			r.Get("/wallpapers/{id}/variants", deps.DeviceHandler.ListVariants)
		})

		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth(deps.JWTSecret))
			r.Post("/wallpapers", deps.WallpaperHandler.Upload)
			r.Delete("/wallpapers/{id}", deps.WallpaperHandler.Delete)
			r.Post("/wallpapers/{id}/like", deps.WallpaperHandler.Like)
			r.Delete("/wallpapers/{id}/like", deps.WallpaperHandler.Unlike)
			r.Post("/wallpapers/{id}/favorite", deps.WallpaperHandler.Favorite)
			r.Delete("/wallpapers/{id}/favorite", deps.WallpaperHandler.Unfavorite)
		})

		r.Get("/users/{id}", deps.UserHandler.GetProfile)
		r.Group(func(r chi.Router) {
			r.Use(middleware.OptionalAuth(deps.JWTSecret))
			r.Get("/users/{id}/wallpapers", deps.UserHandler.GetWallpapers)
		})
		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth(deps.JWTSecret))
			r.Get("/users/me/favorites", deps.UserHandler.GetFavorites)
		})
	})

	return r
}
