// weekly-drop generates the two artifacts that drive the new Home page
// for the current ISO week:
//
//  1. A 10-wallpaper "Weekly Picks" slate (no theme — just hot rows from
//     the recent uploads, with a historical-tail fallback when the recent
//     pool is thin). Stored in weekly_picks.
//  2. A themed editor collection (kind=1) with 10 wallpapers that share
//     one coherent dimension. Theme is decided by Claude from a sample
//     of recent published wallpapers. Stored in collections (+ link rows).
//
// Both run in one shot so the Home page is consistent. Picks and themes
// are allowed to overlap — by design.
//
// Usage:
//
//	./weekly-drop                       # dry-run: print what would happen
//	./weekly-drop --commit              # write picks + create theme collection
//	./weekly-drop --commit --week 21    # generate for an explicit week
//	./weekly-drop --commit --year 2026 --week 21
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/llm"
	"github.com/wallpaper/backend/internal/pkg/slug"
	"github.com/wallpaper/backend/internal/repo"
)

const (
	weeklyPicksTarget        = 10
	themeCandidatePoolSize   = 60 // how many recent rows we hand to Claude
	themeMinPicks            = 6  // minimum coherent picks before we publish
	recentLookbackDays       = 7
	historicalLookbackMonths = 6
)

func main() {
	var (
		commit bool
		year   int
		week   int
		owner  int64
	)
	flag.BoolVar(&commit, "commit", false, "actually write to DB (default: dry-run)")
	flag.IntVar(&year, "year", 0, "ISO year (default: current)")
	flag.IntVar(&week, "week", 0, "ISO week 1-53 (default: current)")
	flag.Int64Var(&owner, "owner", 1, "user id that owns generated theme collections (defaults to admin user 1)")
	flag.Parse()

	if year == 0 || week == 0 {
		y, w := time.Now().UTC().ISOWeek()
		if year == 0 {
			year = y
		}
		if week == 0 {
			week = w
		}
	}
	if week < 1 || week > 53 {
		log.Fatalf("--week must be 1-53, got %d", week)
	}

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
	weeklyRepo := repo.NewWeeklyPickRepo(db)
	collectionRepo := repo.NewCollectionRepo(db)
	llmClient := llm.New(cfg.Anthropic.APIKey)

	fmt.Printf("==> Generating Weekly Drop for ISO %d-W%02d\n", year, week)

	// ── PART 1: Weekly Picks (no theme, just hot recent + historical tail).
	pickIDs := selectWeeklyPicks(ctx, weeklyRepo)
	fmt.Printf("Picks selected: %d wallpapers\n", len(pickIDs))
	for i, id := range pickIDs {
		fmt.Printf("  [%2d] id=%d\n", i+1, id)
	}

	// ── PART 2: Theme Collection.
	candidates := loadThemeCandidates(ctx, db, themeCandidatePoolSize)
	fmt.Printf("Theme candidates: %d\n", len(candidates))
	if len(candidates) < themeMinPicks {
		fmt.Println("not enough candidates for a theme; will skip theme generation")
	}

	var pick *llm.ThemePick
	if len(candidates) >= themeMinPicks {
		fmt.Println("Asking Claude for a coherent weekly theme...")
		pick, err = llmClient.ProposeWeeklyTheme(ctx, candidates)
		if err != nil {
			log.Fatal("propose theme: ", err)
		}
		// Validate that returned ids are a subset of the offered pool —
		// the model occasionally hallucinates ids when nothing fits.
		offered := make(map[int64]bool, len(candidates))
		for _, c := range candidates {
			offered[c.ID] = true
		}
		valid := pick.WallpaperIDs[:0]
		for _, id := range pick.WallpaperIDs {
			if offered[id] {
				valid = append(valid, id)
			}
		}
		pick.WallpaperIDs = valid
		fmt.Printf("Theme: %q\n", pick.ThemeName)
		fmt.Printf("  %s\n", pick.Description)
		fmt.Printf("  %d wallpapers in theme\n", len(pick.WallpaperIDs))
		if len(pick.WallpaperIDs) < themeMinPicks {
			fmt.Println("  (theme rejected — fewer than %d valid picks)")
			pick = nil
		}
	}

	if !commit {
		fmt.Println("\n--- dry-run; pass --commit to write ---")
		return
	}

	// ── Persist picks.
	if len(pickIDs) > 0 {
		if err := weeklyRepo.Insert(ctx, int16(year), int16(week), pickIDs); err != nil {
			log.Fatal("insert weekly picks: ", err)
		}
		fmt.Printf("Wrote %d picks for %d-W%02d\n", len(pickIDs), year, week)
	}

	// ── Persist theme collection.
	if pick != nil && len(pick.WallpaperIDs) >= themeMinPicks {
		col := &model.Collection{
			UserID:      owner,
			Title:       fmt.Sprintf("Week %02d · %s", week, pick.ThemeName),
			Description: pick.Description,
			IsPublic:    true,
			Kind:        1,
			Year:        int16(year),
			Week:        int16(week),
		}
		col.Slug = slug.Generate(fmt.Sprintf("week-%d-%02d-%s", year, week, pick.ThemeName))
		if err := collectionRepo.Create(ctx, col); err != nil {
			log.Fatal("create collection: ", err)
		}
		// Attach wallpapers in pick order — repo.AddWallpaper bumps
		// wallpaper_count and sets sort_order so the detail page
		// renders them in the order Claude returned.
		attached := 0
		for _, wpID := range pick.WallpaperIDs {
			if err := collectionRepo.AddWallpaper(ctx, col.ID, wpID); err != nil {
				fmt.Printf("  add wallpaper %d failed: %v\n", wpID, err)
				continue
			}
			attached++
		}
		fmt.Printf("Created theme collection %q (id=%d, slug=%s, %d wallpapers)\n",
			col.Title, col.ID, col.Slug, attached)
	} else {
		fmt.Println("No theme collection created this week (insufficient coherent picks)")
	}

	// ── Sanity output.
	fmt.Println("\nDone. Review on /weekly-picks or check the home page.")
	_ = os.Stdout.Sync()
}

// selectWeeklyPicks chooses 10 wallpapers by hot score, preferring recent
// uploads and falling back to the historical tail when the recent pool is
// thin. Anything that has appeared in any past slate is excluded so users
// see fresh content every week.
func selectWeeklyPicks(ctx context.Context, weeklyRepo *repo.WeeklyPickRepo) []int64 {
	excluded, err := weeklyRepo.AllPickedIDs(ctx)
	if err != nil {
		log.Fatal("load excluded: ", err)
	}
	excludedIDs := make([]int64, 0, len(excluded))
	for id := range excluded {
		excludedIDs = append(excludedIDs, id)
	}
	since := time.Now().UTC().AddDate(0, 0, -recentLookbackDays).Unix()
	recent, err := weeklyRepo.CandidatePool(ctx, since, excludedIDs)
	if err != nil {
		log.Fatal("recent candidate pool: ", err)
	}

	picked := make([]int64, 0, weeklyPicksTarget)
	seen := make(map[int64]bool, weeklyPicksTarget)
	for _, c := range recent {
		if len(picked) >= weeklyPicksTarget {
			break
		}
		if seen[c.ID] {
			continue
		}
		seen[c.ID] = true
		picked = append(picked, c.ID)
	}
	if len(picked) >= weeklyPicksTarget {
		return picked
	}

	// Recent pool too small — top up from history (last 6 months).
	deadline := time.Now().UTC().AddDate(0, -historicalLookbackMonths, 0).Unix()
	hist, err := weeklyRepo.CandidatePool(ctx, deadline, append(excludedIDs, picked...))
	if err != nil {
		log.Fatal("historical candidate pool: ", err)
	}
	for _, c := range hist {
		if len(picked) >= weeklyPicksTarget {
			break
		}
		if seen[c.ID] {
			continue
		}
		seen[c.ID] = true
		picked = append(picked, c.ID)
	}
	return picked
}

// loadThemeCandidates fetches the recent published catalog (with quality
// ok) plus tags + category, packaged for the LLM's theme decision. The
// pool is intentionally larger than the target (so Claude has slack to
// pick a coherent subset).
func loadThemeCandidates(ctx context.Context, db *gorm.DB, limit int) []llm.ThemeCandidate {
	type row struct {
		ID         int64
		CategoryID int64
		Category   string
		Title      string
		Dominant   string
	}
	since := time.Now().UTC().AddDate(0, 0, -14) // a touch wider than picks
	var rows []row
	if err := db.WithContext(ctx).Raw(`
		SELECT w.id, w.category_id, COALESCE(c.slug, '') AS category,
		       w.title, w.dominant_color AS dominant
		FROM wallpapers w
		LEFT JOIN categories c ON c.id = w.category_id
		WHERE w.status = 1
		  AND w.quality_flag = 'ok'
		  AND w.created_at >= ?
		ORDER BY (3.0 * w.like_count + 2.0 * w.download_count + 0.1 * w.view_count) DESC
		LIMIT ?
	`, since, limit).Scan(&rows).Error; err != nil {
		log.Fatal("load theme candidates: ", err)
	}
	if len(rows) < themeMinPicks {
		// Fall back to historical pool — same as picks logic.
		if err := db.WithContext(ctx).Raw(`
			SELECT w.id, w.category_id, COALESCE(c.slug, '') AS category,
			       w.title, w.dominant_color AS dominant
			FROM wallpapers w
			LEFT JOIN categories c ON c.id = w.category_id
			WHERE w.status = 1 AND w.quality_flag = 'ok'
			ORDER BY (3.0 * w.like_count + 2.0 * w.download_count + 0.1 * w.view_count) DESC
			LIMIT ?
		`, limit).Scan(&rows).Error; err != nil {
			log.Fatal("load theme candidates (historical): ", err)
		}
	}
	ids := make([]int64, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	// Attach tags in one batch.
	tagsByWp := loadTags(ctx, db, ids)

	out := make([]llm.ThemeCandidate, len(rows))
	for i, r := range rows {
		out[i] = llm.ThemeCandidate{
			ID:         r.ID,
			CategoryID: r.CategoryID,
			Category:   r.Category,
			Tags:       tagsByWp[r.ID],
			Title:      strings.TrimSpace(r.Title),
			Dominant:   r.Dominant,
		}
	}
	return out
}

func loadTags(ctx context.Context, db *gorm.DB, ids []int64) map[int64][]string {
	out := make(map[int64][]string, len(ids))
	if len(ids) == 0 {
		return out
	}
	type row struct {
		WallpaperID int64
		Name        string
	}
	var rows []row
	if err := db.WithContext(ctx).Raw(`
		SELECT wt.wallpaper_id, t.name
		FROM wallpaper_tags wt
		JOIN tags t ON t.id = wt.tag_id
		WHERE wt.wallpaper_id IN ?
	`, ids).Scan(&rows).Error; err != nil {
		log.Fatal("load tags: ", err)
	}
	for _, r := range rows {
		out[r.WallpaperID] = append(out[r.WallpaperID], r.Name)
	}
	return out
}
