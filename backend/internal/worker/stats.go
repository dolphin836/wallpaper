package worker

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/repo"
)

type StatsWorker struct {
	reader        *kafka.Reader
	wallpaperRepo *repo.WallpaperRepo
	jobRepo       *repo.WorkerJobRepo
	mu            sync.Mutex
	counters      map[counterKey]int64
}

type counterKey struct {
	WallpaperID int64
	Field       string
}

type WallpaperStatsEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	EventType   string `json:"event_type"`
	UserID      int64  `json:"user_id"`
	Timestamp   string `json:"timestamp"`
}

func NewStatsWorker(brokers []string, wallpaperRepo *repo.WallpaperRepo, jobRepo *repo.WorkerJobRepo) *StatsWorker {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  brokers,
		Topic:    "wallpaper.stats",
		GroupID:  "stats-worker",
		MinBytes: 1,
		MaxBytes: 10e6,
	})
	return &StatsWorker{
		reader:        reader,
		wallpaperRepo: wallpaperRepo,
		jobRepo:       jobRepo,
		counters:      make(map[counterKey]int64),
	}
}

func (w *StatsWorker) Run(ctx context.Context) error {
	slog.Info("stats worker started")

	go func() {
		ticker := time.NewTicker(10 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				w.flush(ctx)
			}
		}
	}()

	for {
		msg, err := w.reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				// final flush with background context since ctx is already canceled
				w.flush(context.Background())
				return ctx.Err()
			}
			slog.Error("fetch message failed", "error", err)
			continue
		}

		var event WallpaperStatsEvent
		if err := json.Unmarshal(msg.Value, &event); err != nil {
			slog.Error("unmarshal stats event failed", "error", err)
			if commitErr := w.reader.CommitMessages(ctx, msg); commitErr != nil {
				slog.Error("commit message failed", "error", commitErr)
			}
			continue
		}

		field := eventTypeToField(event.EventType)
		if field == "" {
			slog.Warn("unknown event type", "event_type", event.EventType)
			if commitErr := w.reader.CommitMessages(ctx, msg); commitErr != nil {
				slog.Error("commit message failed", "error", commitErr)
			}
			continue
		}

		w.mu.Lock()
		w.counters[counterKey{WallpaperID: event.WallpaperID, Field: field}]++
		shouldFlush := len(w.counters) >= 1000
		w.mu.Unlock()

		if shouldFlush {
			w.flush(ctx)
		}

		if err := w.reader.CommitMessages(ctx, msg); err != nil {
			slog.Error("commit message failed", "error", err)
		}
	}
}

func eventTypeToField(eventType string) string {
	switch eventType {
	case "view":
		return "view_count"
	case "download":
		return "download_count"
	default:
		return ""
	}
}

func (w *StatsWorker) flush(ctx context.Context) {
	w.mu.Lock()
	if len(w.counters) == 0 {
		w.mu.Unlock()
		return
	}
	snapshot := w.counters
	w.counters = make(map[counterKey]int64)
	w.mu.Unlock()

	// Track the flush as one job so the admin dashboard can show batch size
	// and timing instead of being silent during quiet periods.
	jobID, jobErr := w.jobRepo.Start(ctx, "stats", "wallpaper.stats", 0)
	if jobErr != nil {
		slog.WarnContext(ctx, "worker_jobs start failed (non-fatal)", "worker", "stats", "error", jobErr)
	}

	var failed int
	for key, count := range snapshot {
		if err := w.wallpaperRepo.IncrementCounter(ctx, key.WallpaperID, key.Field, count); err != nil {
			slog.Error("increment counter failed",
				"wallpaper_id", key.WallpaperID,
				"field", key.Field,
				"error", err,
			)
			failed++
		}
	}

	status := "done"
	msg := fmt.Sprintf("flushed %d counters", len(snapshot))
	if failed > 0 {
		status = "failed"
		msg = fmt.Sprintf("flushed %d counters, %d failed", len(snapshot), failed)
	}
	if finErr := w.jobRepo.Finish(ctx, jobID, status, msg); finErr != nil {
		slog.WarnContext(ctx, "worker_jobs finish failed", "worker", "stats", "error", finErr)
	}

	slog.Info("stats flushed", "counter_count", len(snapshot))
}

func (w *StatsWorker) Close() error {
	return w.reader.Close()
}
