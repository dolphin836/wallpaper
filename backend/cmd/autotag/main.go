// autotag scans published wallpapers and runs each unclassified one
// (category_id = 0 and no tags) through Claude's vision API to fill in
// category, tags, and — where the uploaded title is just a stock-photo
// file ID — a polished title suggestion.
//
// Usage:
//
//	./autotag                          # dry-run on first N rows, prints decisions
//	./autotag --commit                 # actually writes to the DB
//	./autotag --commit --limit 5       # canary the first 5
//	./autotag --commit --force         # re-classify even rows that already
//	                                   # have a category or tags
//
// Recommended: --commit --limit 5 first; spot-check a few wallpapers in
// the admin or on the site; then run the full batch.
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
	"github.com/wallpaper/backend/internal/repo"
)

type wallpaperRow struct {
	ID         int64
	Title      string
	ThumbURL   string
	PreviewURL string
	CategoryID int64
}

func main() {
	var (
		commit    bool
		limit     int
		force     bool
		pause     time.Duration
		updateTitle bool
	)
	flag.BoolVar(&commit, "commit", false, "actually write classifications to the DB (default: dry-run)")
	flag.IntVar(&limit, "limit", 0, "process at most N wallpapers (0 = unlimited)")
	flag.BoolVar(&force, "force", false, "re-classify rows that already have a category or tags")
	flag.DurationVar(&pause, "pause", 500*time.Millisecond, "delay between API calls (rate-limit cushion)")
	flag.BoolVar(&updateTitle, "update-title", false, "overwrite empty wallpaper titles with the model's suggestion")
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

	// Build slug → category_id map. The LLM returns slugs from a fixed
	// whitelist; the DB stores numeric IDs. If a slug somehow isn't in
	// the categories table we leave the row unclassified rather than
	// pin it to a wrong ID.
	categoryRepo := repo.NewCategoryRepo(db)
	cats, err := categoryRepo.List(ctx)
	if err != nil {
		log.Fatal("list categories: ", err)
	}
	slugToID := make(map[string]int64, len(cats))
	for _, c := range cats {
		slugToID[c.Slug] = c.ID
	}
	fmt.Printf("loaded %d categories: %s\n", len(cats), strings.Join(keys(slugToID), ", "))

	// Build the work list. Unless --force, only pick rows that have neither
	// a category nor any tags — those are the ones the LLM should fill in.
	var rows []wallpaperRow
	q := db.WithContext(ctx).
		Table("wallpapers").
		Select("id, title, thumb_url, preview_url, category_id").
		Where("status = ?", model.WallpaperStatusPublished).
		Order("id ASC")
	if !force {
		q = q.Where("category_id = 0")
		q = q.Where("NOT EXISTS (SELECT 1 FROM wallpaper_tags wt WHERE wt.wallpaper_id = wallpapers.id)")
	}
	if limit > 0 {
		q = q.Limit(limit)
	}
	if err := q.Find(&rows).Error; err != nil {
		log.Fatal("query wallpapers: ", err)
	}
	fmt.Printf("found %d wallpapers to classify\n", len(rows))
	if !commit {
		fmt.Println("dry-run — pass --commit to write changes")
	}
	if len(rows) == 0 {
		return
	}

	llmClient := llm.New(cfg.Anthropic.APIKey, repo.NewLLMUsageRepo(db))
	tagRepo := repo.NewTagRepo(db)

	var ok, skipped, failed int
	for i, r := range rows {
		// Prefer thumb (smaller, faster for the Anthropic server-side
		// fetcher — China-hosted MinIO is slow from outside, and the
		// preview can be hundreds of KB which times out). Fall back to
		// preview if thumb is missing, then preview if thumb errors.
		candidates := []string{}
		if r.ThumbURL != "" {
			candidates = append(candidates, r.ThumbURL)
		}
		if r.PreviewURL != "" {
			candidates = append(candidates, r.PreviewURL)
		}
		if len(candidates) == 0 {
			fmt.Printf("[%d/%d] id=%d SKIP (no thumb or preview URL)\n", i+1, len(rows), r.ID)
			skipped++
			continue
		}

		var cls *llm.Classification
		var err error
		for _, img := range candidates {
			cls, err = llmClient.Classify(ctx, img)
			if err == nil {
				break
			}
			// Only retry on Anthropic-side download timeout — anything
			// else is unlikely to differ between thumb and preview.
			if !strings.Contains(err.Error(), "timed out while trying to download") {
				break
			}
		}
		if err != nil {
			fmt.Printf("[%d/%d] id=%d CLASSIFY ERR: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}

		catID, catOK := slugToID[cls.CategorySlug]
		if !catOK {
			// Coerced "other" should always exist; if even that's missing
			// the categories table is malformed.
			fmt.Printf("[%d/%d] id=%d SKIP (unknown category slug %q)\n", i+1, len(rows), r.ID, cls.CategorySlug)
			skipped++
			continue
		}

		fmt.Printf("[%d/%d] id=%d → %s (%d tags) %s\n",
			i+1, len(rows), r.ID, cls.CategorySlug, len(cls.Tags),
			truncate(strings.Join(cls.Tags, ","), 60))

		if !commit {
			if pause > 0 {
				time.Sleep(pause)
			}
			continue
		}

		// Update category (and optionally title). Title is only overwritten
		// when the existing one is empty, since the upload flow lets users
		// type their own.
		updates := map[string]any{"category_id": catID}
		if updateTitle && strings.TrimSpace(r.Title) == "" && cls.TitleSuggestion != "" {
			updates["title"] = cls.TitleSuggestion
		}
		if err := db.WithContext(ctx).Table("wallpapers").
			Where("id = ?", r.ID).
			Updates(updates).Error; err != nil {
			fmt.Printf("[%d/%d] id=%d DB UPDATE ERR: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}

		// Create/lookup each tag and link it via wallpaper_tags. The repo
		// helper handles the case-insensitive upsert and the link-table
		// rewrite atomically.
		tagIDs := make([]int64, 0, len(cls.Tags))
		for _, name := range cls.Tags {
			t, err := tagRepo.GetOrCreate(ctx, name)
			if err != nil {
				fmt.Printf("[%d/%d] id=%d TAG %q ERR: %v\n", i+1, len(rows), r.ID, name, err)
				continue
			}
			tagIDs = append(tagIDs, t.ID)
		}
		if len(tagIDs) > 0 {
			if err := tagRepo.SetWallpaperTags(ctx, r.ID, tagIDs); err != nil {
				fmt.Printf("[%d/%d] id=%d TAG LINK ERR: %v\n", i+1, len(rows), r.ID, err)
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
	fmt.Printf("done: %d classified, %d skipped, %d failed\n", ok, skipped, failed)
}

func keys(m map[string]int64) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	return out
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n] + "…"
}
