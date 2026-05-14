// phashgen backfills the wallpapers.phash column for published wallpapers
// that pre-date the perceptual-hash dedup feature.
//
// Usage:
//   /bin/phashgen                    # only rows with phash=0
//   /bin/phashgen --force            # recompute every published row
//   /bin/phashgen --report-dupes     # after backfill, log near-duplicate pairs
//
// Runs inside the api container so it shares config/network with the API
// (env-driven DB DSN, MinIO public URL reachable). For ~hundreds of
// wallpapers the HTTP-GET-and-decode loop is fine; for tens of thousands
// switch to internal MinIO with a parallel worker pool.
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
	"net/http"
	"time"

	"github.com/corona10/goimagehash"
	_ "github.com/gen2brain/heic"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"

	"github.com/wallpaper/backend/internal/config"
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

	fmt.Printf("Wallpapers to backfill: %d\n", len(rows))
	client := &http.Client{Timeout: *timeout}

	var ok, fail int
	for _, r := range rows {
		ctx, cancel := context.WithTimeout(context.Background(), *timeout)
		hash, err := computePhash(ctx, client, r.OriginalURL)
		cancel()
		if err != nil {
			log.Printf("  [FAIL] %d %s: %v", r.ID, r.OriginalURL, err)
			fail++
			continue
		}
		if err := db.Table("wallpapers").Where("id = ?", r.ID).Update("phash", hash).Error; err != nil {
			log.Printf("  [FAIL] %d save: %v", r.ID, err)
			fail++
			continue
		}
		fmt.Printf("  [OK] %d -> phash=%d\n", r.ID, hash)
		ok++
	}
	fmt.Printf("Backfill done. ok=%d fail=%d\n", ok, fail)

	if *reportDupes {
		reportDuplicates(db)
	}
}

func computePhash(ctx context.Context, client *http.Client, url string) (int64, error) {
	if url == "" {
		return 0, fmt.Errorf("empty original_url")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return 0, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("http %d", resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
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
