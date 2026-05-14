package repo

import (
	"context"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

// AdminRepo holds cross-table aggregates used by the admin dashboard. Each
// query is one round-trip so a dashboard render fans out cheaply.
type AdminRepo struct {
	db *gorm.DB
}

func NewAdminRepo(db *gorm.DB) *AdminRepo {
	return &AdminRepo{db: db}
}

type OverviewStats struct {
	UserTotal         int64 `json:"user_total"`
	UserNewToday      int64 `json:"user_new_today"`
	UserNewLast7Days  int64 `json:"user_new_last_7_days"`
	UserAdmins        int64 `json:"user_admins"`
	WallpaperTotal    int64 `json:"wallpaper_total"`
	WallpaperPending  int64 `json:"wallpaper_pending"`
	WallpaperFailed   int64 `json:"wallpaper_failed"`
	WallpaperRemoved  int64 `json:"wallpaper_removed"`
	WallpaperDup      int64 `json:"wallpaper_duplicate"`
	WallpaperToday    int64 `json:"wallpaper_today"`
	CollectionTotal   int64 `json:"collection_total"`
	ReportOpen        int64 `json:"report_open"`
	ReportResolved    int64 `json:"report_resolved"`
	TotalViews        int64 `json:"total_views"`
	TotalLikes        int64 `json:"total_likes"`
	TotalFavorites    int64 `json:"total_favorites"`
	TotalDownloads    int64 `json:"total_downloads"`
	TotalCoinsCircled int64 `json:"total_coins_circled"`
}

func (r *AdminRepo) Overview(ctx context.Context) (*OverviewStats, error) {
	var s OverviewStats
	db := r.db.WithContext(ctx)

	// Users
	db.Model(&model.User{}).Where("id > 0").Count(&s.UserTotal)
	db.Model(&model.User{}).Where("id > 0 AND created_at >= NOW() - INTERVAL '1 day'").Count(&s.UserNewToday)
	db.Model(&model.User{}).Where("id > 0 AND created_at >= NOW() - INTERVAL '7 days'").Count(&s.UserNewLast7Days)
	db.Model(&model.User{}).Where("id > 0 AND is_admin = TRUE").Count(&s.UserAdmins)

	// Wallpapers by status
	db.Model(&model.Wallpaper{}).Where("status = ?", model.WallpaperStatusPublished).Count(&s.WallpaperTotal)
	db.Model(&model.Wallpaper{}).Where("status = ?", model.WallpaperStatusProcessing).Count(&s.WallpaperPending)
	db.Model(&model.Wallpaper{}).Where("status = ?", model.WallpaperStatusFailed).Count(&s.WallpaperFailed)
	db.Model(&model.Wallpaper{}).Where("status = ?", model.WallpaperStatusRemoved).Count(&s.WallpaperRemoved)
	db.Model(&model.Wallpaper{}).Where("status = ?", model.WallpaperStatusDuplicate).Count(&s.WallpaperDup)
	db.Model(&model.Wallpaper{}).Where("status = ? AND created_at >= NOW() - INTERVAL '1 day'", model.WallpaperStatusPublished).Count(&s.WallpaperToday)

	// Collections
	db.Model(&model.Collection{}).Count(&s.CollectionTotal)

	// Reports
	db.Model(&model.Report{}).Where("status = ?", model.ReportStatusOpen).Count(&s.ReportOpen)
	db.Model(&model.Report{}).Where("status = ?", model.ReportStatusResolved).Count(&s.ReportResolved)

	// Aggregate counters (only across published wallpapers — removed/failed shouldn't pad the dashboard)
	type sumRow struct {
		Views     int64
		Likes     int64
		Favorites int64
		Downloads int64
	}
	var sr sumRow
	db.Raw(`
		SELECT
			COALESCE(SUM(view_count), 0)     AS views,
			COALESCE(SUM(like_count), 0)     AS likes,
			COALESCE(SUM(favorite_count), 0) AS favorites,
			COALESCE(SUM(download_count), 0) AS downloads
		FROM wallpapers WHERE status = ?
	`, model.WallpaperStatusPublished).Scan(&sr)
	s.TotalViews = sr.Views
	s.TotalLikes = sr.Likes
	s.TotalFavorites = sr.Favorites
	s.TotalDownloads = sr.Downloads

	// Coin pool excluding the system user
	db.Model(&model.User{}).Where("id > 0").Select("COALESCE(SUM(coins), 0)").Scan(&s.TotalCoinsCircled)

	return &s, nil
}

type DailyPoint struct {
	Day   string `json:"day"`
	Count int64  `json:"count"`
}

// DailySeries returns the last N days of counts for the given fact: "users",
// "wallpapers", "downloads", "views". Backfilled with zeros for gaps so the
// frontend chart draws a smooth line.
func (r *AdminRepo) DailySeries(ctx context.Context, fact string, days int) ([]DailyPoint, error) {
	if days <= 0 || days > 90 {
		days = 30
	}
	var sql string
	switch fact {
	case "users":
		sql = `
			SELECT TO_CHAR(d, 'YYYY-MM-DD') AS day, COALESCE(c.cnt, 0) AS count
			FROM generate_series(NOW()::date - INTERVAL '` + intervalDays(days) + `', NOW()::date, '1 day') d
			LEFT JOIN (
				SELECT created_at::date AS day, COUNT(*)::bigint AS cnt
				FROM users WHERE id > 0 AND created_at >= NOW()::date - INTERVAL '` + intervalDays(days) + `'
				GROUP BY created_at::date
			) c ON c.day = d
			ORDER BY day
		`
	case "wallpapers":
		sql = `
			SELECT TO_CHAR(d, 'YYYY-MM-DD') AS day, COALESCE(c.cnt, 0) AS count
			FROM generate_series(NOW()::date - INTERVAL '` + intervalDays(days) + `', NOW()::date, '1 day') d
			LEFT JOIN (
				SELECT created_at::date AS day, COUNT(*)::bigint AS cnt
				FROM wallpapers
				WHERE status = 1 AND created_at >= NOW()::date - INTERVAL '` + intervalDays(days) + `'
				GROUP BY created_at::date
			) c ON c.day = d
			ORDER BY day
		`
	case "events":
		sql = `
			SELECT TO_CHAR(d, 'YYYY-MM-DD') AS day, COALESCE(c.cnt, 0) AS count
			FROM generate_series(NOW()::date - INTERVAL '` + intervalDays(days) + `', NOW()::date, '1 day') d
			LEFT JOIN (
				SELECT created_at::date AS day, COUNT(*)::bigint AS cnt
				FROM analytics_events
				WHERE created_at >= NOW()::date - INTERVAL '` + intervalDays(days) + `'
				GROUP BY created_at::date
			) c ON c.day = d
			ORDER BY day
		`
	default:
		return []DailyPoint{}, nil
	}

	var pts []DailyPoint
	err := r.db.WithContext(ctx).Raw(sql).Scan(&pts).Error
	return pts, err
}

func intervalDays(n int) string {
	if n < 1 {
		n = 1
	}
	return formatInt(n) + " days"
}

func formatInt(n int) string {
	// avoid strconv import — kept tiny because intervalDays is the only caller
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

// TopWallpaper holds a thin row for the dashboard "top by views/likes" lists.
type TopWallpaper struct {
	ID            int64  `json:"id"`
	Slug          string `json:"slug"`
	Title         string `json:"title"`
	ThumbURL      string `json:"thumb_url"`
	ViewCount     int64  `json:"view_count"`
	LikeCount     int64  `json:"like_count"`
	DownloadCount int64  `json:"download_count"`
}

func (r *AdminRepo) TopWallpapers(ctx context.Context, by string, limit int) ([]TopWallpaper, error) {
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	order := "view_count DESC"
	switch by {
	case "likes":
		order = "like_count DESC"
	case "downloads":
		order = "download_count DESC"
	case "favorites":
		order = "favorite_count DESC"
	}
	var rows []TopWallpaper
	err := r.db.WithContext(ctx).Raw(`
		SELECT id, slug, title, thumb_url, view_count, like_count, download_count
		  FROM wallpapers
		 WHERE status = 1
		 ORDER BY `+order+`, id DESC
		 LIMIT ?
	`, limit).Scan(&rows).Error
	return rows, err
}

func (r *AdminRepo) CategoryDistribution(ctx context.Context) ([]CategoryCount, error) {
	type row struct {
		CategoryID int64
		Name       string
		Cnt        int64
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT w.category_id, COALESCE(c.name, '(uncategorized)') AS name, COUNT(*)::bigint AS cnt
		  FROM wallpapers w
		  LEFT JOIN categories c ON c.id = w.category_id
		 WHERE w.status = 1
		 GROUP BY w.category_id, c.name
		 ORDER BY cnt DESC
	`).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	out := make([]CategoryCount, len(rows))
	for i, r := range rows {
		out[i] = CategoryCount{CategoryID: r.CategoryID, Name: r.Name, Count: r.Cnt}
	}
	return out, nil
}

type CategoryCount struct {
	CategoryID int64  `json:"category_id"`
	Name       string `json:"name"`
	Count      int64  `json:"count"`
}

// touchSilencer pins the time import in case other helpers above are removed.
var _ = time.Time{}
