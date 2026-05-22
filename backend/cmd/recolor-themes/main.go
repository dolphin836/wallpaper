// recolor-themes assigns an accent_color to every themed (kind=1)
// wallpaper collection that doesn't already have one. Reads title +
// description, asks Claude for a single OKLCH color, writes the result
// back. Idempotent — re-running picks up only the still-uncolored rows.
//
// Background: collections.accent_color was added after the first 21
// themed weeks were generated, so all of them landed with accent_color
// = ''. This CLI fills them in once. Newly generated themes already
// include the color (cmd/weekly-drop hands the field through).
//
// Usage (via scripts/recolor-themes-prod.sh from a developer Mac, since
// Claude is offshore-blocked from prod):
//   ./scripts/recolor-themes-prod.sh
package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/llm"
	"github.com/wallpaper/backend/internal/repo"
)

type row struct {
	ID          int64
	Title       string
	Description string
}

func main() {
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

	var rows []row
	if err := db.WithContext(ctx).Raw(`
		SELECT id, title, COALESCE(description, '') AS description
		FROM collections
		WHERE kind = 1 AND (accent_color IS NULL OR accent_color = '')
		ORDER BY year ASC, week ASC
	`).Scan(&rows).Error; err != nil {
		log.Fatal("query collections: ", err)
	}
	fmt.Printf("found %d themed collections without accent_color\n", len(rows))
	if len(rows) == 0 {
		return
	}

	llmClient := llm.New(cfg.Anthropic.APIKey, repo.NewLLMUsageRepo(db))

	var ok, failed int
	for i, r := range rows {
		// Stripping the "Week NN · " prefix so Claude focuses on the
		// editorial theme, not the calendar marker.
		title := r.Title
		if idx := indexOfSep(title); idx > 0 {
			title = title[idx+len(" · "):]
		}
		accent, err := llmClient.ProposeThemeAccent(ctx, title, r.Description)
		if err != nil {
			fmt.Printf("[%d/%d] id=%d FAILED: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}
		if err := db.WithContext(ctx).Exec(
			`UPDATE collections SET accent_color = ? WHERE id = ?`, accent, r.ID,
		).Error; err != nil {
			fmt.Printf("[%d/%d] id=%d UPDATE FAILED: %v\n", i+1, len(rows), r.ID, err)
			failed++
			continue
		}
		fmt.Printf("[%d/%d] id=%d %q → %s\n", i+1, len(rows), r.ID, title, accent)
		ok++
		time.Sleep(400 * time.Millisecond) // gentle rate-limit cushion
	}
	fmt.Printf("\ndone: %d colored, %d failed\n", ok, failed)
}

// indexOfSep returns the byte index of " · " in s, or -1.
func indexOfSep(s string) int {
	const sep = " · "
	for i := 0; i+len(sep) <= len(s); i++ {
		if s[i:i+len(sep)] == sep {
			return i
		}
	}
	return -1
}
