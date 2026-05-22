package repo

import (
	"context"
	"errors"

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
// in a single call. It mirrors the shape of model.Wallpaper minus the
// owner-only OriginalURL — the public surface should never see that.
type WeeklyPicked struct {
	model.Wallpaper
	SortOrder int `json:"sort_order"`
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
		        w.thumb_url, w.preview_url, w.width, w.height, w.file_size, w.file_type,
		        w.dominant_color, w.color_palette, w.status, w.view_count, w.like_count,
		        w.download_count, w.favorite_count, w.is_dynamic, w.dynamic_type,
		        w.frame_urls, w.created_at, w.updated_at, wp.sort_order`).
		Joins("JOIN wallpapers w ON w.id = wp.wallpaper_id").
		Where("wp.year = ? AND wp.week = ? AND w.status = ?", year, week, model.WallpaperStatusPublished).
		Order("wp.sort_order ASC").
		Find(&rows).Error
	return rows, err
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
	Year     int16  `json:"year"`
	Week     int16  `json:"week"`
	Count    int    `json:"count"`
	CoverURL string `json:"cover_url"`
}

// Archive returns every past pick slate, newest first, paginated by
// limit. Used by the /weekly-picks page (the "past weeks" archive).
func (r *WeeklyPickRepo) Archive(ctx context.Context, limit int) ([]ArchiveEntry, error) {
	if limit <= 0 {
		limit = 50
	}
	var rows []ArchiveEntry
	err := r.db.WithContext(ctx).Raw(`
		SELECT wp.year, wp.week, slate.cnt AS count, COALESCE(w.thumb_url, w.preview_url, '') AS cover_url
		FROM (
		    SELECT year, week, COUNT(*) AS cnt
		    FROM weekly_picks
		    GROUP BY year, week
		) slate
		JOIN weekly_picks wp ON wp.year = slate.year AND wp.week = slate.week AND wp.sort_order = 0
		LEFT JOIN wallpapers w ON w.id = wp.wallpaper_id
		ORDER BY wp.year DESC, wp.week DESC
		LIMIT ?
	`, limit).Scan(&rows).Error
	return rows, err
}

// CandidatePool returns published wallpapers with quality_flag='ok',
// joined with their engagement counts, ordered by a weighted "hot
// score" — likes weigh more than downloads, downloads more than views.
// Optionally filter to wallpapers uploaded since `since`; when the
// recent pool is empty the picker calls again with a zero time to
// fall back to the historical pool.
type Candidate struct {
	ID       int64
	Score    float64
}

func (r *WeeklyPickRepo) CandidatePool(ctx context.Context, sinceUnix int64, excludeIDs []int64) ([]Candidate, error) {
	q := r.db.WithContext(ctx).
		Table("wallpapers").
		Select(`id,
		        (3.0 * like_count + 2.0 * download_count + 0.1 * view_count) AS score`).
		Where("status = ?", model.WallpaperStatusPublished).
		Where("quality_flag = ?", "ok").
		Order("score DESC, created_at DESC")
	if sinceUnix > 0 {
		q = q.Where("created_at >= to_timestamp(?)", sinceUnix)
	}
	if len(excludeIDs) > 0 {
		q = q.Where("id NOT IN ?", excludeIDs)
	}
	var rows []Candidate
	if err := q.Limit(200).Scan(&rows).Error; err != nil {
		return nil, err
	}
	return rows, nil
}

// IsNotFound is a tiny convenience so handler code doesn't have to
// import gorm just to check for the sentinel.
func IsNotFound(err error) bool { return errors.Is(err, gorm.ErrRecordNotFound) }
