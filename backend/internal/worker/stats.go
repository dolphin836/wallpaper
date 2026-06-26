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
	eventRepo     *repo.EventRepo
	jobRepo       *repo.WorkerJobRepo
	mu            sync.Mutex
	counters      map[counterKey]int64
	// pending holds the highest fetched-but-uncommitted message per
	// partition. Offsets are committed only after the counters they
	// contributed to are flushed to the DB, so a worker crash replays
	// the window instead of silently dropping it.
	pending map[int]kafka.Message
}

type counterKey struct {
	WallpaperID int64
	Field       string
}

type WallpaperStatsEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	EventType   string `json:"event_type"`
	UserID      int64  `json:"user_id"`
	Client      string `json:"client"`
	IP          string `json:"ip"`
	UserAgent   string `json:"user_agent"`
	Referrer    string `json:"referrer"`
	SessionID   string `json:"session_id"`
	Timestamp   string `json:"timestamp"`
}

func NewStatsWorker(brokers []string, wallpaperRepo *repo.WallpaperRepo, eventRepo *repo.EventRepo, jobRepo *repo.WorkerJobRepo) *StatsWorker {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     brokers,
		Topic:       "wallpaper.stats",
		GroupID:     "stats-worker",
		MinBytes:    1,
		MaxBytes:    10e6,
		ErrorLogger: readerErrorLogger("stats-worker"),
	})
	return &StatsWorker{
		reader:        reader,
		wallpaperRepo: wallpaperRepo,
		eventRepo:     eventRepo,
		jobRepo:       jobRepo,
		counters:      make(map[counterKey]int64),
		pending:       make(map[int]kafka.Message),
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
			// Committing a bad message directly would also commit every
			// earlier offset in its partition, including unflushed counter
			// messages — park it in pending instead.
			w.markPending(msg)
			continue
		}

		field := eventTypeToField(event.EventType)
		if field == "" {
			slog.Warn("unknown event type", "event_type", event.EventType)
			w.markPending(msg)
			continue
		}

		if w.eventRepo != nil {
			if err := w.eventRepo.RecordWithMeta(ctx, event.WallpaperID, event.EventType, event.UserID, nil, repo.EventMeta{
				Client:    event.Client,
				IP:        event.IP,
				UserAgent: event.UserAgent,
				Referrer:  event.Referrer,
				SessionID: event.SessionID,
			}); err != nil {
				slog.Error("record stats event failed",
					"wallpaper_id", event.WallpaperID,
					"event_type", event.EventType,
					"error", err,
				)
			}
		}

		w.mu.Lock()
		w.counters[counterKey{WallpaperID: event.WallpaperID, Field: field}]++
		if cur, ok := w.pending[msg.Partition]; !ok || msg.Offset > cur.Offset {
			w.pending[msg.Partition] = msg
		}
		shouldFlush := len(w.counters) >= 1000
		w.mu.Unlock()

		if shouldFlush {
			w.flush(ctx)
		}
	}
}

// markPending records msg as consumed-but-uncommitted; flush commits it
// after the DB write succeeds.
func (w *StatsWorker) markPending(msg kafka.Message) {
	w.mu.Lock()
	if cur, ok := w.pending[msg.Partition]; !ok || msg.Offset > cur.Offset {
		w.pending[msg.Partition] = msg
	}
	w.mu.Unlock()
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
	if len(w.counters) == 0 && len(w.pending) == 0 {
		w.mu.Unlock()
		return
	}
	snapshot := w.counters
	w.counters = make(map[counterKey]int64)
	pending := w.pending
	w.pending = make(map[int]kafka.Message)
	w.mu.Unlock()

	if len(snapshot) == 0 {
		// Only parked bad messages this window — just advance the offsets.
		w.commitPending(ctx, pending)
		return
	}

	// Track the flush as one job so the admin dashboard can show batch size
	// and timing instead of being silent during quiet periods.
	jobID, jobErr := w.jobRepo.Start(ctx, "stats", "wallpaper.stats", 0)
	if jobErr != nil {
		slog.WarnContext(ctx, "worker_jobs start failed (non-fatal)", "worker", "stats", "error", jobErr)
	}

	failedCounts := make(map[counterKey]int64)
	for key, count := range snapshot {
		if err := w.wallpaperRepo.IncrementCounter(ctx, key.WallpaperID, key.Field, count); err != nil {
			slog.Error("increment counter failed",
				"wallpaper_id", key.WallpaperID,
				"field", key.Field,
				"error", err,
			)
			failedCounts[key] += count
		}
	}

	if len(failedCounts) == 0 {
		// Everything is durable in the DB — only now is it safe to move
		// the consumer group past this window.
		w.commitPending(ctx, pending)
	} else {
		// Requeue the failed counts and hold the offsets back so the next
		// flush retries; a crash in between replays instead of dropping.
		w.mu.Lock()
		for key, count := range failedCounts {
			w.counters[key] += count
		}
		for partition, m := range pending {
			if cur, ok := w.pending[partition]; !ok || m.Offset > cur.Offset {
				w.pending[partition] = m
			}
		}
		w.mu.Unlock()
	}

	status := "done"
	msg := fmt.Sprintf("flushed %d counters", len(snapshot))
	if len(failedCounts) > 0 {
		status = "failed"
		msg = fmt.Sprintf("flushed %d counters, %d failed (requeued)", len(snapshot), len(failedCounts))
	}
	if finErr := w.jobRepo.Finish(ctx, jobID, status, msg); finErr != nil {
		slog.WarnContext(ctx, "worker_jobs finish failed", "worker", "stats", "error", finErr)
	}

	slog.Info("stats flushed", "counter_count", len(snapshot), "failed_count", len(failedCounts))
}

func (w *StatsWorker) commitPending(ctx context.Context, pending map[int]kafka.Message) {
	if len(pending) == 0 {
		return
	}
	msgs := make([]kafka.Message, 0, len(pending))
	for _, m := range pending {
		msgs = append(msgs, m)
	}
	if err := w.reader.CommitMessages(ctx, msgs...); err != nil {
		// Worst case the window replays after a restart (at-least-once);
		// counters may then double-count once, which beats losing them.
		slog.Error("commit stats offsets failed", "error", err)
	}
}

func (w *StatsWorker) Close() error {
	return w.reader.Close()
}
