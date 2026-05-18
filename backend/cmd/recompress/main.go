// recompress re-runs the image worker over every published wallpaper to
// pick up new variant-encoding defaults (quality tweaks, format switches).
// It does *not* re-encode in place — it just re-publishes wallpaper.uploaded
// Kafka events so the existing worker pipeline does the work, which means
// the cleanup logic in worker.processImage handles the old artifacts.
//
// Usage:
//
//	./recompress             # dry-run: print what would be requeued
//	./recompress --commit    # actually publish to Kafka
//	./recompress --commit --limit 10   # only first N (for canary)
//	./recompress --commit --status 3   # process status=removed too
//
// Recommended flow: --commit --limit 5 first; spot-check a few wallpapers
// in the admin / on the site; then run the full batch.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/storage"
)

type wallpaperRow struct {
	ID          int64
	UserID      int64
	OriginalURL string
	Status      int16
}

type uploadedEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	UserID      int64  `json:"user_id"`
	ObjectKey   string `json:"object_key"`
	Timestamp   string `json:"timestamp"`
}

func main() {
	var (
		commit bool
		limit  int
		status int
		pause  time.Duration
	)
	flag.BoolVar(&commit, "commit", false, "actually publish Kafka events (default: dry-run)")
	flag.IntVar(&limit, "limit", 0, "process at most N wallpapers (0 = unlimited)")
	flag.IntVar(&status, "status", int(model.WallpaperStatusPublished), "wallpaper status to scan (1=published, 3=removed, etc.)")
	flag.DurationVar(&pause, "pause", 100*time.Millisecond, "delay between events (avoids overwhelming the worker queue)")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}

	store, err := storage.New(cfg.MinIO)
	if err != nil {
		log.Fatal("init storage: ", err)
	}

	var rows []wallpaperRow
	q := db.Table("wallpapers").
		Select("id, user_id, original_url, status").
		Where("status = ?", status).
		Order("id ASC")
	if limit > 0 {
		q = q.Limit(limit)
	}
	if err := q.Find(&rows).Error; err != nil {
		log.Fatal("query wallpapers: ", err)
	}

	fmt.Printf("found %d wallpapers (status=%d)\n", len(rows), status)
	if !commit {
		fmt.Println("dry-run — pass --commit to actually publish Kafka events")
		// Still show a sample of what would happen.
		preview := 5
		if len(rows) < preview {
			preview = len(rows)
		}
		for i := 0; i < preview; i++ {
			key := store.ObjectKeyFromURL(rows[i].OriginalURL)
			fmt.Printf("  [%d] id=%d key=%s\n", i+1, rows[i].ID, key)
		}
		return
	}

	writer := &kafka.Writer{
		Addr:                   kafka.TCP(cfg.Kafka.Brokers...),
		Topic:                  "wallpaper.uploaded",
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: true,
		BatchSize:              1,
	}
	defer writer.Close()

	ctx := context.Background()
	var ok, skipped, failed int
	for i, r := range rows {
		key := store.ObjectKeyFromURL(r.OriginalURL)
		if key == "" {
			fmt.Printf("[%d/%d] id=%d SKIP (cannot derive object key from %q)\n", i+1, len(rows), r.ID, r.OriginalURL)
			skipped++
			continue
		}
		evt := uploadedEvent{
			WallpaperID: r.ID,
			UserID:      r.UserID,
			ObjectKey:   key,
			Timestamp:   time.Now().UTC().Format(time.RFC3339),
		}
		data, err := json.Marshal(evt)
		if err != nil {
			fmt.Printf("[%d/%d] id=%d marshal err: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}

		// Flip status back to processing so the public list/feed hides this
		// row while the worker regenerates artifacts (cleanup nukes the old
		// thumb/preview/variants first, so without this guard a brief window
		// would render broken images).
		if err := db.WithContext(ctx).Table("wallpapers").
			Where("id = ?", r.ID).
			Update("status", model.WallpaperStatusProcessing).Error; err != nil {
			fmt.Printf("[%d/%d] id=%d status update err: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}

		if err := writer.WriteMessages(ctx, kafka.Message{
			Key:   []byte(strconv.FormatInt(r.ID, 10)),
			Value: data,
		}); err != nil {
			fmt.Printf("[%d/%d] id=%d publish err: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}
		ok++
		fmt.Printf("[%d/%d] id=%d requeued\n", i+1, len(rows), r.ID)
		if pause > 0 {
			time.Sleep(pause)
		}
	}

	fmt.Println(strings.Repeat("-", 60))
	fmt.Printf("done: %d requeued, %d skipped, %d failed\n", ok, skipped, failed)
}
