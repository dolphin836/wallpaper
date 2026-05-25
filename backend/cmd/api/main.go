package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/segmentio/kafka-go"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/cache"
	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/handler"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})))

	cfg, err := config.Load()
	if err != nil {
		slog.Error("load config failed", "error", err)
		os.Exit(1)
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		slog.Error("connect db failed", "error", err)
		os.Exit(1)
	}

	store, err := storage.New(cfg.MinIO)
	if err != nil {
		slog.Error("init storage failed", "error", err)
		os.Exit(1)
	}
	if err := store.EnsureBucket(context.Background()); err != nil {
		slog.Error("ensure bucket failed", "error", err)
		os.Exit(1)
	}

	cacheClient := cache.New(cfg.Redis.Addr, cfg.Redis.Password, cfg.Redis.DB)
	if err := cacheClient.Ping(context.Background()); err != nil {
		slog.Error("connect redis failed", "error", err)
		os.Exit(1)
	}
	slog.Info("redis connected", "addr", cfg.Redis.Addr)
	defer func() {
		if err := cacheClient.Close(); err != nil {
			slog.Error("close redis failed", "error", err)
		}
	}()

	_ = cacheClient

	kafkaWriter := &kafka.Writer{
		Addr:                   kafka.TCP(cfg.Kafka.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: true,
		BatchSize:              1,
		BatchTimeout:           10 * time.Millisecond,
		WriteTimeout:           10 * time.Second,
		RequiredAcks:           kafka.RequireOne,
	}
	defer func() {
		if err := kafkaWriter.Close(); err != nil {
			slog.Error("close kafka writer failed", "error", err)
		}
	}()

	userRepo := repo.NewUserRepo(db)
	wallpaperRepo := repo.NewWallpaperRepo(db)
	categoryRepo := repo.NewCategoryRepo(db)
	tagRepo := repo.NewTagRepo(db)
	interactionRepo := repo.NewInteractionRepo(db)
	deviceRepo := repo.NewDeviceRepo(db)
	collectionRepo := repo.NewCollectionRepo(db)
	eventRepo := repo.NewEventRepo(db)
	coinRepo := repo.NewCoinRepo(db)
	reportRepo := repo.NewReportRepo(db)
	analyticsRepo := repo.NewAnalyticsRepo(db)
	adminRepo := repo.NewAdminRepo(db)
	workerJobRepo := repo.NewWorkerJobRepo(db)

	authSvc := service.NewAuthService(userRepo, coinRepo, cfg.JWT.Secret, cfg.JWT.ExpireHour)
	wallpaperSvc := service.NewWallpaperService(wallpaperRepo, tagRepo, interactionRepo, userRepo, eventRepo, coinRepo, collectionRepo, deviceRepo, store, kafkaWriter)
	collectionSvc := service.NewCollectionService(collectionRepo, interactionRepo)

	authHandler := handler.NewAuthHandler(authSvc)
	wallpaperHandler := handler.NewWallpaperHandler(wallpaperSvc)
	categoryHandler := handler.NewCategoryHandler(categoryRepo)
	tagHandler := handler.NewTagHandler(tagRepo)
	userHandler := handler.NewUserHandler(userRepo, wallpaperRepo, interactionRepo, coinRepo, store)
	deviceHandler := handler.NewDeviceHandler(deviceRepo, eventRepo, wallpaperRepo, coinRepo, interactionRepo)
	collectionHandler := handler.NewCollectionHandler(collectionSvc, interactionRepo, userRepo)
	releaseHandler := handler.NewReleaseHandler()
	seoHandler := handler.NewSEOHandler(wallpaperRepo, categoryRepo, deviceRepo, collectionRepo, userRepo, cfg.IndexNow.Key, cfg.IndexNow.SiteURL)
	reportHandler := handler.NewReportHandler(reportRepo, wallpaperRepo)
	analyticsHandler := handler.NewAnalyticsHandler(analyticsRepo)
	recommendHandler := handler.NewRecommendHandler(wallpaperRepo)
	weeklyPickRepo := repo.NewWeeklyPickRepo(db)
	weeklyPickHandler := handler.NewWeeklyPickHandler(weeklyPickRepo, collectionRepo)
	statsHandler := handler.NewStatsHandler(wallpaperRepo, collectionRepo)
	llmUsageRepo := repo.NewLLMUsageRepo(db)
	adminHandler := handler.NewAdminHandler(adminRepo, userRepo, wallpaperRepo, collectionRepo, reportRepo, workerJobRepo, categoryRepo, analyticsRepo, llmUsageRepo, store, wallpaperSvc)

	// Resumable video uploads. Failure to set up the tus handler is
	// non-fatal — the rest of the API stays up and the upload endpoint
	// is simply unavailable.
	tusHandler, err := handler.NewTusHandler(wallpaperSvc, wallpaperRepo, store, cfg.JWT.Secret, cfg.Tus.TmpDir)
	if err != nil {
		slog.Warn("tus upload handler disabled", "error", err)
		tusHandler = nil
	}

	router := handler.NewRouter(handler.Deps{
		AuthHandler:       authHandler,
		WallpaperHandler:  wallpaperHandler,
		CategoryHandler:   categoryHandler,
		TagHandler:        tagHandler,
		UserHandler:       userHandler,
		DeviceHandler:     deviceHandler,
		CollectionHandler: collectionHandler,
		ReleaseHandler:    releaseHandler,
		SEOHandler:        seoHandler,
		ReportHandler:     reportHandler,
		AnalyticsHandler:  analyticsHandler,
		RecommendHandler:  recommendHandler,
		WeeklyPickHandler: weeklyPickHandler,
		StatsHandler:      statsHandler,
		AdminHandler:      adminHandler,
		TusHandler:        tusHandler,
		UserRepo:          userRepo,
		IndexNowKey:       cfg.IndexNow.Key,
		JWTSecret:         cfg.JWT.Secret,
	})

	srv := &http.Server{
		Addr:         fmt.Sprintf(":%d", cfg.Server.Port),
		Handler:      router,
		ReadTimeout:  5 * time.Minute,
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("api server started", "port", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case <-quit:
		slog.Info("shutting down server")
	case err := <-errCh:
		slog.Error("server error", "error", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		slog.Error("server shutdown error", "error", err)
	}
	slog.Info("server stopped")
}
