package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/segmentio/kafka-go"
	"golang.org/x/sync/errgroup"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/indexnow"
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
	eventRepo := repo.NewEventRepo(db)
	jobRepo := repo.NewWorkerJobRepo(db)

	indexClient, err := indexnow.New(cfg.IndexNow.Key, cfg.IndexNow.SiteURL)
	if err != nil {
		slog.Warn("indexnow disabled (config invalid)", "error", err)
		indexClient = nil
	}

	imgWorker := worker.NewImageWorker(
		cfg.Kafka.Brokers,
		wallpaperRepo,
		deviceRepo,
		jobRepo,
		store,
		indexClient,
		cfg.IndexNow.SiteURL,
	)
	statsWorker := worker.NewStatsWorker(cfg.Kafka.Brokers, wallpaperRepo, eventRepo, jobRepo)

	// Transcode worker is optional — if ffmpeg isn't installed or the
	// work dir can't be created, log and continue so the image +
	// stats workers stay up. Video uploads won't progress past
	// Processing until the worker is healthy.
	transcodeWorker, err := worker.NewTranscodeWorker(
		cfg.Kafka.Brokers, wallpaperRepo, jobRepo, store, cfg.Transcode.WorkDir,
	)
	if err != nil {
		slog.Warn("transcode worker disabled", "error", err)
		transcodeWorker = nil
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		quit := make(chan os.Signal, 1)
		signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
		<-quit
		slog.Info("shutting down workers")
		cancel()
	}()

	// Gate worker startup on the group coordinator actually answering.
	// kafka-go readers do not survive joining a broker whose coordinator
	// isn't up yet: the join fails with GroupCoordinatorNotAvailable and
	// the reader stalls forever without retrying (2026-06-12 incident —
	// five videos stuck in processing for 37h after a deploy recreated
	// the broker). Exit non-zero on timeout so the container restart
	// policy retries the whole boot against a warmer broker.
	if err := waitKafkaReady(ctx, cfg.Kafka.Brokers); err != nil {
		slog.Error("kafka group coordinator not ready, exiting for restart", "error", err)
		os.Exit(1)
	}

	g, gCtx := errgroup.WithContext(ctx)

	g.Go(func() error {
		return imgWorker.Run(gCtx)
	})

	g.Go(func() error {
		return statsWorker.Run(gCtx)
	})

	if transcodeWorker != nil {
		g.Go(func() error {
			return transcodeWorker.Run(gCtx)
		})
	}

	if err := g.Wait(); err != nil && err != context.Canceled {
		slog.Error("worker error", "error", err)
	}

	if err := imgWorker.Close(); err != nil {
		slog.Error("close image worker failed", "error", err)
	}
	if err := statsWorker.Close(); err != nil {
		slog.Error("close stats worker failed", "error", err)
	}
	if transcodeWorker != nil {
		if err := transcodeWorker.Close(); err != nil {
			slog.Error("close transcode worker failed", "error", err)
		}
	}

	slog.Info("workers stopped")
}

// waitKafkaReady polls FindCoordinator until the broker's consumer-group
// coordinator responds, or the deadline lapses. Any group key works for
// the probe; the coordinator is either up for all groups or none.
func waitKafkaReady(ctx context.Context, brokers []string) error {
	client := &kafka.Client{Addr: kafka.TCP(brokers...)}
	deadline := time.Now().Add(2 * time.Minute)

	for {
		reqCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		resp, err := client.FindCoordinator(reqCtx, &kafka.FindCoordinatorRequest{
			Addr:    client.Addr,
			Key:     "stats-worker",
			KeyType: kafka.CoordinatorKeyTypeConsumer,
		})
		cancel()

		probeErr := err
		if probeErr == nil && resp.Error != nil {
			probeErr = resp.Error
		}
		if probeErr == nil {
			slog.Info("kafka group coordinator ready")
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("kafka group coordinator not ready: %w", probeErr)
		}

		slog.Info("waiting for kafka group coordinator", "error", probeErr.Error())
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}
