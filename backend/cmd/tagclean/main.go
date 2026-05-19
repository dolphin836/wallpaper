// tagclean asks Claude to look at the full tag taxonomy and propose
// from→to renames that consolidate trivial variants (singular/plural,
// hyphenation, obvious synonyms). Two-phase by design — Claude proposes,
// you review, then a second invocation applies.
//
// Usage:
//
//	./tagclean                       # dry-run: print proposed renames as JSON
//	./tagclean --propose-out FILE    # save proposed renames JSON to FILE
//	./tagclean --apply-from FILE     # apply a (possibly hand-edited) renames JSON
//	./tagclean --commit              # propose + apply in one shot (no review window)
//
// Recommended:
//   1. ./tagclean --propose-out /tmp/renames.json
//   2. Eyeball the JSON, delete anything you disagree with.
//   3. ./tagclean --apply-from /tmp/renames.json
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/llm"
)

func main() {
	var (
		commit      bool
		proposeOut  string
		applyFrom   string
	)
	flag.BoolVar(&commit, "commit", false, "propose and apply in one shot (no review window)")
	flag.StringVar(&proposeOut, "propose-out", "", "write proposed renames JSON to this file (no DB writes)")
	flag.StringVar(&applyFrom, "apply-from", "", "read renames JSON from this file and apply (no LLM call)")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}

	ctx := context.Background()

	// Path 1: --apply-from skips the LLM entirely and applies a saved/
	// hand-edited proposal. This is the recommended write path.
	if applyFrom != "" {
		raw, err := os.ReadFile(applyFrom)
		if err != nil {
			log.Fatal("read renames file: ", err)
		}
		var doc struct{ Renames []llm.TagMerge `json:"renames"` }
		if err := json.Unmarshal(raw, &doc); err != nil {
			log.Fatal("parse renames json: ", err)
		}
		fmt.Printf("applying %d renames from %s\n", len(doc.Renames), applyFrom)
		applyMerges(ctx, db, doc.Renames)
		return
	}

	// Path 2: propose via LLM, optionally apply.
	if cfg.Anthropic.APIKey == "" {
		log.Fatal("ANTHROPIC_API_KEY is not set in env")
	}

	tags := loadTags(ctx, db)
	fmt.Printf("loaded %d tags from DB\n", len(tags))

	llmClient := llm.New(cfg.Anthropic.APIKey)
	fmt.Println("asking Claude for rename proposals (may take 20-60s)...")
	merges, err := llmClient.ProposeTagMerges(ctx, tags)
	if err != nil {
		log.Fatal("propose merges: ", err)
	}
	fmt.Printf("Claude proposed %d renames\n", len(merges))

	// Resolve targets that don't exist as tags yet — those become "rename"
	// operations rather than "merge" ones; both are fine, just useful to
	// see the breakdown.
	tagSet := make(map[string]bool, len(tags))
	for _, t := range tags {
		tagSet[t.Name] = true
	}
	merges = filterValid(merges, tagSet)

	doc := struct{ Renames []llm.TagMerge `json:"renames"` }{Renames: merges}
	out, _ := json.MarshalIndent(doc, "", "  ")

	if proposeOut != "" {
		if err := os.WriteFile(proposeOut, out, 0644); err != nil {
			log.Fatal("write file: ", err)
		}
		fmt.Printf("wrote proposals to %s — review and run with --apply-from\n", proposeOut)
		return
	}

	if !commit {
		fmt.Println("--- proposed renames (dry-run) ---")
		fmt.Println(string(out))
		fmt.Println("--- pass --commit to apply, or --propose-out FILE for human review first ---")
		return
	}

	applyMerges(ctx, db, merges)
}

func loadTags(ctx context.Context, db *gorm.DB) []llm.TagInput {
	type row struct {
		Name string
		N    int
	}
	var rows []row
	if err := db.WithContext(ctx).Raw(`
		SELECT t.name, COUNT(wt.wallpaper_id) AS n
		  FROM tags t
		  LEFT JOIN wallpaper_tags wt ON wt.tag_id = t.id
		 GROUP BY t.name
		 ORDER BY n DESC, t.name ASC
	`).Scan(&rows).Error; err != nil {
		log.Fatal("load tags: ", err)
	}
	out := make([]llm.TagInput, len(rows))
	for i, r := range rows {
		out[i] = llm.TagInput{Name: r.Name, Count: r.N}
	}
	return out
}

// filterValid drops renames whose source isn't actually in the tag table
// (defensive — Claude shouldn't hallucinate them, but it's cheap to check).
func filterValid(merges []llm.TagMerge, existing map[string]bool) []llm.TagMerge {
	out := merges[:0]
	skipped := 0
	for _, m := range merges {
		if !existing[m.From] {
			skipped++
			continue
		}
		out = append(out, m)
	}
	if skipped > 0 {
		fmt.Printf("(dropped %d renames whose source tag no longer exists)\n", skipped)
	}
	return out
}

// applyMerges runs each rename in its own transaction. For each (from → to):
//
//  1. If `to` doesn't yet exist as a tag row, rename `from` → `to` and stop.
//     This is a cheap UPDATE on the tags table; wallpaper_tags links unaffected.
//  2. Otherwise both exist: re-point every wallpaper_tags row pointing at
//     `from` to instead point at `to` (with ON CONFLICT DO NOTHING so we
//     never duplicate a (wallpaper_id, tag_id) pair), then drop the leftover
//     links and finally the `from` tag.
//
// Wrapping each rename individually means a malformed merge in the middle of
// the batch doesn't roll back the work that already succeeded.
func applyMerges(ctx context.Context, db *gorm.DB, merges []llm.TagMerge) {
	var ok, skipped, failed int
	for i, m := range merges {
		err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			var fromID int64
			if err := tx.Raw(`SELECT id FROM tags WHERE name = ?`, m.From).Scan(&fromID).Error; err != nil {
				return err
			}
			if fromID == 0 {
				return fmt.Errorf("tag %q no longer exists (race or already merged)", m.From)
			}
			var toID int64
			if err := tx.Raw(`SELECT id FROM tags WHERE name = ?`, m.To).Scan(&toID).Error; err != nil {
				return err
			}
			if toID == 0 {
				// Path 1: rename in place.
				return tx.Exec(`UPDATE tags SET name = ? WHERE id = ?`, m.To, fromID).Error
			}
			// Path 2: merge. Re-point links (dedup), drop dangling, delete from.
			if err := tx.Exec(`
				INSERT INTO wallpaper_tags (wallpaper_id, tag_id)
				SELECT wallpaper_id, ? FROM wallpaper_tags WHERE tag_id = ?
				ON CONFLICT DO NOTHING
			`, toID, fromID).Error; err != nil {
				return err
			}
			if err := tx.Exec(`DELETE FROM wallpaper_tags WHERE tag_id = ?`, fromID).Error; err != nil {
				return err
			}
			return tx.Exec(`DELETE FROM tags WHERE id = ?`, fromID).Error
		})
		switch {
		case err == nil:
			ok++
			fmt.Printf("[%d/%d] %s → %s\n", i+1, len(merges), m.From, m.To)
		case strings.Contains(err.Error(), "no longer exists"):
			skipped++
			fmt.Printf("[%d/%d] SKIP %s → %s (%v)\n", i+1, len(merges), m.From, m.To, err)
		default:
			failed++
			fmt.Printf("[%d/%d] FAIL %s → %s: %v\n", i+1, len(merges), m.From, m.To, err)
		}
	}
	fmt.Println(strings.Repeat("-", 60))
	fmt.Printf("done: %d applied, %d skipped, %d failed\n", ok, skipped, failed)
}
