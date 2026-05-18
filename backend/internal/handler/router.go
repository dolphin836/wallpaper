package handler

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

	"github.com/wallpaper/backend/internal/middleware"
	"github.com/wallpaper/backend/internal/repo"
)

type Deps struct {
	AuthHandler       *AuthHandler
	WallpaperHandler  *WallpaperHandler
	CategoryHandler   *CategoryHandler
	TagHandler        *TagHandler
	UserHandler       *UserHandler
	DeviceHandler     *DeviceHandler
	CollectionHandler *CollectionHandler
	ReleaseHandler    *ReleaseHandler
	SEOHandler        *SEOHandler
	ReportHandler     *ReportHandler
	AnalyticsHandler  *AnalyticsHandler
	RecommendHandler  *RecommendHandler
	StatsHandler      *StatsHandler
	AdminHandler      *AdminHandler
	UserRepo          *repo.UserRepo
	JWTSecret         string
}

func NewRouter(deps Deps) *chi.Mux {
	r := chi.NewRouter()

	r.Use(chimiddleware.RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recovery)
	r.Use(cors.Handler(cors.Options{
		AllowOriginFunc: func(_ *http.Request, origin string) bool {
			switch origin {
			case "https://wallpaperexchange.com",
				"https://www.wallpaperexchange.com",
				"https://wallpaper.haibing.site":
				return true
			}
			return strings.HasPrefix(origin, "http://localhost:")
		},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           86400,
	}))

	limiter := middleware.NewRateLimiter(10, 30)
	r.Use(limiter.Handler)

	r.Get("/robots.txt", deps.SEOHandler.RobotsTxt)
	r.Get("/sitemap.xml", deps.SEOHandler.Sitemap)
	r.Get("/__og/wallpaper/{slug}", deps.SEOHandler.OGWallpaper)

	r.Route("/api/v1", func(r chi.Router) {
		r.Post("/auth/register", deps.AuthHandler.Register)
		r.Post("/auth/login", deps.AuthHandler.Login)

		r.Get("/categories", deps.CategoryHandler.List)
		r.Get("/tags", deps.TagHandler.Popular)
		r.Get("/devices", deps.DeviceHandler.ListDevices)
		r.Get("/devices/{slug}", deps.DeviceHandler.GetDeviceBySlug)
		r.Get("/devices/{slug}/wallpapers", deps.DeviceHandler.ListWallpapersForDevice)
		r.Get("/mac/release", deps.ReleaseHandler.GetMacRelease)
		r.Get("/stats", deps.StatsHandler.Get)

		r.Get("/users", deps.UserHandler.ListUsers)

		r.Group(func(r chi.Router) {
			r.Use(middleware.OptionalAuth(deps.JWTSecret))
			r.Post("/events", deps.AnalyticsHandler.Track)
			r.Get("/wallpapers", deps.WallpaperHandler.List)
			r.Get("/wallpapers/{id}", deps.WallpaperHandler.Get)
			r.Get("/wallpapers/{id}/variants", deps.DeviceHandler.ListVariants)
			r.Get("/wallpapers/{id}/engagements", deps.WallpaperHandler.GetEngagements)
			r.Get("/wallpapers/{id}/similar", deps.RecommendHandler.Similar)

			r.Get("/collections", deps.CollectionHandler.List)
			r.Get("/collections/{id}", deps.CollectionHandler.Get)
			r.Get("/collections/{id}/wallpapers", deps.CollectionHandler.ListWallpapers)
			r.Get("/users/{id}/collections", deps.CollectionHandler.ListUserCollections)
			r.Get("/users/{id}/wallpapers", deps.UserHandler.GetWallpapers)
			r.Get("/users/{id}/likes", deps.UserHandler.GetUserLikes)
			r.Get("/users/{id}/favorites", deps.UserHandler.GetUserFavorites)
			r.Get("/users/{id}/downloads", deps.UserHandler.GetUserDownloads)
		})

		r.Group(func(r chi.Router) {
			r.Use(middleware.Auth(deps.JWTSecret))

			r.Post("/wallpapers", deps.WallpaperHandler.Upload)
			r.Delete("/wallpapers/{id}", deps.WallpaperHandler.Delete)
			r.Get("/wallpapers/{id}/download", deps.WallpaperHandler.Download)
			r.Post("/wallpapers/{id}/variants/{vid}/download", deps.DeviceHandler.DownloadVariant)
			r.Post("/wallpapers/{id}/like", deps.WallpaperHandler.Like)
			r.Delete("/wallpapers/{id}/like", deps.WallpaperHandler.Unlike)
			r.Post("/wallpapers/{id}/favorite", deps.WallpaperHandler.Favorite)
			r.Delete("/wallpapers/{id}/favorite", deps.WallpaperHandler.Unfavorite)
			r.Post("/wallpapers/{id}/report", deps.ReportHandler.Create)

			r.Get("/users/me", deps.UserHandler.GetMe)
			r.Put("/users/me/profile", deps.UserHandler.UpdateProfile)
			r.Post("/users/me/avatar", deps.UserHandler.UploadAvatar)
			r.Put("/users/me/password", deps.UserHandler.ChangePassword)
			r.Put("/users/me/privacy", deps.UserHandler.UpdatePrivacy)
			r.Get("/wallpapers/for-you", deps.RecommendHandler.ForYou)

			r.Get("/users/me/coins", deps.UserHandler.GetCoins)
			r.Get("/users/me/coin-transactions", deps.UserHandler.GetCoinTransactions)
			r.Get("/users/me/favorites", deps.UserHandler.GetFavorites)
			r.Get("/users/me/likes", deps.UserHandler.GetLikes)
			r.Get("/users/me/downloads", deps.UserHandler.GetDownloads)
			r.Get("/users/me/collections", deps.CollectionHandler.ListMyCollections)

			r.Post("/collections", deps.CollectionHandler.Create)
			r.Put("/collections/{id}", deps.CollectionHandler.Update)
			r.Delete("/collections/{id}", deps.CollectionHandler.Delete)
			r.Post("/collections/{id}/wallpapers", deps.CollectionHandler.AddWallpaper)
			r.Delete("/collections/{id}/wallpapers/{wid}", deps.CollectionHandler.RemoveWallpaper)
			r.Post("/collections/{id}/like", deps.CollectionHandler.Like)
			r.Delete("/collections/{id}/like", deps.CollectionHandler.Unlike)
		})

		r.Get("/users/{id}", deps.UserHandler.GetProfile)

		// ── Admin console ──
		r.Route("/admin", func(r chi.Router) {
			r.Use(middleware.AdminAuth(deps.JWTSecret, deps.UserRepo))

			r.Get("/overview", deps.AdminHandler.GetOverview)
			r.Get("/series", deps.AdminHandler.GetSeries)
			r.Get("/tops", deps.AdminHandler.GetTops)

			r.Get("/wallpapers", deps.AdminHandler.ListWallpapers)
			r.Put("/wallpapers/{id}", deps.AdminHandler.UpdateWallpaper)
			r.Post("/wallpapers/{id}/reprocess", deps.AdminHandler.ReprocessWallpaper)
			r.Delete("/wallpapers/{id}", deps.AdminHandler.DeleteWallpaper)
			r.Delete("/wallpapers/{id}/hard", deps.AdminHandler.HardDeleteWallpaper)

			r.Get("/collections", deps.AdminHandler.ListCollections)
			r.Put("/collections/{id}", deps.AdminHandler.UpdateCollection)
			r.Delete("/collections/{id}", deps.AdminHandler.DeleteCollection)

			r.Get("/users", deps.AdminHandler.ListUsers)
			r.Put("/users/{id}/admin", deps.AdminHandler.SetUserAdmin)
			r.Put("/users/{id}/status", deps.AdminHandler.SetUserStatus)

			r.Get("/reports", deps.AdminHandler.ListReports)
			r.Put("/reports/{id}/resolve", deps.AdminHandler.ResolveReport)

			r.Get("/workers/summary", deps.AdminHandler.WorkerSummary)
			r.Get("/workers/jobs", deps.AdminHandler.WorkerJobs)

			r.Get("/storage", deps.AdminHandler.GetStorage)
		})
	})

	return r
}
