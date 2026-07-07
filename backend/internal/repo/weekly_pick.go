package repo

import (
	"context"
	"errors"
	"strings"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type WeeklyPickRepo struct {
	db *gorm.DB
}

func NewWeeklyPickRepo(db *gorm.DB) *WeeklyPickRepo {
	return &WeeklyPickRepo{db: db}
}

// WeeklyPicked is one row of a Weekly Picks slate, joined with the
// wallpaper itself so the API can return everything the gallery needs
// in a single call. OriginalURL is populated ONLY on the hero row
// (IsHero=true, or sort_order=0 as fallback when no hero is set) —
// the home page needs the original for the hero card's full-res
// display, but all other picks return original_url="" so the public
// surface still gates full-resolution downloads behind the coin
// economy. The unbounded /wallpapers list endpoint still strips it.
type WeeklyPicked struct {
	model.Wallpaper
	SortOrder int  `json:"sort_order"`
	IsHero    bool `json:"is_hero"`
}

// Insert writes the 10-row slate for one ISO week. If a slate already
// exists for (year, week) it's wiped first so re-runs are idempotent;
// the picker's "never show a wallpaper twice" guarantee is enforced by
// IsAlreadyPicked, not by uniqueness in the picks table itself.
func (r *WeeklyPickRepo) Insert(ctx context.Context, year, week int16, wallpaperIDs []int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("year = ? AND week = ?", year, week).Delete(&model.WeeklyPick{}).Error; err != nil {
			return err
		}
		rows := make([]model.WeeklyPick, len(wallpaperIDs))
		for i, id := range wallpaperIDs {
			rows[i] = model.WeeklyPick{
				Year:        year,
				Week:        week,
				WallpaperID: id,
				SortOrder:   i,
				// First pick (sort_order=0) starts as the hero so the home
				// page always has one. Admin can change via SetHero.
				IsHero: i == 0,
			}
		}
		if len(rows) == 0 {
			return nil
		}
		return tx.Create(&rows).Error
	})
}

// AllPickedIDs returns every wallpaper id that has appeared in any pick
// slate to date. Used by the picker to exclude historical features —
// "once featured, never featured again" — so users see fresh content
// each week.
func (r *WeeklyPickRepo) AllPickedIDs(ctx context.Context) (map[int64]bool, error) {
	var ids []int64
	if err := r.db.WithContext(ctx).
		Model(&model.WeeklyPick{}).
		Distinct("wallpaper_id").
		Pluck("wallpaper_id", &ids).Error; err != nil {
		return nil, err
	}
	out := make(map[int64]bool, len(ids))
	for _, id := range ids {
		out[id] = true
	}
	return out, nil
}

// ListByWeek returns the 10 wallpapers picked for a specific ISO week,
// joined with the wallpaper rows themselves in pick order. Missing weeks
// return an empty slice — the handler is responsible for 404-ing.
func (r *WeeklyPickRepo) ListByWeek(ctx context.Context, year, week int16) ([]WeeklyPicked, error) {
	var rows []WeeklyPicked
	err := r.db.WithContext(ctx).
		Table("weekly_picks AS wp").
		Select(`w.id, w.slug, w.user_id, w.category_id, w.title, w.description,
		        w.original_url, w.thumb_url, w.preview_url, w.preview_video_url, w.width, w.height,
		        w.file_size, w.file_type, w.dominant_color, w.color_palette,
		        w.status, w.view_count, w.like_count, w.download_count,
		        w.favorite_count, w.is_dynamic, w.dynamic_type, w.frame_urls,
		        w.created_at, w.updated_at, wp.sort_order, wp.is_hero`).
		Joins("JOIN wallpapers w ON w.id = wp.wallpaper_id").
		Where("wp.year = ? AND wp.week = ? AND w.status = ?", year, week, model.WallpaperStatusPublished).
		Order("wp.sort_order ASC").
		Find(&rows).Error
	if err != nil {
		return nil, err
	}
	// Strip OriginalURL from every row except the hero. If no row has
	// IsHero=true (legacy weeks predating this column), fall back to
	// sort_order=0 — same wallpaper the picker has historically treated
	// as #1 — so existing slates keep working without an explicit
	// migration touchup.
	heroIdx := -1
	for i, r := range rows {
		if r.IsHero {
			heroIdx = i
			break
		}
	}
	if heroIdx == -1 && len(rows) > 0 {
		heroIdx = 0
		rows[0].IsHero = true // legacy default: first pick = hero
	}
	for i := range rows {
		if i != heroIdx {
			rows[i].OriginalURL = ""
		}
	}
	return rows, nil
}

// SetHero flips the hero flag for one wallpaper in (year, week), clearing
// all others in the same week. Runs in a transaction so the partial
// unique index can never see two TRUE rows at once.
func (r *WeeklyPickRepo) SetHero(ctx context.Context, year, week int16, wallpaperID int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&model.WeeklyPick{}).
			Where("year = ? AND week = ? AND is_hero = ?", year, week, true).
			Update("is_hero", false).Error; err != nil {
			return err
		}
		res := tx.Model(&model.WeeklyPick{}).
			Where("year = ? AND week = ? AND wallpaper_id = ?", year, week, wallpaperID).
			Update("is_hero", true)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return gorm.ErrRecordNotFound
		}
		return nil
	})
}

// AddPick appends a single wallpaper to a week's slate at sort_order =
// max+1, with is_hero=false (since the slate must already have a hero —
// admin can promote later with SetHero). Returns ErrAlreadyPicked if the
// wallpaper is already in that week's slate (the UNIQUE (year, week,
// wallpaper_id) constraint).
var ErrAlreadyPicked = errors.New("wallpaper is already in this week's slate")

func (r *WeeklyPickRepo) AddPick(ctx context.Context, year, week int16, wallpaperID int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var maxOrder *int
		if err := tx.Model(&model.WeeklyPick{}).
			Select("MAX(sort_order)").
			Where("year = ? AND week = ?", year, week).
			Row().Scan(&maxOrder); err != nil {
			return err
		}
		next := 0
		if maxOrder != nil {
			next = *maxOrder + 1
		}
		row := model.WeeklyPick{
			Year:        year,
			Week:        week,
			WallpaperID: wallpaperID,
			SortOrder:   next,
			IsHero:      next == 0,
		}
		if err := tx.Create(&row).Error; err != nil {
			// Duplicate (year, week, wallpaper_id) → friendly error.
			if strings.Contains(err.Error(), "duplicate") || strings.Contains(err.Error(), "unique") {
				return ErrAlreadyPicked
			}
			return err
		}
		return nil
	})
}

// RemovePick deletes a single (year, week, wallpaper_id) row. If the
// removed pick was the hero, promotes the next-lowest sort_order in the
// same week to is_hero=true so the slate always has exactly one hero
// (and the public surface never loses its full-res home image).
func (r *WeeklyPickRepo) RemovePick(ctx context.Context, year, week int16, wallpaperID int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var deleting model.WeeklyPick
		if err := tx.Where("year = ? AND week = ? AND wallpaper_id = ?", year, week, wallpaperID).
			First(&deleting).Error; err != nil {
			return err
		}
		if err := tx.Delete(&deleting).Error; err != nil {
			return err
		}
		if !deleting.IsHero {
			return nil
		}
		// We deleted the hero; promote the lowest remaining sort_order.
		var next model.WeeklyPick
		err := tx.Where("year = ? AND week = ?", year, week).
			Order("sort_order ASC").First(&next).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Week is now empty — nothing to promote, that's fine.
			return nil
		}
		if err != nil {
			return err
		}
		return tx.Model(&next).Update("is_hero", true).Error
	})
}

// DeleteWeek removes an entire (year, week) slate. Returns
// gorm.ErrRecordNotFound if the week has no picks so the handler can
// answer 404 instead of a silent no-op. Deleting a week also frees its
// wallpapers for future slates (AllPickedIDs no longer sees them).
func (r *WeeklyPickRepo) DeleteWeek(ctx context.Context, year, week int16) error {
	res := r.db.WithContext(ctx).
		Where("year = ? AND week = ?", year, week).
		Delete(&model.WeeklyPick{})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return gorm.ErrRecordNotFound
	}
	return nil
}

// WeekSummary is one entry in the admin weekly-picks index — a single
// (year, week) row enriched with how many picks were curated and which
// wallpaper is the hero, so the admin list can render cover thumbnails
// without a per-row second fetch.
type WeekSummary struct {
	Year      int16  `json:"year"`
	Week      int16  `json:"week"`
	Count     int    `json:"count"`
	HeroThumb string `json:"hero_thumb"`
	HeroTitle string `json:"hero_title"`
	HeroWPID  int64  `json:"hero_wallpaper_id"`
}

// ListAllWeeks returns every week that has a picks slate, newest first,
// with hero info attached. Used by the admin console.
func (r *WeeklyPickRepo) ListAllWeeks(ctx context.Context) ([]WeekSummary, error) {
	// Build a per-week summary in one round-trip. We need two pieces
	// from each week's hero row (thumb_url, title) and the count of
	// picks, so a CTE keeps the SQL readable.
	type row struct {
		Year      int16
		Week      int16
		Count     int
		HeroThumb string
		HeroTitle string
		HeroWPID  int64
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		WITH counts AS (
		    SELECT year, week, COUNT(*) AS c FROM weekly_picks GROUP BY year, week
		),
		heroes AS (
		    SELECT wp.year, wp.week, wp.wallpaper_id, w.thumb_url, w.title
		    FROM weekly_picks wp
		    JOIN wallpapers w ON w.id = wp.wallpaper_id
		    WHERE wp.is_hero = TRUE
		),
		first_pick AS (
		    SELECT DISTINCT ON (wp.year, wp.week)
		           wp.year, wp.week, wp.wallpaper_id, w.thumb_url, w.title
		    FROM weekly_picks wp
		    JOIN wallpapers w ON w.id = wp.wallpaper_id
		    ORDER BY wp.year, wp.week, wp.sort_order ASC
		)
		SELECT c.year, c.week, c.c AS count,
		       COALESCE(h.thumb_url, fp.thumb_url) AS hero_thumb,
		       COALESCE(h.title,     fp.title)     AS hero_title,
		       COALESCE(h.wallpaper_id, fp.wallpaper_id) AS hero_wp_id
		FROM counts c
		LEFT JOIN heroes     h  ON h.year  = c.year AND h.week  = c.week
		LEFT JOIN first_pick fp ON fp.year = c.year AND fp.week = c.week
		ORDER BY c.year DESC, c.week DESC
	`).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	out := make([]WeekSummary, len(rows))
	for i, r := range rows {
		out[i] = WeekSummary{
			Year: r.Year, Week: r.Week, Count: r.Count,
			HeroThumb: r.HeroThumb, HeroTitle: r.HeroTitle, HeroWPID: r.HeroWPID,
		}
	}
	return out, nil
}

// LatestWeek returns the most recent (year, week) for which a slate
// exists. Returns (0, 0, ErrRecordNotFound) when no picks have been
// generated yet — the handler turns that into an empty payload so the
// Home page renders gracefully on day one.
func (r *WeeklyPickRepo) LatestWeek(ctx context.Context) (int16, int16, error) {
	var row struct {
		Year int16
		Week int16
	}
	err := r.db.WithContext(ctx).
		Model(&model.WeeklyPick{}).
		Select("year, week").
		Order("year DESC, week DESC").
		Limit(1).
		Scan(&row).Error
	if err != nil {
		return 0, 0, err
	}
	if row.Year == 0 {
		return 0, 0, gorm.ErrRecordNotFound
	}
	return row.Year, row.Week, nil
}

// ArchiveEntry is one row of the "all past weeks" index. The cover_url
// is the thumb (≈400×300) of whichever pick was sort_order=0 in that
// week — thumbnail-sized is intentional, archive cards render ≤280px
// wide so preview_url would just waste bandwidth.
type ArchiveEntry struct {
	Year        int16  `json:"year"`
	Week        int16  `json:"week"`
	Count       int    `json:"count"`
	CoverURL    string `json:"cover_url"`
	OriginalURL string `json:"original_url,omitempty"`
	AccentColor string `json:"accent_color,omitempty"`
	// Cover wallpaper's extracted palette + dominant colour. The
	// SPA archive page sets these on its root as --w-c1/c2/c3 when
	// the user picks an issue from the timeline so the page-mesh
	// tracks the selected week's colour signature, same pattern as
	// WeeklyWeekPage. Omit when missing (no extracted palette).
	DominantColor string `json:"dominant_color,omitempty"`
	ColorPalette  string `json:"color_palette,omitempty"`
}

// Archive returns every past pick slate, newest first, paginated by
// limit. Used by the /weekly-picks page (the "past weeks" archive).
func (r *WeeklyPickRepo) Archive(ctx context.Context, limit int) ([]ArchiveEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	var rows []ArchiveEntry
	// Join the matching themed collection so each archive entry can
	// surface the LLM-chosen accent color alongside its cover. Themed
	// collections share the (year, week) key with weekly_picks; left
	// join keeps weeks without a theme working.
	// Cover selection per slate:
	//   - Prefer the admin-marked hero (is_hero = TRUE) — that's the
	//     piece the curator wanted on the cover.
	//   - If the hero wallpaper has been unpublished since, fall
	//     through to the next published row by sort_order ASC.
	//   - Only published wallpapers are eligible (status filter on
	//     the wallpapers JOIN).
	// DISTINCT ON + the ORDER BY 'is_hero DESC, sort_order ASC' inner
	// keys do that selection in one query. The archive endpoint
	// returns just one row per (year, week) and the SPA list page
	// renders the cover_url directly — no follow-up byWeek fetch,
	// no progressive upgrade, no chance of swap.
	err := r.db.WithContext(ctx).Raw(`
		SELECT DISTINCT ON (slate.year, slate.week)
		       slate.year, slate.week, slate.cnt AS count,
		       COALESCE(w.preview_url, w.thumb_url, '') AS cover_url,
		       COALESCE(w.original_url, '') AS original_url,
		       COALESCE(tc.accent_color, '') AS accent_color,
		       COALESCE(w.dominant_color, '') AS dominant_color,
		       COALESCE(w.color_palette, '') AS color_palette
		FROM (
		    SELECT year, week, COUNT(*) AS cnt
		    FROM weekly_picks
		    GROUP BY year, week
		) slate
		JOIN weekly_picks wp ON wp.year = slate.year AND wp.week = slate.week
		JOIN wallpapers w ON w.id = wp.wallpaper_id AND w.status = ?
		LEFT JOIN collections tc ON tc.kind = 1 AND tc.year = slate.year AND tc.week = slate.week
		ORDER BY slate.year DESC, slate.week DESC, wp.is_hero DESC, wp.sort_order ASC
		LIMIT ?
	`, model.WallpaperStatusPublished, limit).Scan(&rows).Error
	return rows, err
}

// IsNotFound is a tiny convenience so handler code doesn't have to
// import gorm just to check for the sentinel.
func IsNotFound(err error) bool { return errors.Is(err, gorm.ErrRecordNotFound) }
