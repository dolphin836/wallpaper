package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type SitemapEntry struct {
	Slug      string
	UpdatedAt time.Time
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
		Select("id, slug, user_id, title, description, category_id, original_url, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, created_at, updated_at").
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

func (r *WallpaperRepo) GetBySlug(ctx context.Context, slug string) (*model.Wallpaper, error) {
	var w model.Wallpaper
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, original_url, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, created_at, updated_at").
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
	Cursor           int64
	Limit            int
	CategoryID       int64
	UserID           int64
	Status           int16
	IncludeAllActive bool
	Sort             string // "newest" or "popular"
	Search           string
	DeviceWidth      int
	DeviceHeight     int
	IncludeDynamic   bool
	DynamicOnly      bool
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
	if opts.IncludeAllActive {
		query = query.Where("status != ?", model.WallpaperStatusRemoved)
	} else if opts.Status > 0 {
		query = query.Where("status = ?", opts.Status)
	} else {
		query = query.Where("status = ?", model.WallpaperStatusPublished)
	}
	if opts.Search != "" {
		query = query.Where("title ILIKE ?", "%"+opts.Search+"%")
	}
	if opts.DynamicOnly {
		query = query.Where("is_dynamic = true")
	} else if opts.DeviceWidth > 0 && opts.DeviceHeight > 0 {
		if opts.IncludeDynamic {
			query = query.Where("(id IN (SELECT wallpaper_id FROM wallpaper_variants WHERE width = ? AND height = ?) OR is_dynamic = true)",
				opts.DeviceWidth, opts.DeviceHeight)
		} else {
			query = query.Where("id IN (SELECT wallpaper_id FROM wallpaper_variants WHERE width = ? AND height = ?)",
				opts.DeviceWidth, opts.DeviceHeight)
		}
	}
	return query
}

func (r *WallpaperRepo) List(ctx context.Context, opts ListOptions) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, category_id, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, created_at")
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
		Select("id, slug, user_id, title, description, category_id, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, frame_urls, created_at").
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
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"thumb_url":      thumbURL,
			"preview_url":    previewURL,
			"width":          width,
			"height":         height,
			"dominant_color": dominantColor,
			"color_palette":  colorPalette,
			"status":         model.WallpaperStatusPublished,
		}).Error
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
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update(field, gorm.Expr(field+" + ?", delta)).Error
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

type ColorEntry struct {
	ID            int64
	DominantColor string
}

func (r *WallpaperRepo) ListPublishedColors(ctx context.Context, excludeID int64) ([]ColorEntry, error) {
	var entries []ColorEntry
	err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("id, dominant_color").
		Where("status = ? AND id <> ? AND dominant_color <> ''", model.WallpaperStatusPublished, excludeID).
		Find(&entries).Error
	return entries, err
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

func (r *WallpaperRepo) ListPublishedPhashes(ctx context.Context, excludeID int64) ([]PhashEntry, error) {
	var entries []PhashEntry
	err := r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Select("id, phash").
		Where("status = ? AND phash <> 0 AND id <> ?", model.WallpaperStatusPublished, excludeID).
		Find(&entries).Error
	return entries, err
}

func (r *WallpaperRepo) SetPhash(ctx context.Context, id int64, phash int64) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Update("phash", phash).Error
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
