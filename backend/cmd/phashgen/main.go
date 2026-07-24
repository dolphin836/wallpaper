// phashgen backfills the wallpapers.phash column for published wallpapers
// that pre-date the perceptual-hash dedup feature.
//
// Usage:
//
//	/bin/phashgen                    # only rows with phash=0
//	/bin/phashgen --force            # recompute every published row
//	/bin/phashgen --report-dupes     # after backfill, log near-duplicate pairs
//
// Runs inside the api container so it shares config/network with the API.
// Originals are read through the authenticated MinIO client; reads + decodes
// are I/O- and CPU-bound, so we fan out across worker goroutines.
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"log"
	"math/bits"
	"sync"
	"sync/atomic"
	"time"

	"github.com/corona10/goimagehash"
	_ "github.com/gen2brain/heic"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
)

type wallpaperRow struct {
	ID          int64
	OriginalURL string
	Phash       int64
}

func main() {
	force := flag.Bool("force", false, "recompute even when phash is already set")
	reportDupes := flag.Bool("report-dupes", false, "list near-duplicate pairs after the backfill")
	timeout := flag.Duration("timeout", 60*time.Second, "per-wallpaper download+decode timeout")
	concurrency := flag.Int("concurrency", 10, "number of parallel download+decode workers")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Silent),
	})
	if err != nil {
		log.Fatal("connect db: ", err)
	}

	var rows []wallpaperRow
	q := db.Table("wallpapers").Select("id, original_url, phash").Where("status = 1")
	if !*force {
		q = q.Where("phash = 0")
	}
	if err := q.Order("id ASC").Find(&rows).Error; err != nil {
		log.Fatal("query: ", err)
	}

	store, err := storage.New(cfg.MinIO)
	if err != nil {
		log.Fatal("connect minio: ", err)
	}

	fmt.Printf("Wallpapers to backfill: %d (concurrency=%d, timeout=%s, internal=%s)\n",
		len(rows), *concurrency, *timeout, cfg.MinIO.Endpoint)

	jobs := make(chan wallpaperRow)
	var ok, fail int64
	var wg sync.WaitGroup
	for i := 0; i < *concurrency; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := range jobs {
				ctx, cancel := context.WithTimeout(context.Background(), *timeout)
				hash, err := computePhash(ctx, store, r.OriginalURL)
				cancel()
				if err != nil {
					log.Printf("  [FAIL] %d: %v", r.ID, err)
					atomic.AddInt64(&fail, 1)
					continue
				}
				if err := db.Table("wallpapers").Where("id = ?", r.ID).Update("phash", hash).Error; err != nil {
					log.Printf("  [FAIL] %d save: %v", r.ID, err)
					atomic.AddInt64(&fail, 1)
					continue
				}
				n := atomic.AddInt64(&ok, 1)
				if n%25 == 0 {
					log.Printf("  progress: %d ok / %d fail", n, atomic.LoadInt64(&fail))
				}
			}
		}()
	}

	for _, r := range rows {
		jobs <- r
	}
	close(jobs)
	wg.Wait()

	fmt.Printf("Backfill done. ok=%d fail=%d\n", ok, fail)

	if *reportDupes {
		reportDuplicates(db)
	}
}

func computePhash(ctx context.Context, store *storage.Storage, originalURL string) (int64, error) {
	if originalURL == "" {
		return 0, fmt.Errorf("empty original_url")
	}
	objectKey := store.ObjectKeyFromURL(originalURL)
	if objectKey == "" {
		return 0, fmt.Errorf("cannot derive object key from %q", originalURL)
	}
	object, err := store.GetObject(ctx, objectKey)
	if err != nil {
		return 0, err
	}
	defer object.Close()
	data, err := io.ReadAll(object)
	if err != nil {
		return 0, err
	}
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return 0, fmt.Errorf("decode: %w", err)
	}
	h, err := goimagehash.PerceptionHash(img)
	if err != nil {
		return 0, fmt.Errorf("phash: %w", err)
	}
	return int64(h.GetHash()), nil
}

const dupHammingThreshold = 5

func reportDuplicates(db *gorm.DB) {
	var rows []wallpaperRow
	if err := db.Table("wallpapers").Select("id, original_url, phash").
		Where("status = 1 AND phash <> 0").
		Order("id ASC").
		Find(&rows).Error; err != nil {
		log.Printf("report query: %v", err)
		return
	}
	fmt.Printf("\nNear-duplicate pairs (Hamming <= %d):\n", dupHammingThreshold)
	found := 0
	for i := range rows {
		for j := i + 1; j < len(rows); j++ {
			d := bits.OnesCount64(uint64(rows[i].Phash ^ rows[j].Phash))
			if d <= dupHammingThreshold {
				fmt.Printf("  %d ↔ %d  (hamming=%d)\n", rows[i].ID, rows[j].ID, d)
				found++
			}
		}
	}
	if found == 0 {
		fmt.Println("  none")
	}
}
