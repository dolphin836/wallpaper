// [skill: go-team-standards · 错误处理 · 外部IO超时] offline UGC translation backfill CLI
//
// i18nfill backfills the *_i18n JSONB columns that power content
// localization: tag names plus public collection titles/descriptions.
// It batches untranslated rows through Claude and writes the four-language
// maps back. Like autotag/tagclean it is a LOCAL tool — the Anthropic API
// is unreachable from the prod host, so run it from a dev machine with an
// SSH tunnel to the prod Postgres (and ANTHROPIC_API_KEY in the env).
//
// Usage:
//
//	./i18nfill                       # dry-run: show what would be translated
//	./i18nfill --commit              # translate + write back
//	./i18nfill --commit --limit 20   # canary the first 20 rows per kind
//	./i18nfill --commit --only tags  # tags | collections | all (default all)
//	./i18nfill --commit --force      # re-translate rows that already have all languages
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/llm"
	"github.com/wallpaper/backend/internal/repo"
)

// needsFillExpr matches rows whose i18n map is missing at least one of the
// four UI languages (jsonb ?& tests key presence).
const needsFillExpr = `NOT (%s ?& array['en','zh-CN','zh-TW','ja'])`

const (
	tagBatchSize        = 40
	collectionBatchSize = 8
	callTimeout         = 3 * time.Minute
)

func main() {
	var (
		commit bool
		limit  int
		only   string
		force  bool
		pause  time.Duration
	)
	flag.BoolVar(&commit, "commit", false, "actually write translations to the DB (default: dry-run)")
	flag.IntVar(&limit, "limit", 0, "process at most N rows per kind (0 = unlimited)")
	flag.StringVar(&only, "only", "all", "which kind to fill: tags | collections | all")
	flag.BoolVar(&force, "force", false, "re-translate rows that already have all four languages")
	flag.DurationVar(&pause, "pause", time.Second, "delay between API calls (rate-limit cushion)")
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
	client := llm.New(cfg.Anthropic.APIKey, repo.NewLLMUsageRepo(db))

	if only == "all" || only == "tags" {
		if err := fillTags(ctx, db, client, commit, limit, force, pause); err != nil {
			log.Fatal("fill tags: ", err)
		}
	}
	if only == "all" || only == "collections" {
		if err := fillCollections(ctx, db, client, commit, limit, force, pause); err != nil {
			log.Fatal("fill collections: ", err)
		}
	}
	if !commit {
		fmt.Println("dry-run — pass --commit to write changes")
	}
}

func fillTags(ctx context.Context, db *gorm.DB, client *llm.Client, commit bool, limit int, force bool, pause time.Duration) error {
	var tags []model.Tag
	q := db.WithContext(ctx).Select("id, name, name_i18n").Order("id ASC")
	if !force {
		q = q.Where(fmt.Sprintf(needsFillExpr, "name_i18n"))
	}
	if limit > 0 {
		q = q.Limit(limit)
	}
	if err := q.Find(&tags).Error; err != nil {
		return fmt.Errorf("query tags: %w", err)
	}
	fmt.Printf("tags: %d rows need translation\n", len(tags))

	for start := 0; start < len(tags); start += tagBatchSize {
		end := min(start+tagBatchSize, len(tags))
		batch := tags[start:end]

		items := make([]llm.TranslateItem, 0, len(batch))
		for _, t := range batch {
			items = append(items, llm.TranslateItem{ID: t.ID, Kind: "tag", Text: t.Name})
		}
		if !commit {
			for _, t := range batch {
				fmt.Printf("  would translate tag %d: %q\n", t.ID, t.Name)
			}
			continue
		}

		callCtx, cancel := context.WithTimeout(ctx, callTimeout)
		got, err := client.TranslateBatch(callCtx, items)
		cancel()
		if err != nil {
			return fmt.Errorf("translate tag batch at %d: %w", start, err)
		}
		for _, t := range batch {
			m, ok := got[t.ID]
			if !ok {
				fmt.Printf("  ! tag %d (%q) missing from response, will retry next run\n", t.ID, t.Name)
				continue
			}
			if err := db.WithContext(ctx).Model(&model.Tag{}).
				Where("id = ?", t.ID).
				UpdateColumn("name_i18n", model.I18n(m)).Error; err != nil {
				return fmt.Errorf("write tag %d: %w", t.ID, err)
			}
			fmt.Printf("  ✓ tag %d %q → zh-CN %q · zh-TW %q · ja %q\n", t.ID, t.Name, m["zh-CN"], m["zh-TW"], m["ja"])
		}
		time.Sleep(pause)
	}
	return nil
}

func fillCollections(ctx context.Context, db *gorm.DB, client *llm.Client, commit bool, limit int, force bool, pause time.Duration) error {
	var cols []model.Collection
	// Private collections are only ever seen by their owner (who wrote the
	// text), so spend tokens on public ones only.
	q := db.WithContext(ctx).
		Select("id, title, description, title_i18n, description_i18n").
		Where("is_public = ?", true).
		Order("id ASC")
	if !force {
		q = q.Where(fmt.Sprintf(needsFillExpr, "title_i18n") +
			" OR (description <> '' AND " + fmt.Sprintf(needsFillExpr, "description_i18n") + ")")
	}
	if limit > 0 {
		q = q.Limit(limit)
	}
	if err := q.Find(&cols).Error; err != nil {
		return fmt.Errorf("query collections: %w", err)
	}
	fmt.Printf("collections: %d rows need translation\n", len(cols))

	for start := 0; start < len(cols); start += collectionBatchSize {
		end := min(start+collectionBatchSize, len(cols))
		batch := cols[start:end]

		// Titles ride on the collection id; descriptions on -id so one
		// call carries both fields without an extra lookup table.
		items := make([]llm.TranslateItem, 0, len(batch)*2)
		for _, c := range batch {
			items = append(items, llm.TranslateItem{ID: c.ID, Kind: "title", Text: c.Title})
			if c.Description != "" {
				items = append(items, llm.TranslateItem{ID: -c.ID, Kind: "description", Text: c.Description})
			}
		}
		if !commit {
			for _, c := range batch {
				fmt.Printf("  would translate collection %d: %q (desc %d chars)\n", c.ID, c.Title, len(c.Description))
			}
			continue
		}

		callCtx, cancel := context.WithTimeout(ctx, callTimeout)
		got, err := client.TranslateBatch(callCtx, items)
		cancel()
		if err != nil {
			return fmt.Errorf("translate collection batch at %d: %w", start, err)
		}
		for _, c := range batch {
			updates := map[string]any{}
			if m, ok := got[c.ID]; ok {
				updates["title_i18n"] = model.I18n(m)
			}
			if m, ok := got[-c.ID]; ok {
				updates["description_i18n"] = model.I18n(m)
			}
			if len(updates) == 0 {
				fmt.Printf("  ! collection %d (%q) missing from response, will retry next run\n", c.ID, c.Title)
				continue
			}
			// UpdateColumns skips gorm hooks so updated_at (and the list
			// ordering that reads it) is not perturbed by a backfill.
			if err := db.WithContext(ctx).Model(&model.Collection{}).
				Where("id = ?", c.ID).
				UpdateColumns(updates).Error; err != nil {
				return fmt.Errorf("write collection %d: %w", c.ID, err)
			}
			fmt.Printf("  ✓ collection %d %q (%d fields)\n", c.ID, c.Title, len(updates))
		}
		time.Sleep(pause)
	}
	return nil
}
