package repo

import (
	"context"
	"strings"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type AnalyticsRepo struct {
	db *gorm.DB
}

func NewAnalyticsRepo(db *gorm.DB) *AnalyticsRepo {
	return &AnalyticsRepo{db: db}
}

func (r *AnalyticsRepo) Create(ctx context.Context, e *model.AnalyticsEvent) error {
	return r.db.WithContext(ctx).Create(e).Error
}

// botUAClause excludes obvious crawlers/scrapers from aggregations.
// We mostly rely on real-user JS firing the track endpoint (bots without
// JS never enter the table), but headless Chrome scrapers occasionally
// do, so the query-time filter is a belt-and-braces measure. Postgres
// ILIKE matches case-insensitively.
const botUAClause = `user_agent !~* '(bot|spider|crawler|scrape|preview|monitor|headless|lighthouse|fetch|sitechecker|chatgpt|claude|gpt|llm|curl|wget|httpclient|python|go-http|java/)'`

// DayBucket is one row of the per-day aggregation. Day is in UTC and
// truncated to the day boundary.
type DayBucket struct {
	Day       time.Time `gorm:"column:day" json:"day"`
	PageViews int64     `gorm:"column:page_views" json:"page_views"`
	Sessions  int64     `gorm:"column:sessions" json:"sessions"`
	UniqueIPs int64     `gorm:"column:unique_ips" json:"unique_ips"`
}

// DailyTimeseries returns one row per UTC day for the given window,
// including days with zero events (generated_series fills the gaps).
func (r *AnalyticsRepo) DailyTimeseries(ctx context.Context, days int) ([]DayBucket, error) {
	if days <= 0 {
		days = 7
	}
	if days > 90 {
		days = 90
	}
	since := time.Now().UTC().AddDate(0, 0, -days+1).Truncate(24 * time.Hour)

	rows := []DayBucket{}
	err := r.db.WithContext(ctx).Raw(`
		WITH days AS (
			SELECT generate_series(?::date, CURRENT_DATE, '1 day'::interval)::date AS day
		)
		SELECT
			d.day AS day,
			COALESCE(COUNT(e.id), 0)                    AS page_views,
			COALESCE(COUNT(DISTINCT e.session_id), 0)   AS sessions,
			COALESCE(COUNT(DISTINCT e.ip), 0)           AS unique_ips
		FROM days d
		LEFT JOIN analytics_events e
		  ON date_trunc('day', e.created_at)::date = d.day
		 AND e.event_type = 'page_view'
		 AND `+botUAClause+`
		GROUP BY d.day
		ORDER BY d.day ASC
	`, since).Scan(&rows).Error
	return rows, err
}

// Totals returns aggregate metrics over the window. Used for the
// dashboard KPI tiles and for delta-vs-previous-period comparisons.
type Totals struct {
	PageViews int64 `gorm:"column:page_views" json:"page_views"`
	Sessions  int64 `gorm:"column:sessions" json:"sessions"`
	UniqueIPs int64 `gorm:"column:unique_ips" json:"unique_ips"`
}

func (r *AnalyticsRepo) Totals(ctx context.Context, from, to time.Time) (Totals, error) {
	var t Totals
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			COUNT(*)                  AS page_views,
			COUNT(DISTINCT session_id) AS sessions,
			COUNT(DISTINCT ip)         AS unique_ips
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ? AND created_at < ?
		  AND `+botUAClause+`
	`, from, to).Scan(&t).Error
	return t, err
}

// LabelCount is one row of any (key, count) Top-N breakdown.
type LabelCount struct {
	Label string `gorm:"column:label" json:"label"`
	Count int64  `gorm:"column:count" json:"count"`
}

// TopCountries returns the most common country codes over the window.
// Rows with empty country (events stored before CF-IPCountry was wired
// up) are excluded so they don't dominate the top-of-list with junk.
func (r *AnalyticsRepo) TopCountries(ctx context.Context, days, limit int) ([]LabelCount, error) {
	since := time.Now().UTC().AddDate(0, 0, -days)
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT country AS label, COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ?
		  AND country <> ''
		  AND `+botUAClause+`
		GROUP BY country
		ORDER BY count DESC
		LIMIT ?
	`, since, limit).Scan(&rows).Error
	return rows, err
}

// TopPaths returns the most viewed paths. Useful for spotting which
// landing pages a promotion campaign actually drives traffic to.
func (r *AnalyticsRepo) TopPaths(ctx context.Context, days, limit int) ([]LabelCount, error) {
	since := time.Now().UTC().AddDate(0, 0, -days)
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT path AS label, COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ?
		  AND path <> ''
		  AND `+botUAClause+`
		GROUP BY path
		ORDER BY count DESC
		LIMIT ?
	`, since, limit).Scan(&rows).Error
	return rows, err
}

// ClientDownloads counts official website clicks for Mac / Android
// client packages. New events write target_client; the fallback keeps
// old or ad-hoc events grouped if they used client directly.
func (r *AnalyticsRepo) ClientDownloads(ctx context.Context, days, limit int) ([]LabelCount, error) {
	since := time.Now().UTC().AddDate(0, 0, -days)
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			COALESCE(
				NULLIF(lower(props->>'target_client'), ''),
				NULLIF(lower(props->>'client'), ''),
				'unknown'
			) AS label,
			COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'client_download'
		  AND created_at >= ?
		  AND `+botUAClause+`
		GROUP BY label
		ORDER BY count DESC
		LIMIT ?
	`, since, limit).Scan(&rows).Error
	return rows, err
}

// ClientBreakdown groups analytics events by the client that emitted
// them. Web events now set props.client explicitly; native clients can
// reuse the same /events endpoint with mac/android/ios/windows later.
func (r *AnalyticsRepo) ClientBreakdown(ctx context.Context, days, limit int) ([]LabelCount, error) {
	since := time.Now().UTC().AddDate(0, 0, -days)
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT label, COUNT(*) AS count
		FROM (
			SELECT
				CASE
					WHEN lower(props->>'client') IN ('web', 'mac', 'android', 'ios', 'windows') THEN lower(props->>'client')
					WHEN user_agent ~* 'WallpaperExchange/(mac|android|ios|windows)' THEN lower(substring(user_agent from 'WallpaperExchange/([A-Za-z]+)'))
					ELSE 'web'
				END AS label
			FROM analytics_events
			WHERE created_at >= ?
			  AND `+botUAClause+`
		) e
		GROUP BY label
		ORDER BY count DESC
		LIMIT ?
	`, since, limit).Scan(&rows).Error
	return rows, err
}

// ReferrerRow is the raw referrer host + count, before classification.
// The handler layer maps these hosts to a friendly source name
// ("Google", "Pinterest", ...) so the repo doesn't need to know about
// promotional channels.
type ReferrerRow struct {
	Host  string `gorm:"column:host" json:"host"`
	Count int64  `gorm:"column:count" json:"count"`
}

// TopReferrerHosts returns the most common referrer hostnames over the
// window. Empty referrers are bucketed separately as "" so the caller
// can label them "Direct"; same-site referrers are filtered out.
func (r *AnalyticsRepo) TopReferrerHosts(ctx context.Context, days, limit int, ownHosts []string) ([]ReferrerRow, error) {
	since := time.Now().UTC().AddDate(0, 0, -days)
	if limit <= 0 {
		limit = 20
	}
	if len(ownHosts) == 0 {
		ownHosts = []string{""}
	}

	// GORM Raw does NOT expand slices into IN lists — the query-builder
	// DSL does, but Raw treats every `?` as exactly one parameter. Build
	// the `?, ?, ?` placeholder list by hand and bind one arg per host.
	placeholders := strings.TrimRight(strings.Repeat("?,", len(ownHosts)), ",")
	args := []any{since}
	for _, h := range ownHosts {
		args = append(args, h)
	}
	args = append(args, limit)

	rows := []ReferrerRow{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT
			COALESCE(
				NULLIF(split_part(split_part(referrer, '//', 2), '/', 1), ''),
				''
			) AS host,
			COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ?
		  AND `+botUAClause+`
		GROUP BY host
		HAVING COALESCE(NULLIF(split_part(split_part(referrer, '//', 2), '/', 1), ''), '') NOT IN (`+placeholders+`)
		ORDER BY count DESC
		LIMIT ?
	`, args...).Scan(&rows).Error
	return rows, err
}
