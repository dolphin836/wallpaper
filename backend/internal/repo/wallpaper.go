package repo

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type SitemapEntry struct {
	Slug      string
	UpdatedAt time.Time
}

// FeedEntry is the slim row the RSS handler needs — slug for the link,
// title + description + preview thumbnail for the entry body, created_at
// for pubDate. Sorted newest first.
type FeedEntry struct {
	Slug        string
	Title       string
	Description string
	PreviewURL  string
	ThumbURL    string
	Width       int
	Height      int
	CreatedAt   time.Time
}

type WallpaperRepo struct {
	db *gorm.DB
}

func NewWallpaperRepo(db *gorm.DB) *WallpaperRepo {
	return &WallpaperRepo{db: db}
}

func (r *WallpaperRepo) Create(ctx context.Context, w *model.Wallpaper) error {
	return r.db.WithContext(ctx).Create(w).Error
}

func (r *WallpaperRepo) GetByID(ctx context.Context, id int64) (*model.Wallpaper, error) {
	var w model.Wallpaper
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, original_url, thumb_url, preview_url, poster_url, preview_video_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, is_ai_generated, rejection_reason, created_at, updated_at").
		Where("id = ? AND status != ?", id, model.WallpaperStatusRemoved).
		First(&w).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &w, nil
}

// GetByIDAnyStatus is GetByID without the status filter. Admin paths that
// operate on already-hidden rows (hard-delete on removed/duplicate) need
// to see them; the public GetByID hides removed rows by design.
func (r *WallpaperRepo) GetByIDAnyStatus(ctx context.Context, id int64) (*model.Wallpaper, error) {
	var w model.Wallpaper
	err := r.db.WithContext(ctx).Where("id = ?", id).First(&w).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &w, nil
}

func (r *WallpaperRepo) GetBySlug(ctx context.Context, slug string) (*model.Wallpaper, error) {
	var w model.Wallpaper
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, original_url, thumb_url, preview_url, poster_url, preview_video_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, is_ai_generated, rejection_reason, created_at, updated_at").
		Where("slug = ? AND status != ?", slug, model.WallpaperStatusRemoved).
		First(&w).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &w, nil
}

type ListOptions struct {
	Cursor     int64
	Limit      int
	CategoryID int64
	UserID     int64
	Status     int16
	// StatusFilter overrides Status / IncludeAllActive when set, and is
	// honored even when the value is 0 (Processing). Without this, callers
	// can't ask for processing wallpapers because `Status: 0` collides with
	// the struct zero-value and silently fell back to "published only".
	StatusFilter *int16
	// StatusFilterIn lets the caller ask for several statuses at once
	// (e.g. Processing + PendingReview for the profile's "Pending" tab).
	// Takes precedence over StatusFilter/Status/IncludeAllActive when set.
	StatusFilterIn   []int16
	IncludeAllActive bool
	Sort             string // "newest" or "popular"
	Search           string
	DeviceWidth      int
	DeviceHeight     int
	IncludeDynamic   bool
	DynamicOnly      bool
	AIOnly           bool
	VideoOnly        bool
	Resolution       string
	Color            string
	// ExcludeDynamic / ExcludeVideo let platform clients hide wallpaper
	// types they can't render. Windows hides macOS-dynamic HEIC (it
	// has no system support for them); macOS hides video/* wallpapers
	// (mac doesn't ship a video-wallpaper engine yet).
	ExcludeDynamic bool
	ExcludeVideo   bool
}

type WallpaperExclusionFilters struct {
	ExcludeDynamic bool
	ExcludeVideo   bool
	DeviceWidth    int
	DeviceHeight   int
	Resolution     string
	Color          string
}

var wallpaperResolutionOptions = []string{"720P", "1080P", "2K", "4K", "8K"}
var wallpaperColorFamilies = []string{
	"red",
	"orange",
	"yellow",
	"green",
	"cyan",
	"blue",
	"purple",
	"pink",
	"brown",
	"black",
	"gray",
	"white",
}

func SupportedWallpaperResolutions() []string {
	return append([]string(nil), wallpaperResolutionOptions...)
}

func NormalizeWallpaperResolution(value string) string {
	switch strings.ToUpper(strings.TrimSpace(value)) {
	case "720P":
		return "720P"
	case "1080P":
		return "1080P"
	case "2K":
		return "2K"
	case "4K":
		return "4K"
	case "8K":
		return "8K"
	default:
		return ""
	}
}

func wallpaperResolutionBounds(value string) (min, max int) {
	switch NormalizeWallpaperResolution(value) {
	case "720P":
		return 1280, 1920
	case "1080P":
		return 1920, 2560
	case "2K":
		return 2560, 3840
	case "4K":
		return 3840, 7680
	case "8K":
		return 7680, 0
	default:
		return 0, 0
	}
}

func SupportedWallpaperColorFamilies() []string {
	return append([]string(nil), wallpaperColorFamilies...)
}

func NormalizeWallpaperColorFamily(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	for _, family := range wallpaperColorFamilies {
		if value == family {
			return family
		}
	}
	return ""
}

// wallpaperColorFamilyPredicate builds a correlated EXISTS predicate that
// classifies every color in a wallpaper's generated palette using HSV-like
// hue, saturation, and brightness ranges. Matching the full palette instead
// of one exact dominant hex lets a wallpaper belong to every visible color
// family it contains.
func wallpaperColorFamilyPredicate(qualifier, family string) string {
	family = NormalizeWallpaperColorFamily(family)
	if family == "" {
		return ""
	}

	prefix := ""
	if qualifier != "" {
		prefix = qualifier + "."
	}

	var familyCondition string
	switch family {
	case "black":
		familyCondition = "hsv.brightness < 0.20"
	case "white":
		familyCondition = "hsv.brightness >= 0.85 AND hsv.saturation <= 0.18"
	case "gray":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.brightness < 0.85 AND hsv.saturation <= 0.18"
	case "red":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.saturation > 0.18 AND (hsv.hue < 15 OR hsv.hue >= 345)"
	case "orange":
		familyCondition = "hsv.brightness >= 0.55 AND hsv.saturation > 0.18 AND hsv.hue >= 15 AND hsv.hue < 45"
	case "yellow":
		familyCondition = "hsv.brightness >= 0.45 AND hsv.saturation > 0.18 AND hsv.hue >= 45 AND hsv.hue < 70"
	case "green":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.saturation > 0.18 AND hsv.hue >= 70 AND hsv.hue < 165"
	case "cyan":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.saturation > 0.18 AND hsv.hue >= 165 AND hsv.hue < 195"
	case "blue":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.saturation > 0.18 AND hsv.hue >= 195 AND hsv.hue < 255"
	case "purple":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.saturation > 0.18 AND hsv.hue >= 255 AND hsv.hue < 290"
	case "pink":
		familyCondition = "hsv.brightness >= 0.35 AND hsv.saturation > 0.18 AND hsv.hue >= 290 AND hsv.hue < 345"
	case "brown":
		familyCondition = "hsv.brightness >= 0.20 AND hsv.brightness < 0.55 AND hsv.saturation > 0.18 AND hsv.hue >= 15 AND hsv.hue < 45"
	}

	palette := "CONCAT_WS(',', NULLIF(" + prefix + "color_palette, ''), NULLIF(" + prefix + "dominant_color, ''))"
	return `EXISTS (
		SELECT 1
		FROM unnest(string_to_array(` + palette + `, ',')) AS palette(raw_hex)
		CROSS JOIN LATERAL (
			SELECT BTRIM(palette.raw_hex) AS hex
		) normalized
		CROSS JOIN LATERAL (
			SELECT
				normalized.hex ~ '^#[0-9A-Fa-f]{6}$' AS valid,
				get_byte(decode(CASE WHEN normalized.hex ~ '^#[0-9A-Fa-f]{6}$' THEN SUBSTRING(normalized.hex FROM 2) ELSE '000000' END, 'hex'), 0) / 255.0 AS red_value,
				get_byte(decode(CASE WHEN normalized.hex ~ '^#[0-9A-Fa-f]{6}$' THEN SUBSTRING(normalized.hex FROM 2) ELSE '000000' END, 'hex'), 1) / 255.0 AS green_value,
				get_byte(decode(CASE WHEN normalized.hex ~ '^#[0-9A-Fa-f]{6}$' THEN SUBSTRING(normalized.hex FROM 2) ELSE '000000' END, 'hex'), 2) / 255.0 AS blue_value
		) rgb
		CROSS JOIN LATERAL (
			SELECT
				GREATEST(rgb.red_value, rgb.green_value, rgb.blue_value) AS high,
				LEAST(rgb.red_value, rgb.green_value, rgb.blue_value) AS low
		) channels
		CROSS JOIN LATERAL (
			SELECT
				channels.high AS brightness,
				CASE WHEN channels.high = 0 THEN 0 ELSE (channels.high - channels.low) / channels.high END AS saturation,
				CASE
					WHEN channels.high = channels.low THEN 0
					WHEN channels.high = rgb.red_value THEN
						60 * ((rgb.green_value - rgb.blue_value) / (channels.high - channels.low))
						+ CASE WHEN rgb.green_value < rgb.blue_value THEN 360 ELSE 0 END
					WHEN channels.high = rgb.green_value THEN
						60 * ((rgb.blue_value - rgb.red_value) / (channels.high - channels.low) + 2)
					ELSE
						60 * ((rgb.red_value - rgb.green_value) / (channels.high - channels.low) + 4)
				END AS hue
		) hsv
		WHERE rgb.valid AND (` + familyCondition + `)
	)`
}

func applyWallpaperFacets(query *gorm.DB, qualifier, resolution, color string) *gorm.DB {
	columnPrefix := qualifier
	if columnPrefix != "" {
		columnPrefix += "."
	}
	dimension := "GREATEST(" + columnPrefix + "width, " + columnPrefix + "height)"
	minResolution, maxResolution := wallpaperResolutionBounds(resolution)
	if minResolution > 0 {
		query = query.Where(dimension+" >= ?", minResolution)
	}
	if maxResolution > 0 {
		query = query.Where(dimension+" < ?", maxResolution)
	}
	if predicate := wallpaperColorFamilyPredicate(qualifier, color); predicate != "" {
		query = query.Where(predicate)
	}
	return query
}

func (f WallpaperExclusionFilters) apply(query *gorm.DB, qualifier string) *gorm.DB {
	query = applyWallpaperFacets(query, qualifier, f.Resolution, f.Color)
	if qualifier != "" {
		qualifier += "."
	}
	if f.ExcludeDynamic {
		query = query.Where(qualifier + "is_dynamic = false")
	}
	if f.ExcludeVideo {
		query = query.Where(qualifier + "file_type NOT LIKE 'video/%'")
	}
	if f.DeviceWidth > 0 && f.DeviceHeight > 0 {
		query = query.Where(
			qualifier+"width >= ? AND "+qualifier+"height >= ?",
			f.DeviceWidth, f.DeviceHeight,
		)
	}
	return query
}

// applyListFilters applies every WHERE clause from ListOptions except the cursor.
// Cursor is intentionally excluded so Count uses the full set, not just the current page slice.
func (r *WallpaperRepo) applyListFilters(query *gorm.DB, opts ListOptions) *gorm.DB {
	if opts.CategoryID > 0 {
		query = query.Where("category_id = ?", opts.CategoryID)
	}
	if opts.UserID > 0 {
		query = query.Where("user_id = ?", opts.UserID)
	}
	if len(opts.StatusFilterIn) > 0 {
		query = query.Where("status IN ?", opts.StatusFilterIn)
	} else if opts.StatusFilter != nil {
		query = query.Where("status = ?", *opts.StatusFilter)
	} else if opts.IncludeAllActive {
		query = query.Where("status != ?", model.WallpaperStatusRemoved)
	} else if opts.Status > 0 {
		query = query.Where("status = ?", opts.Status)
	} else {
		query = query.Where("status = ?", model.WallpaperStatusPublished)
	}
	if opts.Search != "" {
		query = query.Where("title ILIKE ?", "%"+opts.Search+"%")
	}
	if opts.AIOnly {
		query = query.Where("is_ai_generated = true")
	}
	if opts.VideoOnly {
		query = query.Where("file_type LIKE 'video/%'")
	}
	if opts.ExcludeDynamic {
		query = query.Where("is_dynamic = false")
	}
	if opts.ExcludeVideo {
		query = query.Where("file_type NOT LIKE 'video/%'")
	}
	if opts.DynamicOnly {
		query = query.Where("is_dynamic = true OR file_type LIKE 'video/%'")
	} else if opts.DeviceWidth > 0 && opts.DeviceHeight > 0 {
		if opts.IncludeDynamic {
			query = query.Where("((width >= ? AND height >= ?) OR is_dynamic = true)",
				opts.DeviceWidth, opts.DeviceHeight)
		} else {
			query = query.Where("width >= ? AND height >= ?",
				opts.DeviceWidth, opts.DeviceHeight)
		}
	}
	return applyWallpaperFacets(query, "", opts.Resolution, opts.Color)
}

func (r *WallpaperRepo) List(ctx context.Context, opts ListOptions) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, thumb_url, preview_url, poster_url, preview_video_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, is_ai_generated, rejection_reason, created_at")
	query = r.applyListFilters(query, opts)
	if opts.Cursor > 0 {
		query = query.Where("id < ?", opts.Cursor)
	}

	switch opts.Sort {
	case "popular":
		query = query.Order("like_count DESC, id DESC")
	default:
		query = query.Order("id DESC")
	}

	limit := opts.Limit
	if limit <= 0 {
		limit = 20
	}

	var wallpapers []model.Wallpaper
	err := query.Limit(limit).Find(&wallpapers).Error
	return wallpapers, err
}

func (r *WallpaperRepo) Count(ctx context.Context, opts ListOptions) (int64, error) {
	query := r.applyListFilters(r.db.WithContext(ctx).Model(&model.Wallpaper{}), opts)
	var count int64
	err := query.Count(&count).Error
	return count, err
}

func (r *WallpaperRepo) GetByIDs(ctx context.Context, ids []int64) ([]model.Wallpaper, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	var wallpapers []model.Wallpaper
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, thumb_url, preview_url, poster_url, preview_video_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, is_ai_generated, rejection_reason, created_at").
		Where("id IN ? AND status = ?", ids, model.WallpaperStatusPublished).
		Find(&wallpapers).Error
	return wallpapers, err
}

func (r *WallpaperRepo) UpdateStatus(ctx context.Context, id int64, status int16) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update("status", status).Error
}

func (r *WallpaperRepo) UpdateProcessed(ctx context.Context, id int64, thumbURL, previewURL string, width, height int, dominantColor, colorPalette string) error {
	updates := map[string]any{
		"thumb_url":      thumbURL,
		"preview_url":    previewURL,
		"width":          width,
		"height":         height,
		"dominant_color": dominantColor,
		"color_palette":  colorPalette,
		// Status transition uses a SQL CASE so reprocess preserves
		// the existing publication state:
		//   Processing (0) → PendingReview (5): first-time upload
		//     just finished the image pipeline; admin needs to review.
		//   Published (1) → Published: an admin / CLI re-queued an
		//     already-live wallpaper (e.g., `recompress` to refresh
		//     previews after a worker-side change); keep it live.
		//   Removed (3) → Removed, Duplicate (4) → Duplicate,
		//     Rejected (6) → Rejected: terminal states stay put.
		//   PendingReview (5) → PendingReview, Failed (2) →
		//     PendingReview: a re-run from a non-terminal state
		//     means the artifacts were regenerated and should be
		//     looked at again.
		// This was previously a hard-coded PendingReview, which
		// silently un-published 800+ live wallpapers when the
		// recompress CLI was used to refresh derived artifacts.
		// ::smallint casts on every THEN/ELSE branch are required —
		// without them pgx binds the int16 placeholders ambiguously
		// and Postgres infers the whole CASE result as TEXT, then
		// refuses to write it into the smallint `status` column with
		// SQLSTATE 42804 ("expression is of type text"). See worker
		// logs around 2026-05-30 17:17 — every upload after the
		// reprocess-status-preserve change failed for that reason.
		"status": gorm.Expr(`CASE
			WHEN status = ? THEN ?::smallint
			WHEN status = ? THEN ?::smallint
			WHEN status = ? THEN ?::smallint
			WHEN status = ? THEN ?::smallint
			WHEN status = ? THEN ?::smallint
			ELSE ?::smallint
		END`,
			model.WallpaperStatusPublished, model.WallpaperStatusPublished,
			model.WallpaperStatusRemoved, model.WallpaperStatusRemoved,
			model.WallpaperStatusDuplicate, model.WallpaperStatusDuplicate,
			model.WallpaperStatusRejected, model.WallpaperStatusRejected,
			model.WallpaperStatusPendingReview, model.WallpaperStatusPendingReview,
			model.WallpaperStatusPendingReview),
	}
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(updates).Error
}

// UpdateTranscodedInput carries the post-transcode metadata the
// worker writes back to the wallpapers row when a video upload
// finishes processing.
type UpdateTranscodedInput struct {
	OriginalURL     string
	ThumbURL        string
	PreviewURL      string
	PosterURL       string
	PreviewVideoURL string
	Width           int
	Height          int
	FileSize        int64
	FileType        string
}

// UpdateTranscoded writes the transcoded mp4 + three poster URLs back to
// the wallpaper row and transitions Processing → PendingReview so
// the admin queue picks it up. Mirrors UpdateProcessed in spirit but
// is keyed for video uploads. Video still images use the same 400px thumb,
// 1600px preview, and full-size poster progression as normal wallpapers.
func (r *WallpaperRepo) UpdateTranscoded(ctx context.Context, id int64, in UpdateTranscodedInput) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"original_url":      in.OriginalURL,
			"thumb_url":         in.ThumbURL,
			"preview_url":       in.PreviewURL,
			"poster_url":        in.PosterURL,
			"preview_video_url": in.PreviewVideoURL,
			"width":             in.Width,
			"height":            in.Height,
			"file_size":         in.FileSize,
			"file_type":         in.FileType,
			"status":            model.WallpaperStatusPendingReview,
		}).Error
}

// AdminApprove transitions a wallpaper from PendingReview → Published,
// clearing any prior rejection reason in case the row went through a
// reject-then-undo cycle. Called by the admin review queue handler.
// Returns whether a row actually transitioned, so the caller can tell
// a real approval apart from a no-op on an already-published (or
// otherwise non-pending) wallpaper — the upload coin reward must only
// fire on the real transition.
func (r *WallpaperRepo) AdminApprove(ctx context.Context, id int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ? AND status = ?", id, model.WallpaperStatusPendingReview).
		Updates(map[string]any{
			"status":           model.WallpaperStatusPublished,
			"rejection_reason": "",
		})
	return res.RowsAffected > 0, res.Error
}

// AdminReject transitions PendingReview → Rejected and stores the
// human-readable reason the uploader sees on their "my uploads" view.
func (r *WallpaperRepo) AdminReject(ctx context.Context, id int64, reason string) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ? AND status = ?", id, model.WallpaperStatusPendingReview).
		Updates(map[string]any{
			"status":           model.WallpaperStatusRejected,
			"rejection_reason": reason,
		}).Error
}

// ReviewQueue returns wallpapers awaiting admin review, newest first.
// Uses the idx_wallpapers_review_queue partial index so the list stays
// cheap even when the catalog grows past hundreds of thousands of
// already-published rows.
func (r *WallpaperRepo) ReviewQueue(ctx context.Context, limit, offset int) ([]model.Wallpaper, int64, error) {
	var rows []model.Wallpaper
	var total int64
	if err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("status = ?", model.WallpaperStatusPendingReview).
		Count(&total).Error; err != nil {
		return nil, 0, err
	}
	if err := r.db.WithContext(ctx).
		Where("status = ?", model.WallpaperStatusPendingReview).
		Order("created_at ASC"). // oldest first — first-come first-reviewed
		Limit(limit).
		Offset(offset).
		Find(&rows).Error; err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

// SetAutoTagged writes the LLM-chosen category onto a published wallpaper,
// and optionally fills in the title when the uploader didn't supply one.
// Caller passes the title to set; pass empty string to leave the existing
// title untouched. No-op transaction overhead is acceptable — autotag
// runs once per upload, far off the hot path.
func (r *WallpaperRepo) SetAutoTagged(ctx context.Context, id int64, categoryID int64, titleIfEmpty string) error {
	updates := map[string]any{"category_id": categoryID}
	if titleIfEmpty != "" {
		// Only overwrite when the current title is blank — guard via SQL
		// so a concurrent user title edit doesn't get clobbered.
		if err := r.db.WithContext(ctx).
			Model(&model.Wallpaper{}).
			Where("id = ? AND (title = '' OR title IS NULL)", id).
			Update("title", titleIfEmpty).Error; err != nil {
			return err
		}
	}
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(updates).Error
}

func (r *WallpaperRepo) UpdateDynamic(ctx context.Context, id int64, isDynamic bool, dynamicType, frameURLs string) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"is_dynamic":   isDynamic,
			"dynamic_type": dynamicType,
			"frame_urls":   frameURLs,
		}).Error
}

var validCounterFields = map[string]bool{
	"view_count":     true,
	"like_count":     true,
	"download_count": true,
	"favorite_count": true,
}

func (r *WallpaperRepo) IncrementCounter(ctx context.Context, id int64, field string, delta int64) error {
	if !validCounterFields[field] {
		return fmt.Errorf("invalid counter field: %s", field)
	}
	expr := gorm.Expr(field+" + ?", delta)
	if delta < 0 {
		expr = gorm.Expr("GREATEST("+field+" + ?, 0)", delta)
	}
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update(field, expr).Error
}

func (r *WallpaperRepo) Delete(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update("status", model.WallpaperStatusRemoved).Error
}

type PhashEntry struct {
	ID    int64
	Phash int64
}

// SimilarCandidate is the lightweight projection of a published wallpaper
// used to score "similar" rankings on the detail page. Includes all four
// signals the ranker reads: dominant color, category, pHash, and (joined
// later) tag overlap.
type SimilarCandidate struct {
	ID            int64
	DominantColor string
	CategoryID    int64
	Phash         int64
}

// similarCandidatePoolCap bounds the in-memory ranking pool on the detail
// page. The ranker walks the slice per request, so the pool must not grow
// with the catalog; the newest N published rows are a good-enough candidate
// universe long before N is reached.
const similarCandidatePoolCap = 5000

// ListSimilarCandidates returns up to similarCandidatePoolCap of the newest
// published wallpapers except the target as SimilarCandidates. The ranker
// walks this slice in memory — a join-free pass is simpler and faster than
// building the score in SQL.
func (r *WallpaperRepo) ListSimilarCandidates(ctx context.Context, excludeID int64, filters WallpaperExclusionFilters) ([]SimilarCandidate, error) {
	var entries []SimilarCandidate
	query := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("id, dominant_color, category_id, phash").
		Where("status = ? AND id <> ?", model.WallpaperStatusPublished, excludeID)
	query = filters.apply(query, "")
	err := query.
		Order("id DESC").
		Limit(similarCandidatePoolCap).
		Find(&entries).Error
	return entries, err
}

// ListPopularIDs returns top wallpapers by like+favorite+view weight,
// excluding wallpapers the given user has already interacted with. Used as
// a cold-start fallback when the user has no signals to score against.
func (r *WallpaperRepo) ListPopularIDs(ctx context.Context, userID int64, limit int, filters WallpaperExclusionFilters) ([]int64, error) {
	type row struct {
		ID int64
	}
	var rows []row
	minResolution, maxResolution := wallpaperResolutionBounds(filters.Resolution)
	colorPredicate := wallpaperColorFamilyPredicate("w", filters.Color)
	if colorPredicate == "" {
		colorPredicate = "TRUE"
	}
	querySQL := `
		WITH user_signals AS (
			SELECT wallpaper_id FROM user_likes WHERE user_id = ?
			UNION
			SELECT wallpaper_id FROM user_favorites WHERE user_id = ?
			UNION
			SELECT wallpaper_id FROM user_downloads WHERE user_id = ?
		)
		SELECT w.id
		FROM wallpapers w
		WHERE w.status = ?
		  AND w.id NOT IN (SELECT wallpaper_id FROM user_signals)
		  AND (? = false OR w.is_dynamic = false)
		  AND (? = false OR w.file_type NOT LIKE 'video/%')
		  AND (? <= 0 OR ? <= 0 OR (w.width >= ? AND w.height >= ?))
		  AND (? <= 0 OR GREATEST(w.width, w.height) >= ?)
		  AND (? <= 0 OR GREATEST(w.width, w.height) < ?)
		  AND (` + colorPredicate + `)
		ORDER BY (w.like_count * 2 + w.favorite_count * 3 + w.view_count) DESC, w.created_at DESC
		LIMIT ?
	`
	err := r.db.WithContext(ctx).Raw(querySQL, userID, userID, userID, model.WallpaperStatusPublished,
		filters.ExcludeDynamic, filters.ExcludeVideo,
		filters.DeviceWidth, filters.DeviceHeight, filters.DeviceWidth, filters.DeviceHeight,
		minResolution, minResolution, maxResolution, maxResolution,
		limit).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	ids := make([]int64, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	return ids, nil
}

// ListForYouIDs scores candidate wallpapers by the user's aggregate tag
// affinity (sum of weighted interactions) and returns the top wallpaper IDs.
// Favorites count for 2, likes and downloads for 1; wallpapers the user has
// already interacted with are excluded. Falls back to the empty slice when
// the user has no signals yet — the caller can show popular in that case.
func (r *WallpaperRepo) ListForYouIDs(ctx context.Context, userID int64, limit int, filters WallpaperExclusionFilters) ([]int64, error) {
	type row struct {
		WallpaperID int64
	}
	var rows []row
	minResolution, maxResolution := wallpaperResolutionBounds(filters.Resolution)
	colorPredicate := wallpaperColorFamilyPredicate("w", filters.Color)
	if colorPredicate == "" {
		colorPredicate = "TRUE"
	}
	querySQL := `
		WITH user_signals AS (
			SELECT wallpaper_id, 1 AS weight FROM user_likes WHERE user_id = ?
			UNION ALL
			SELECT wallpaper_id, 2 AS weight FROM user_favorites WHERE user_id = ?
			UNION ALL
			SELECT wallpaper_id, 1 AS weight FROM user_downloads WHERE user_id = ?
		),
		tag_affinity AS (
			SELECT wt.tag_id, SUM(us.weight) AS w
			FROM user_signals us
			JOIN wallpaper_tags wt ON wt.wallpaper_id = us.wallpaper_id
			GROUP BY wt.tag_id
		),
		candidate_scores AS (
			SELECT wt.wallpaper_id, SUM(ta.w) AS tag_score
			FROM wallpaper_tags wt
			JOIN tag_affinity ta ON ta.tag_id = wt.tag_id
			WHERE wt.wallpaper_id NOT IN (SELECT wallpaper_id FROM user_signals)
			GROUP BY wt.wallpaper_id
		)
		SELECT cs.wallpaper_id
		FROM candidate_scores cs
		JOIN wallpapers w ON w.id = cs.wallpaper_id
		WHERE w.status = ?
		  AND (? = false OR w.is_dynamic = false)
		  AND (? = false OR w.file_type NOT LIKE 'video/%')
		  AND (? <= 0 OR ? <= 0 OR (w.width >= ? AND w.height >= ?))
		  AND (? <= 0 OR GREATEST(w.width, w.height) >= ?)
		  AND (? <= 0 OR GREATEST(w.width, w.height) < ?)
		  AND (` + colorPredicate + `)
		ORDER BY cs.tag_score DESC, w.created_at DESC
		LIMIT ?
	`
	err := r.db.WithContext(ctx).Raw(querySQL, userID, userID, userID, model.WallpaperStatusPublished,
		filters.ExcludeDynamic, filters.ExcludeVideo,
		filters.DeviceWidth, filters.DeviceHeight, filters.DeviceWidth, filters.DeviceHeight,
		minResolution, minResolution, maxResolution, maxResolution,
		limit).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	ids := make([]int64, len(rows))
	for i, r := range rows {
		ids[i] = r.WallpaperID
	}
	return ids, nil
}

// TagOverlapWith returns wallpaper_id → number of tags that wallpaper shares
// with the target. Only includes wallpapers that share at least one tag.
func (r *WallpaperRepo) TagOverlapWith(ctx context.Context, wallpaperID int64) (map[int64]int, error) {
	type row struct {
		WallpaperID int64
		Overlap     int
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT wt.wallpaper_id, COUNT(*) AS overlap
		FROM wallpaper_tags wt
		WHERE wt.tag_id IN (SELECT tag_id FROM wallpaper_tags WHERE wallpaper_id = ?)
		  AND wt.wallpaper_id <> ?
		GROUP BY wt.wallpaper_id
	`, wallpaperID, wallpaperID).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	m := make(map[int64]int, len(rows))
	for _, r := range rows {
		m[r.WallpaperID] = r.Overlap
	}
	return m, nil
}

// phashPoolCap bounds the duplicate-detection comparison set loaded per
// upload. Dedup against the newest N published phashes (16 bytes/row, so
// the cap is ~320KB) — once the catalog outgrows the cap, uploads stop
// being compared against the oldest rows, which is an acceptable trade
// for a hard memory bound on the worker.
const phashPoolCap = 20000

func (r *WallpaperRepo) ListPublishedPhashes(ctx context.Context, excludeID int64) ([]PhashEntry, error) {
	var entries []PhashEntry
	err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("id, phash").
		Where("status = ? AND phash <> 0 AND id <> ?", model.WallpaperStatusPublished, excludeID).
		Order("id DESC").
		Limit(phashPoolCap).
		Find(&entries).Error
	return entries, err
}

func (r *WallpaperRepo) SetPhash(ctx context.Context, id int64, phash int64) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update("phash", phash).Error
}

func (r *WallpaperRepo) SetQualityFlag(ctx context.Context, id int64, flag, notes string) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"quality_flag":  flag,
			"quality_notes": notes,
		}).Error
}

func (r *WallpaperRepo) SetStatus(ctx context.Context, id int64, status int16) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update("status", status).Error
}

func (r *WallpaperRepo) ListPublishedForSitemap(ctx context.Context) ([]SitemapEntry, error) {
	var entries []SitemapEntry
	err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("slug, updated_at").
		Where("status = ? AND slug <> ''", model.WallpaperStatusPublished).
		Order("updated_at DESC").
		Find(&entries).Error
	return entries, err
}

// ListRecentForFeed returns the N newest published wallpapers in the
// shape the RSS handler needs. Capped at 100 — feed readers don't read
// more than that, and the response is cached for 5 minutes anyway.
func (r *WallpaperRepo) ListRecentForFeed(ctx context.Context, limit int) ([]FeedEntry, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var entries []FeedEntry
	err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("slug, title, description, preview_url, thumb_url, width, height, created_at").
		Where("status = ? AND slug <> ''", model.WallpaperStatusPublished).
		Order("created_at DESC").
		Limit(limit).
		Find(&entries).Error
	return entries, err
}
