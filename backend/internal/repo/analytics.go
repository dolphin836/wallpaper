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

func (r *AnalyticsRepo) CreateBatch(ctx context.Context, events []model.AnalyticsEvent) error {
	if len(events) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).CreateInBatches(events, 100).Error
}

func (r *AnalyticsRepo) DeleteAPIRequestsBefore(ctx context.Context, cutoff time.Time) (int64, error) {
	result := r.db.WithContext(ctx).
		Where("event_type = ? AND created_at < ?", "api_request", cutoff).
		Delete(&model.AnalyticsEvent{})
	return result.RowsAffected, result.Error
}

// botUAClause excludes obvious crawlers/scrapers from aggregations.
// We mostly rely on real-user JS firing the track endpoint (bots without
// JS never enter the table), but headless Chrome scrapers occasionally
// do, so the query-time filter is a belt-and-braces measure. Postgres
// ILIKE matches case-insensitively.
const botUAClause = `user_agent !~* '(bot|spider|crawler|scrape|preview|monitor|headless|lighthouse|fetch|sitechecker|chatgpt|claude|gpt|llm|curl|wget|httpclient|python|go-http|java/)'`

// DayBucket is one row of the per-day aggregation. Day is a calendar date in
// the admin-selected timezone.
type DayBucket struct {
	Day             time.Time `gorm:"column:day" json:"day"`
	PageViews       int64     `gorm:"column:page_views" json:"page_views"`
	Sessions        int64     `gorm:"column:sessions" json:"sessions"`
	UniqueIPs       int64     `gorm:"column:unique_ips" json:"unique_ips"`
	WallpaperViews  int64     `gorm:"column:wallpaper_views" json:"wallpaper_views"`
	APIRequests     int64     `gorm:"column:api_requests" json:"api_requests"`
	APIErrors       int64     `gorm:"column:api_errors" json:"api_errors"`
	AvgAPILatencyMS int64     `gorm:"column:avg_api_latency_ms" json:"avg_api_latency_ms"`
	P95APILatencyMS int64     `gorm:"column:p95_api_latency_ms" json:"p95_api_latency_ms"`
}

// DailyTimeseries returns one row per calendar day in timezone. Page views,
// wallpaper detail views, and API requests remain separate because each has a
// different product meaning and collection path.
func (r *AnalyticsRepo) DailyTimeseries(ctx context.Context, from, to time.Time, timezone string) ([]DayBucket, error) {
	location, err := time.LoadLocation(timezone)
	if err != nil {
		location = time.UTC
		timezone = "UTC"
	}
	startDay := from.In(location).Format("2006-01-02")
	endDay := to.Add(-time.Nanosecond).In(location).Format("2006-01-02")
	rows := []DayBucket{}
	err = r.db.WithContext(ctx).Raw(`
		WITH days AS (
			SELECT generate_series(?::date, ?::date, '1 day'::interval)::date AS day
		), page AS (
			SELECT
				timezone(?, created_at)::date AS day,
				COUNT(*) AS page_views,
				COUNT(DISTINCT NULLIF(session_id, '')) AS sessions,
				COUNT(DISTINCT NULLIF(ip, '')) AS unique_ips
			FROM analytics_events
			WHERE event_type = 'page_view'
			  AND created_at >= ? AND created_at < ?
			  AND `+botUAClause+`
			GROUP BY day
		), wallpaper AS (
			SELECT timezone(?, created_at)::date AS day, COUNT(*) AS wallpaper_views
			FROM wallpaper_events
			WHERE event_type = 'view'
			  AND created_at >= ? AND created_at < ?
			GROUP BY day
		), api AS (
			SELECT
				timezone(?, created_at)::date AS day,
				COUNT(*) AS api_requests,
				COUNT(*) FILTER (WHERE COALESCE((props->>'status')::int, 0) >= 400) AS api_errors,
				ROUND(COALESCE(AVG((props->>'duration_ms')::bigint), 0))::bigint AS avg_api_latency_ms,
				ROUND(COALESCE(percentile_cont(0.95) WITHIN GROUP (ORDER BY (props->>'duration_ms')::bigint), 0))::bigint AS p95_api_latency_ms
			FROM analytics_events
			WHERE event_type = 'api_request'
			  AND created_at >= ? AND created_at < ?
			GROUP BY day
		)
		SELECT
			d.day AS day,
			COALESCE(page.page_views, 0) AS page_views,
			COALESCE(page.sessions, 0) AS sessions,
			COALESCE(page.unique_ips, 0) AS unique_ips,
			COALESCE(wallpaper.wallpaper_views, 0) AS wallpaper_views,
			COALESCE(api.api_requests, 0) AS api_requests,
			COALESCE(api.api_errors, 0) AS api_errors,
			COALESCE(api.avg_api_latency_ms, 0) AS avg_api_latency_ms,
			COALESCE(api.p95_api_latency_ms, 0) AS p95_api_latency_ms
		FROM days d
		LEFT JOIN page ON page.day = d.day
		LEFT JOIN wallpaper ON wallpaper.day = d.day
		LEFT JOIN api ON api.day = d.day
		ORDER BY d.day ASC
	`, startDay, endDay,
		timezone, from, to,
		timezone, from, to,
		timezone, from, to,
	).Scan(&rows).Error
	return rows, err
}

// Totals returns aggregate metrics over the window. Used for the
// dashboard KPI tiles and for delta-vs-previous-period comparisons.
type Totals struct {
	PageViews       int64 `gorm:"column:page_views" json:"page_views"`
	Sessions        int64 `gorm:"column:sessions" json:"sessions"`
	UniqueIPs       int64 `gorm:"column:unique_ips" json:"unique_ips"`
	WallpaperViews  int64 `gorm:"column:wallpaper_views" json:"wallpaper_views"`
	APIRequests     int64 `gorm:"column:api_requests" json:"api_requests"`
	APIErrors       int64 `gorm:"column:api_errors" json:"api_errors"`
	AvgAPILatencyMS int64 `gorm:"column:avg_api_latency_ms" json:"avg_api_latency_ms"`
	P95APILatencyMS int64 `gorm:"column:p95_api_latency_ms" json:"p95_api_latency_ms"`
}

func (r *AnalyticsRepo) Totals(ctx context.Context, from, to time.Time) (Totals, error) {
	var t Totals
	err := r.db.WithContext(ctx).Raw(`
		WITH page AS (
			SELECT
				COUNT(*) AS page_views,
				COUNT(DISTINCT NULLIF(session_id, '')) AS sessions,
				COUNT(DISTINCT NULLIF(ip, '')) AS unique_ips
			FROM analytics_events
			WHERE event_type = 'page_view'
			  AND created_at >= ? AND created_at < ?
			  AND `+botUAClause+`
		), wallpaper AS (
			SELECT COUNT(*) AS wallpaper_views
			FROM wallpaper_events
			WHERE event_type = 'view' AND created_at >= ? AND created_at < ?
		), api AS (
			SELECT
				COUNT(*) AS api_requests,
				COUNT(*) FILTER (WHERE COALESCE((props->>'status')::int, 0) >= 400) AS api_errors,
				ROUND(COALESCE(AVG((props->>'duration_ms')::bigint), 0))::bigint AS avg_api_latency_ms,
				ROUND(COALESCE(percentile_cont(0.95) WITHIN GROUP (ORDER BY (props->>'duration_ms')::bigint), 0))::bigint AS p95_api_latency_ms
			FROM analytics_events
			WHERE event_type = 'api_request' AND created_at >= ? AND created_at < ?
		)
		SELECT
			page.page_views,
			page.sessions,
			page.unique_ips,
			wallpaper.wallpaper_views,
			api.api_requests,
			api.api_errors,
			api.avg_api_latency_ms,
			api.p95_api_latency_ms
		FROM page, wallpaper, api
	`, from, to, from, to, from, to).Scan(&t).Error
	return t, err
}

type PageViewDailyRow struct {
	Day         time.Time `gorm:"column:day" json:"day"`
	Path        string    `gorm:"column:path" json:"path"`
	Client      string    `gorm:"column:client" json:"client"`
	Views       int64     `gorm:"column:views" json:"views"`
	Sessions    int64     `gorm:"column:sessions" json:"sessions"`
	UniqueUsers int64     `gorm:"column:unique_users" json:"unique_users"`
	UniqueIPs   int64     `gorm:"column:unique_ips" json:"unique_ips"`
	RowCount    int64     `gorm:"column:row_count" json:"-"`
}

func (r *AnalyticsRepo) PageViewsDaily(ctx context.Context, from, to time.Time, timezone, client, query string, offset, limit int) ([]PageViewDailyRow, int64, error) {
	rows := []PageViewDailyRow{}
	err := r.db.WithContext(ctx).Raw(`
		WITH filtered AS (
			SELECT
				timezone(?, created_at)::date AS day,
				path,
				CASE
					WHEN lower(props->>'client') = 'chrome_extension' THEN 'chrome'
					WHEN lower(props->>'client') IN ('web', 'mac', 'android', 'ios', 'windows', 'chrome') THEN lower(props->>'client')
					ELSE 'web'
				END AS client,
				session_id, user_id, ip
			FROM analytics_events
			WHERE event_type = 'page_view'
			  AND created_at >= ? AND created_at < ?
			  AND `+botUAClause+`
		), grouped AS (
			SELECT
				day, path, client,
				COUNT(*) AS views,
				COUNT(DISTINCT NULLIF(session_id, '')) AS sessions,
				COUNT(DISTINCT NULLIF(user_id, 0)) AS unique_users,
				COUNT(DISTINCT NULLIF(ip, '')) AS unique_ips
			FROM filtered
			WHERE (? = '' OR client = ?)
			  AND (? = '' OR path ILIKE '%%' || ? || '%%')
			GROUP BY day, path, client
		)
		SELECT grouped.*, COUNT(*) OVER() AS row_count
		FROM grouped
		ORDER BY day DESC, views DESC, path ASC, client ASC
		LIMIT ? OFFSET ?
	`, timezone, from, to, client, client, query, query, limit, offset).Scan(&rows).Error
	return rows, detailRowCount(rows), err
}

type WallpaperViewDailyRow struct {
	Day         time.Time `gorm:"column:day" json:"day"`
	WallpaperID int64     `gorm:"column:wallpaper_id" json:"wallpaper_id"`
	Slug        string    `gorm:"column:slug" json:"slug"`
	Title       string    `gorm:"column:title" json:"title"`
	ThumbURL    string    `gorm:"column:thumb_url" json:"thumb_url"`
	Client      string    `gorm:"column:client" json:"client"`
	Views       int64     `gorm:"column:views" json:"views"`
	Sessions    int64     `gorm:"column:sessions" json:"sessions"`
	UniqueUsers int64     `gorm:"column:unique_users" json:"unique_users"`
	UniqueIPs   int64     `gorm:"column:unique_ips" json:"unique_ips"`
	RowCount    int64     `gorm:"column:row_count" json:"-"`
}

func (r *AnalyticsRepo) WallpaperViewsDaily(ctx context.Context, from, to time.Time, timezone, client, query string, offset, limit int) ([]WallpaperViewDailyRow, int64, error) {
	rows := []WallpaperViewDailyRow{}
	err := r.db.WithContext(ctx).Raw(`
		WITH grouped AS (
			SELECT
				timezone(?, we.created_at)::date AS day,
				we.wallpaper_id,
				w.slug,
				w.title,
				w.thumb_url,
				COALESCE(NULLIF(lower(we.client), ''), 'unknown') AS client,
				COUNT(*) AS views,
				COUNT(DISTINCT NULLIF(we.session_id, '')) AS sessions,
				COUNT(DISTINCT NULLIF(we.user_id, 0)) AS unique_users,
				COUNT(DISTINCT NULLIF(we.ip, '')) AS unique_ips
			FROM wallpaper_events we
			JOIN wallpapers w ON w.id = we.wallpaper_id
			WHERE we.event_type = 'view'
			  AND we.created_at >= ? AND we.created_at < ?
			  AND (? = '' OR COALESCE(NULLIF(lower(we.client), ''), 'unknown') = ?)
			  AND (? = '' OR w.title ILIKE '%%' || ? || '%%' OR w.slug ILIKE '%%' || ? || '%%' OR w.id::text = ?)
			GROUP BY 1, 2, 3, 4, 5, 6
		)
		SELECT grouped.*, COUNT(*) OVER() AS row_count
		FROM grouped
		ORDER BY day DESC, views DESC, wallpaper_id DESC, client ASC
		LIMIT ? OFFSET ?
	`, timezone, from, to, client, client, query, query, query, query, limit, offset).Scan(&rows).Error
	return rows, detailRowCount(rows), err
}

type APIRequestDailyRow struct {
	Day           time.Time `gorm:"column:day" json:"day"`
	Method        string    `gorm:"column:method" json:"method"`
	Route         string    `gorm:"column:route" json:"route"`
	Client        string    `gorm:"column:client" json:"client"`
	Requests      int64     `gorm:"column:requests" json:"requests"`
	Successes     int64     `gorm:"column:successes" json:"successes"`
	ClientErrors  int64     `gorm:"column:client_errors" json:"client_errors"`
	ServerErrors  int64     `gorm:"column:server_errors" json:"server_errors"`
	Sessions      int64     `gorm:"column:sessions" json:"sessions"`
	UniqueUsers   int64     `gorm:"column:unique_users" json:"unique_users"`
	UniqueIPs     int64     `gorm:"column:unique_ips" json:"unique_ips"`
	AvgLatencyMS  int64     `gorm:"column:avg_latency_ms" json:"avg_latency_ms"`
	P95LatencyMS  int64     `gorm:"column:p95_latency_ms" json:"p95_latency_ms"`
	MaxLatencyMS  int64     `gorm:"column:max_latency_ms" json:"max_latency_ms"`
	RequestBytes  int64     `gorm:"column:request_bytes" json:"request_bytes"`
	ResponseBytes int64     `gorm:"column:response_bytes" json:"response_bytes"`
	RowCount      int64     `gorm:"column:row_count" json:"-"`
}

func (r *AnalyticsRepo) APIRequestsDaily(ctx context.Context, from, to time.Time, timezone, client, query string, offset, limit int) ([]APIRequestDailyRow, int64, error) {
	rows := []APIRequestDailyRow{}
	err := r.db.WithContext(ctx).Raw(`
		WITH filtered AS (
			SELECT
				timezone(?, created_at)::date AS day,
				COALESCE(NULLIF(upper(props->>'method'), ''), 'UNKNOWN') AS method,
				COALESCE(NULLIF(props->>'route', ''), path) AS route,
				COALESCE(NULLIF(lower(props->>'client'), ''), 'other') AS client,
				COALESCE((props->>'status')::int, 0) AS status,
				GREATEST(COALESCE((props->>'duration_ms')::bigint, 0), 0) AS duration_ms,
				GREATEST(COALESCE((props->>'request_bytes')::bigint, 0), 0) AS request_bytes,
				GREATEST(COALESCE((props->>'response_bytes')::bigint, 0), 0) AS response_bytes,
				session_id, user_id, ip
			FROM analytics_events
			WHERE event_type = 'api_request'
			  AND created_at >= ? AND created_at < ?
		), grouped AS (
			SELECT
				day, method, route, client,
				COUNT(*) AS requests,
				COUNT(*) FILTER (WHERE status > 0 AND status < 400) AS successes,
				COUNT(*) FILTER (WHERE status >= 400 AND status < 500) AS client_errors,
				COUNT(*) FILTER (WHERE status >= 500) AS server_errors,
				COUNT(DISTINCT NULLIF(session_id, '')) AS sessions,
				COUNT(DISTINCT NULLIF(user_id, 0)) AS unique_users,
				COUNT(DISTINCT NULLIF(ip, '')) AS unique_ips,
				ROUND(AVG(duration_ms))::bigint AS avg_latency_ms,
				ROUND(percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms))::bigint AS p95_latency_ms,
				MAX(duration_ms) AS max_latency_ms,
				SUM(request_bytes) AS request_bytes,
				SUM(response_bytes) AS response_bytes
			FROM filtered
			WHERE (? = '' OR client = ?)
			  AND (? = '' OR route ILIKE '%%' || ? || '%%' OR method ILIKE '%%' || ? || '%%')
			GROUP BY day, method, route, client
		)
		SELECT grouped.*, COUNT(*) OVER() AS row_count
		FROM grouped
		ORDER BY day DESC, requests DESC, route ASC, method ASC, client ASC
		LIMIT ? OFFSET ?
	`, timezone, from, to, client, client, query, query, query, limit, offset).Scan(&rows).Error
	return rows, detailRowCount(rows), err
}

type analyticsDetailRow interface {
	PageViewDailyRow | WallpaperViewDailyRow | APIRequestDailyRow
}

func detailRowCount[T analyticsDetailRow](rows []T) int64 {
	if len(rows) == 0 {
		return 0
	}
	switch row := any(rows[0]).(type) {
	case PageViewDailyRow:
		return row.RowCount
	case WallpaperViewDailyRow:
		return row.RowCount
	case APIRequestDailyRow:
		return row.RowCount
	default:
		return 0
	}
}

// LabelCount is one row of any (key, count) Top-N breakdown.
type LabelCount struct {
	Label string `gorm:"column:label" json:"label"`
	Count int64  `gorm:"column:count" json:"count"`
}

// TopCountries returns the most common country codes over the window.
// Rows with empty country (events stored before CF-IPCountry was wired
// up) are excluded so they don't dominate the top-of-list with junk.
func (r *AnalyticsRepo) TopCountries(ctx context.Context, from, to time.Time, limit int) ([]LabelCount, error) {
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT country AS label, COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ? AND created_at < ?
		  AND country <> ''
		  AND `+botUAClause+`
		GROUP BY country
		ORDER BY count DESC
		LIMIT ?
	`, from, to, limit).Scan(&rows).Error
	return rows, err
}

// TopPaths returns the most viewed paths. Useful for spotting which
// landing pages a promotion campaign actually drives traffic to.
func (r *AnalyticsRepo) TopPaths(ctx context.Context, from, to time.Time, limit int) ([]LabelCount, error) {
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT path AS label, COUNT(*) AS count
		FROM analytics_events
		WHERE event_type = 'page_view'
		  AND created_at >= ? AND created_at < ?
		  AND path <> ''
		  AND `+botUAClause+`
		GROUP BY path
		ORDER BY count DESC
		LIMIT ?
	`, from, to, limit).Scan(&rows).Error
	return rows, err
}

// ClientDownloads counts official website clicks for Mac / Android
// client packages. New events write target_client; the fallback keeps
// old or ad-hoc events grouped if they used client directly.
func (r *AnalyticsRepo) ClientDownloads(ctx context.Context, from, to time.Time, limit int) ([]LabelCount, error) {
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
		  AND created_at >= ? AND created_at < ?
		  AND `+botUAClause+`
		GROUP BY label
		ORDER BY count DESC
		LIMIT ?
	`, from, to, limit).Scan(&rows).Error
	return rows, err
}

// ClientBreakdown groups analytics events by the client that emitted
// them. Web events now set props.client explicitly; native clients can
// reuse the same /events endpoint with mac/android/ios/windows later.
func (r *AnalyticsRepo) ClientBreakdown(ctx context.Context, from, to time.Time, limit int) ([]LabelCount, error) {
	if limit <= 0 {
		limit = 10
	}
	rows := []LabelCount{}
	err := r.db.WithContext(ctx).Raw(`
		SELECT label, COUNT(*) AS count
		FROM (
			SELECT
				CASE
					WHEN lower(props->>'client') = 'chrome_extension' THEN 'chrome'
					WHEN lower(props->>'client') IN ('web', 'mac', 'android', 'ios', 'windows', 'chrome') THEN lower(props->>'client')
					WHEN user_agent ~* 'WallpaperExchange/(mac|android|ios|windows)' THEN lower(substring(user_agent from 'WallpaperExchange/([A-Za-z]+)'))
					ELSE 'web'
				END AS label
			FROM analytics_events
			WHERE created_at >= ? AND created_at < ?
			  AND event_type <> 'api_request'
			  AND `+botUAClause+`
		) e
		GROUP BY label
		ORDER BY count DESC
		LIMIT ?
	`, from, to, limit).Scan(&rows).Error
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
func (r *AnalyticsRepo) TopReferrerHosts(ctx context.Context, from, to time.Time, limit int, ownHosts []string) ([]ReferrerRow, error) {
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
	args := []any{from, to}
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
		  AND created_at >= ? AND created_at < ?
		  AND `+botUAClause+`
		GROUP BY host
		HAVING COALESCE(NULLIF(split_part(split_part(referrer, '//', 2), '/', 1), ''), '') NOT IN (`+placeholders+`)
		ORDER BY count DESC
		LIMIT ?
	`, args...).Scan(&rows).Error
	return rows, err
}
