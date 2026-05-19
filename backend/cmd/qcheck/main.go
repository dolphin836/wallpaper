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
	"github.com/wallpaper/backend/internal/pkg/storage"
)

type wallpaperRow struct {
	ID         int64
	ThumbURL   string
	PreviewURL string
}

func main() {
	var (
		commit          bool
		limit           int
		rescan          bool
		pause           time.Duration
		cleanupFlagged  bool
	)
	flag.BoolVar(&commit, "commit", false, "actually persist quality assessments")
	flag.IntVar(&limit, "limit", 0, "process at most N wallpapers (0 = unlimited)")
	flag.BoolVar(&rescan, "rescan", false, "also re-evaluate rows that already carry a non-ok quality_flag (default: only unassessed). Approved rows (quality_flag='ok') are NEVER re-evaluated — admin approval is final.")
	flag.DurationVar(&pause, "pause", 400*time.Millisecond, "delay between API calls (rate-limit cushion)")
	flag.BoolVar(&cleanupFlagged, "cleanup-flagged", false, "when an assessment returns a non-ok flag, also delete that wallpaper's device variants (DB rows + MinIO objects) so the moderation queue and storage stay in sync")
	cleanupOnly := flag.Bool("cleanup-only", false, "skip the LLM entirely and just drop variants for every row that is already flagged (quality_flag NOT IN ('', 'ok')). Useful for catching up after the first qcheck pass ran without --cleanup-flagged.")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	if !*cleanupOnly && cfg.Anthropic.APIKey == "" {
		log.Fatal("ANTHROPIC_API_KEY is not set in env")
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}
	ctx := context.Background()

	// --cleanup-only short-circuits the LLM path entirely: walk every
	// already-flagged row and drop its device variants. Use case is
	// "the first qcheck pass ran without --cleanup-flagged, now I want
	// to free up the storage."
	if *cleanupOnly {
		if !commit {
			log.Fatal("--cleanup-only requires --commit (it only writes)")
		}
		store, err := storage.New(cfg.MinIO)
		if err != nil {
			log.Fatal("init storage: ", err)
		}
		var ids []int64
		if err := db.WithContext(ctx).
			Table("wallpapers").
			Where("status = ? AND quality_flag NOT IN ('', 'ok')", model.WallpaperStatusPublished).
			Pluck("id", &ids).Error; err != nil {
			log.Fatal("list flagged: ", err)
		}
		fmt.Printf("found %d already-flagged wallpapers; cleaning variants...\n", len(ids))
		total := 0
		for i, id := range ids {
			n := dropVariants(ctx, db, store, id)
			total += n
			fmt.Printf("[%d/%d] id=%d → dropped %d variants\n", i+1, len(ids), id, n)
		}
		fmt.Printf("done: dropped %d variants across %d wallpapers\n", total, len(ids))
		return
	}

	// Pull the work list. By default we only score rows that haven't been
	// assessed yet — second-pass moderation across the entire catalog
	// would be wasteful and a bit noisy, since Claude isn't always
	// stable to the boundary between "ok" and "low_aesthetic".
	var rows []wallpaperRow
	q := db.WithContext(ctx).
		Table("wallpapers").
		Select("id, thumb_url, preview_url").
		Where("status = ?", model.WallpaperStatusPublished).
		// Approved rows are sticky — once an admin has cleared a flag back
		// to 'ok' we treat that as final and never let the LLM second-
		// guess them, even when --rescan is set.
		Where("quality_flag <> 'ok'").
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

	// Storage handle only needed if we're going to delete variant objects
	// for flagged rows. Built lazily so a dry-run never has to talk to
	// MinIO (and `cmd/qcheck --commit` without --cleanup-flagged stays
	// usable in environments where MinIO is unreachable).
	var store *storage.Storage
	if commit && cleanupFlagged {
		store, err = storage.New(cfg.MinIO)
		if err != nil {
			log.Fatal("init storage (needed for --cleanup-flagged): ", err)
		}
	}

	flagCounts := map[string]int{}
	var ok, skipped, failed, cleaned int

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
			// On non-ok flags, drop the device variants for this
			// wallpaper. Best-effort — MinIO delete failures log but
			// don't fail the run; the orphaned objects will eventually
			// be picked up by a sweep. Admin can re-approve via
			// "Mark as OK" which re-emits wallpaper.uploaded and the
			// worker regenerates variants from the original.
			if cleanupFlagged && assessment.Flag != "ok" {
				n := dropVariants(ctx, db, store, r.ID)
				cleaned += n
				if n > 0 {
					fmt.Printf("        ↳ dropped %d variants for flagged wallpaper\n", n)
				}
			}
		}
		ok++
		if pause > 0 {
			time.Sleep(pause)
		}
	}

	fmt.Println(strings.Repeat("-", 60))
	fmt.Printf("done: %d assessed, %d skipped, %d failed", ok, skipped, failed)
	if cleanupFlagged {
		fmt.Printf(", %d variants cleaned", cleaned)
	}
	fmt.Println()
	fmt.Println("flag distribution:")
	for _, f := range llm.AllowedQualityFlags {
		if c := flagCounts[f]; c > 0 {
			fmt.Printf("  %-16s %d\n", f, c)
		}
	}
}

// dropVariants deletes every device variant attached to wallpaperID — DB
// rows in wallpaper_variants and the corresponding MinIO objects. Returns
// the number of variants removed (or attempted to). Best-effort across
// storage: a MinIO-side failure logs and continues so a single bad delete
// doesn't strand the DB in a half-state.
func dropVariants(ctx context.Context, db *gorm.DB, store *storage.Storage, wallpaperID int64) int {
	type row struct {
		ID  int64
		URL string
	}
	var rows []row
	if err := db.WithContext(ctx).
		Table("wallpaper_variants").
		Select("id, url").
		Where("wallpaper_id = ?", wallpaperID).
		Find(&rows).Error; err != nil {
		fmt.Printf("        ↳ variant lookup err: %v\n", err)
		return 0
	}
	for _, r := range rows {
		key := store.ObjectKeyFromURL(r.URL)
		if key == "" {
			continue
		}
		if err := store.Delete(ctx, key); err != nil {
			fmt.Printf("        ↳ minio delete failed (key=%s): %v\n", key, err)
		}
	}
	if err := db.WithContext(ctx).
		Where("wallpaper_id = ?", wallpaperID).
		Delete(&model.WallpaperVariant{}).Error; err != nil {
		fmt.Printf("        ↳ variant db delete err: %v\n", err)
	}
	return len(rows)
}
