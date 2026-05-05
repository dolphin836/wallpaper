package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"golang.org/x/sync/errgroup"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/worker"
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

	wallpaperRepo := repo.NewWallpaperRepo(db)
	deviceRepo := repo.NewDeviceRepo(db)

	imgWorker := worker.NewImageWorker(cfg.Kafka.Brokers, wallpaperRepo, deviceRepo, store)
	statsWorker := worker.NewStatsWorker(cfg.Kafka.Brokers, wallpaperRepo)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		<-quit
		slog.Info("shutting down workers")
		cancel()
	}()

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		return imgWorker.Run(gCtx)
	})

	g.Go(func() error {
		return statsWorker.Run(gCtx)
	})

	if err := g.Wait(); err != nil && err != context.Canceled {
		slog.Error("worker error", "error", err)
	}

	if err := imgWorker.Close(); err != nil {
		slog.Error("close image worker failed", "error", err)
	}
	if err := statsWorker.Close(); err != nil {
		slog.Error("close stats worker failed", "error", err)
	}

	slog.Info("workers stopped")
}
