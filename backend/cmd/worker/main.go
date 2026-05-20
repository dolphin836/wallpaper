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
	"github.com/wallpaper/backend/internal/pkg/indexnow"
	"github.com/wallpaper/backend/internal/pkg/llm"
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
	jobRepo := repo.NewWorkerJobRepo(db)
	tagRepo := repo.NewTagRepo(db)
	categoryRepo := repo.NewCategoryRepo(db)
	llmUsageRepo := repo.NewLLMUsageRepo(db)

	indexClient, err := indexnow.New(cfg.IndexNow.Key, cfg.IndexNow.SiteURL)
	if err != nil {
		slog.Warn("indexnow disabled (config invalid)", "error", err)
		indexClient = nil
	}

	// Cache category slug → id at startup so each autotag call doesn't
	// hit the DB just to translate the LLM's chosen slug. New categories
	// require a worker restart, which is fine — they're an admin action.
	categorySlugMap := map[string]int64{}
	if cats, cerr := categoryRepo.List(context.Background()); cerr == nil {
		for _, c := range cats {
			categorySlugMap[c.Slug] = c.ID
		}
		slog.Info("loaded categories for autotag", "count", len(categorySlugMap))
	} else {
		slog.Warn("autotag disabled (couldn't load categories)", "error", cerr)
	}
	llmClient := llm.New(cfg.Anthropic.APIKey, llmUsageRepo)

	imgWorker := worker.NewImageWorker(
		cfg.Kafka.Brokers,
		wallpaperRepo,
		deviceRepo,
		jobRepo,
		tagRepo,
		categorySlugMap,
		store,
		indexClient,
		llmClient,
		cfg.IndexNow.SiteURL,
	)
	statsWorker := worker.NewStatsWorker(cfg.Kafka.Brokers, wallpaperRepo, jobRepo)

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
