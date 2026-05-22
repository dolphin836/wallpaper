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
	weeklyPicksTarget      = 10
	pickCandidatePoolSize  = 80  // candidates handed to Claude for the unthemed slate
	themeCandidatePoolSize = 120 // candidates handed to Claude for the themed collection
	themeMinPicks          = 6   // minimum coherent picks before we publish a theme
	recentLookbackDays     = 14  // "current-week" mode: bias toward recent uploads
	avoidThemesLookback    = 32  // when proposing a theme, avoid the last N created themes (covers ~half a year of weekly drops + any backfill churn so Claude sees the full slate at a glance)
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

	// "Backfill mode" = the operator pinned an explicit --week. In that
	// case we are stitching a slate for a past week, so we should NOT
	// bias toward recently-uploaded wallpapers (those didn't exist when
	// that historical week was live, conceptually). Current-week mode
	// keeps the recency boost so this Friday's drop reflects what users
	// have just been adding and engaging with.
	backfillMode := week > 0
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
	llmClient := llm.New(cfg.Anthropic.APIKey, repo.NewLLMUsageRepo(db))

	mode := "current-week (recency-boosted)"
	if backfillMode {
		mode = "backfill (all-time pool, no recency boost)"
	}
	fmt.Printf("==> Generating Weekly Drop for ISO %d-W%02d — mode: %s\n", year, week, mode)

	// ── PART 1: Weekly Picks — Claude picks 10 untheme'd wallpapers
	// balancing quality, popularity, and variety.
	pickCandidates := loadPickCandidates(ctx, db, weeklyRepo, pickCandidatePoolSize, backfillMode)
	fmt.Printf("Pick candidates: %d\n", len(pickCandidates))
	pickIDs := selectWeeklyPicks(ctx, llmClient, pickCandidates)
	fmt.Printf("Picks selected: %d wallpapers\n", len(pickIDs))
	for i, id := range pickIDs {
		fmt.Printf("  [%2d] id=%d\n", i+1, id)
	}

	// ── PART 2: Theme Collection.
	candidates := loadThemeCandidates(ctx, db, themeCandidatePoolSize, backfillMode)
	fmt.Printf("Theme candidates: %d\n", len(candidates))
	if len(candidates) < themeMinPicks {
		fmt.Println("not enough candidates for a theme; will skip theme generation")
	}

	avoidThemes := loadRecentThemeNames(ctx, db, avoidThemesLookback)
	if len(avoidThemes) > 0 {
		fmt.Printf("Avoiding recent themes: %v\n", avoidThemes)
	}

	var (
		pick        *llm.ThemePick
		themeWpIDs  []int64
	)
	if len(candidates) >= themeMinPicks {
		fmt.Println("Asking Claude for a coherent weekly theme...")
		pick, err = llmClient.ProposeWeeklyTheme(ctx, candidates, avoidThemes)
		if err != nil {
			log.Fatal("propose theme: ", err)
		}
		fmt.Printf("Theme: %q\n", pick.ThemeName)
		fmt.Printf("  %s\n", pick.Description)
		fmt.Printf("  Keywords: %v\n", pick.Keywords)
		if len(pick.Keywords) == 0 {
			fmt.Println("  (Claude returned empty keywords — skipping theme this week)")
			pick = nil
		} else {
			themeWpIDs = matchWallpapersByKeywords(ctx, db, pick.Keywords, weeklyPicksTarget)
			fmt.Printf("  Matched %d wallpapers in DB\n", len(themeWpIDs))
			if len(themeWpIDs) < themeMinPicks {
				fmt.Printf("  (theme rejected — only %d matched, need >= %d)\n", len(themeWpIDs), themeMinPicks)
				pick = nil
			}
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
	if pick != nil && len(themeWpIDs) >= themeMinPicks {
		// Upsert semantics: wipe any previous (year, week, kind=1)
		// collection before creating the new one. collection_wallpapers
		// has no ON DELETE CASCADE, so we clear the link table first.
		if err := db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			if err := tx.Exec(`
				DELETE FROM collection_wallpapers
				WHERE collection_id IN (
				    SELECT id FROM collections WHERE year = ? AND week = ? AND kind = 1
				)`, year, week).Error; err != nil {
				return err
			}
			return tx.Exec(`DELETE FROM collections WHERE year = ? AND week = ? AND kind = 1`,
				year, week).Error
		}); err != nil {
			log.Fatal("clear previous themed collection: ", err)
		}

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
		attached := 0
		for _, wpID := range themeWpIDs {
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
// selectWeeklyPicks hands the prepared candidate pool to Claude and
// returns the 10 IDs it chose, balancing quality, popularity, and
// variety. Empty pool → no picks (rather than failing loudly).
func selectWeeklyPicks(ctx context.Context, llmClient *llm.Client, candidates []llm.ThemeCandidate) []int64 {
	if len(candidates) == 0 {
		return nil
	}
	ids, err := llmClient.ProposeWeeklyPicks(ctx, candidates)
	if err != nil {
		log.Fatal("propose weekly picks: ", err)
	}
	if len(ids) > weeklyPicksTarget {
		ids = ids[:weeklyPicksTarget]
	}
	return ids
}

// loadPickCandidates returns the candidate pool for the unthemed slate.
// Excludes wallpapers that already appeared in any past week (so users
// see fresh content). In current-week mode it bounds to the recent
// window; in backfill mode it uses the unbounded historical pool.
func loadPickCandidates(ctx context.Context, db *gorm.DB, weeklyRepo *repo.WeeklyPickRepo, limit int, backfillMode bool) []llm.ThemeCandidate {
	excluded, err := weeklyRepo.AllPickedIDs(ctx)
	if err != nil {
		log.Fatal("load excluded: ", err)
	}
	excludedIDs := make([]int64, 0, len(excluded))
	for id := range excluded {
		excludedIDs = append(excludedIDs, id)
	}
	var since int64
	if !backfillMode {
		since = time.Now().UTC().AddDate(0, 0, -recentLookbackDays).Unix()
	}
	pool, err := weeklyRepo.CandidatePool(ctx, since, excludedIDs)
	if err != nil {
		log.Fatal("pick candidate pool: ", err)
	}
	if len(pool) > limit {
		pool = pool[:limit]
	}
	ids := make([]int64, len(pool))
	for i, c := range pool {
		ids[i] = c.ID
	}
	return hydrateCandidates(ctx, db, ids)
}

// loadThemeCandidates returns the candidate pool for the themed
// collection. The themed collection deliberately does NOT exclude
// previously-picked wallpapers (a wallpaper can star in a slate AND in
// a later theme — that's by design). Recency vs. all-time follows the
// same backfill switch as picks.
func loadThemeCandidates(ctx context.Context, db *gorm.DB, limit int, backfillMode bool) []llm.ThemeCandidate {
	type row struct {
		ID            int64
		CategoryID    int64
		Category      string
		Title         string
		Dominant      string
		LikeCount     int64
		DownloadCount int64
	}
	base := `
		SELECT w.id, w.category_id, COALESCE(c.slug, '') AS category,
		       w.title, w.dominant_color AS dominant,
		       w.like_count, w.download_count
		FROM wallpapers w
		LEFT JOIN categories c ON c.id = w.category_id
		WHERE w.status = 1 AND w.quality_flag = 'ok'`
	var rows []row
	if backfillMode {
		if err := db.WithContext(ctx).Raw(base+`
			ORDER BY (3.0 * w.like_count + 2.0 * w.download_count + 0.1 * w.view_count) DESC
			LIMIT ?`, limit).Scan(&rows).Error; err != nil {
			log.Fatal("load theme candidates (all-time): ", err)
		}
	} else {
		since := time.Now().UTC().AddDate(0, 0, -recentLookbackDays)
		if err := db.WithContext(ctx).Raw(base+` AND w.created_at >= ?
			ORDER BY (3.0 * w.like_count + 2.0 * w.download_count + 0.1 * w.view_count) DESC
			LIMIT ?`, since, limit).Scan(&rows).Error; err != nil {
			log.Fatal("load theme candidates (recent): ", err)
		}
	}
	ids := make([]int64, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	tagsByWp := loadTags(ctx, db, ids)

	out := make([]llm.ThemeCandidate, len(rows))
	for i, r := range rows {
		out[i] = llm.ThemeCandidate{
			ID:            r.ID,
			CategoryID:    r.CategoryID,
			Category:      r.Category,
			Tags:          tagsByWp[r.ID],
			Title:         strings.TrimSpace(r.Title),
			Dominant:      r.Dominant,
			LikeCount:     r.LikeCount,
			DownloadCount: r.DownloadCount,
		}
	}
	return out
}

// hydrateCandidates takes a list of wallpaper IDs in display order and
// fetches the per-row metadata Claude needs (category slug, title,
// dominant color, tags, engagement counts). Order is preserved from
// the input ids slice. Missing IDs are silently dropped.
func hydrateCandidates(ctx context.Context, db *gorm.DB, ids []int64) []llm.ThemeCandidate {
	if len(ids) == 0 {
		return nil
	}
	type row struct {
		ID            int64
		CategoryID    int64
		Category      string
		Title         string
		Dominant      string
		LikeCount     int64
		DownloadCount int64
	}
	var rows []row
	if err := db.WithContext(ctx).Raw(`
		SELECT w.id, w.category_id, COALESCE(c.slug, '') AS category,
		       w.title, w.dominant_color AS dominant,
		       w.like_count, w.download_count
		FROM wallpapers w
		LEFT JOIN categories c ON c.id = w.category_id
		WHERE w.id IN ?
	`, ids).Scan(&rows).Error; err != nil {
		log.Fatal("hydrate candidates: ", err)
	}
	tagsByWp := loadTags(ctx, db, ids)
	rowByID := make(map[int64]row, len(rows))
	for _, r := range rows {
		rowByID[r.ID] = r
	}
	out := make([]llm.ThemeCandidate, 0, len(ids))
	for _, id := range ids {
		r, ok := rowByID[id]
		if !ok {
			continue
		}
		out = append(out, llm.ThemeCandidate{
			ID:            r.ID,
			CategoryID:    r.CategoryID,
			Category:      r.Category,
			Tags:          tagsByWp[r.ID],
			Title:         strings.TrimSpace(r.Title),
			Dominant:      r.Dominant,
			LikeCount:     r.LikeCount,
			DownloadCount: r.DownloadCount,
		})
	}
	return out
}

// matchWallpapersByKeywords pulls up to `limit` wallpapers whose title,
// any tag, or category slug contains ANY of the given keywords (case-
// insensitive substring). The result is sorted by the same hot score
// used elsewhere so popular wallpapers float to the top. Used by the
// themed-collection picker — Claude proposes a theme + keywords, this
// function does the actual selection so we stop relying on the LLM to
// remember which IDs are in the catalog.
func matchWallpapersByKeywords(ctx context.Context, db *gorm.DB, keywords []string, limit int) []int64 {
	if len(keywords) == 0 {
		return nil
	}
	// Build a single Postgres regex alternation: "cat|kitten|feline".
	// Keywords are LLM-supplied lowercase short terms — no escaping of
	// regex metachars needed in practice (they'd be malformed input
	// anyway and the regex would just fail to match, not crash).
	pattern := strings.Join(keywords, "|")
	var ids []int64
	if err := db.WithContext(ctx).Raw(`
		SELECT w.id
		FROM wallpapers w
		LEFT JOIN categories c ON c.id = w.category_id
		WHERE w.status = 1
		  AND w.quality_flag = 'ok'
		  AND (
		      w.title ~* ?
		      OR (c.slug IS NOT NULL AND c.slug ~* ?)
		      OR EXISTS (
		          SELECT 1 FROM wallpaper_tags wt
		          JOIN tags t ON t.id = wt.tag_id
		          WHERE wt.wallpaper_id = w.id AND t.name ~* ?
		      )
		  )
		ORDER BY (3.0 * w.like_count + 2.0 * w.download_count + 0.1 * w.view_count) DESC,
		         w.created_at DESC
		LIMIT ?
	`, pattern, pattern, pattern, limit).Scan(&ids).Error; err != nil {
		log.Fatal("match wallpapers by keywords: ", err)
	}
	return ids
}

// loadRecentThemeNames returns the most recently CREATED themed-collection
// titles so the LLM can avoid repeating them. Ordering by created_at
// (not year/week) is deliberate: in backfill mode the operator might
// stitch together past weeks in any order, and what we want to avoid is
// editorial repetition across whatever the last few runs produced — not
// "the highest-week titles by calendar". The "Week NN · " prefix is
// stripped — Claude cares about the editorial angle, not the marker.
func loadRecentThemeNames(ctx context.Context, db *gorm.DB, limit int) []string {
	var titles []string
	if err := db.WithContext(ctx).Raw(`
		SELECT title FROM collections
		WHERE kind = 1
		ORDER BY created_at DESC
		LIMIT ?
	`, limit).Scan(&titles).Error; err != nil {
		return nil
	}
	out := make([]string, 0, len(titles))
	for _, t := range titles {
		if idx := strings.Index(t, " · "); idx > 0 && strings.HasPrefix(t, "Week ") {
			t = t[idx+len(" · "):]
		}
		if t = strings.TrimSpace(t); t != "" {
			out = append(out, t)
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
