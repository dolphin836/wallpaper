// qcheck walks published wallpapers and runs each one through Claude
// vision to assign a quality flag (ok / blurry / watermark / ai_slop /
// text_overlay / low_aesthetic) plus a one-line reason. The flag goes
// into wallpapers.quality_flag for the admin moderation queue to filter
// on; "ok" rows are noise-free, anything else is a hint that an admin
// should glance at it.
//
// Usage:
//
//	./qcheck                          # dry-run on first N rows
//	./qcheck --commit                 # actually write quality_flag
//	./qcheck --commit --limit 10      # canary first
//	./qcheck --commit --rescan        # also re-assess rows already flagged
//
// Dry-run prints each decision; --commit additionally persists it.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/llm"
)

type wallpaperRow struct {
	ID         int64
	ThumbURL   string
	PreviewURL string
}

func main() {
	var (
		commit bool
		limit  int
		rescan bool
		pause  time.Duration
	)
	flag.BoolVar(&commit, "commit", false, "actually persist quality assessments")
	flag.IntVar(&limit, "limit", 0, "process at most N wallpapers (0 = unlimited)")
	flag.BoolVar(&rescan, "rescan", false, "include rows that already have a quality_flag (default: skip)")
	flag.DurationVar(&pause, "pause", 400*time.Millisecond, "delay between API calls (rate-limit cushion)")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	if cfg.Anthropic.APIKey == "" {
		log.Fatal("ANTHROPIC_API_KEY is not set in env")
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}
	ctx := context.Background()

	// Pull the work list. By default we only score rows that haven't been
	// assessed yet — second-pass moderation across the entire catalog
	// would be wasteful and a bit noisy, since Claude isn't always
	// stable to the boundary between "ok" and "low_aesthetic".
	var rows []wallpaperRow
	q := db.WithContext(ctx).
		Table("wallpapers").
		Select("id, thumb_url, preview_url").
		Where("status = ?", model.WallpaperStatusPublished).
		Order("id ASC")
	if !rescan {
		q = q.Where("quality_flag = ''")
	}
	if limit > 0 {
		q = q.Limit(limit)
	}
	if err := q.Find(&rows).Error; err != nil {
		log.Fatal("query wallpapers: ", err)
	}
	fmt.Printf("found %d wallpapers to assess\n", len(rows))
	if !commit {
		fmt.Println("dry-run — pass --commit to write changes")
	}
	if len(rows) == 0 {
		return
	}

	llmClient := llm.New(cfg.Anthropic.APIKey)

	flagCounts := map[string]int{}
	var ok, skipped, failed int

	for i, r := range rows {
		// Thumb first (smaller payload through Anthropic's image fetcher,
		// same MinIO-from-China latency story as autotag). Fall back to
		// preview if thumb errors out.
		candidates := []string{}
		if r.ThumbURL != "" {
			candidates = append(candidates, r.ThumbURL)
		}
		if r.PreviewURL != "" {
			candidates = append(candidates, r.PreviewURL)
		}
		if len(candidates) == 0 {
			fmt.Printf("[%d/%d] id=%d SKIP (no image url)\n", i+1, len(rows), r.ID)
			skipped++
			continue
		}

		var assessment *llm.QualityAssessment
		var err error
		for _, img := range candidates {
			assessment, err = llmClient.AssessQuality(ctx, img)
			if err == nil {
				break
			}
			if !strings.Contains(err.Error(), "timed out while trying to download") {
				break
			}
		}
		if err != nil {
			fmt.Printf("[%d/%d] id=%d ERR: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}

		flagCounts[assessment.Flag]++
		marker := "  "
		if assessment.Flag != "ok" {
			marker = "⚑ "
		}
		fmt.Printf("[%d/%d] %sid=%d → %s — %s\n", i+1, len(rows), marker, r.ID, assessment.Flag, assessment.Notes)

		if commit {
			if err := db.WithContext(ctx).Table("wallpapers").
				Where("id = ?", r.ID).
				Updates(map[string]any{
					"quality_flag":  assessment.Flag,
					"quality_notes": assessment.Notes,
				}).Error; err != nil {
				fmt.Printf("[%d/%d] id=%d DB ERR: %v\n", i+1, len(rows), r.ID, err)
				failed++
				continue
			}
		}
		ok++
		if pause > 0 {
			time.Sleep(pause)
		}
	}

	fmt.Println(strings.Repeat("-", 60))
	fmt.Printf("done: %d assessed, %d skipped, %d failed\n", ok, skipped, failed)
	fmt.Println("flag distribution:")
	for _, f := range llm.AllowedQualityFlags {
		if c := flagCounts[f]; c > 0 {
			fmt.Printf("  %-16s %d\n", f, c)
		}
	}
}
