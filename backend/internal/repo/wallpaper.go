package repo

import (
	"context"
	"errors"
	"fmt"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

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
		Select("id, user_id, title, description, category_id, original_url, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, created_at, updated_at").
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
}

func (r *WallpaperRepo) List(ctx context.Context, opts ListOptions) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Select("id, user_id, title, description, category_id, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, created_at")

	if opts.Cursor > 0 {
		query = query.Where("id < ?", opts.Cursor)
	}
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
	if opts.DeviceWidth > 0 && opts.DeviceHeight > 0 {
		query = query.Where("id IN (SELECT wallpaper_id FROM wallpaper_variants WHERE width = ? AND height = ?)",
			opts.DeviceWidth, opts.DeviceHeight)
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

func (r *WallpaperRepo) GetByIDs(ctx context.Context, ids []int64) ([]model.Wallpaper, error) {
	if len(ids) == 0 {
		return nil, nil
	}
	var wallpapers []model.Wallpaper
	err := r.db.WithContext(ctx).
		Select("id, user_id, title, description, category_id, thumb_url, preview_url, width, height, file_size, file_type, dominant_color, color_palette, status, view_count, like_count, download_count, favorite_count, is_dynamic, dynamic_type, created_at").
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

func (r *WallpaperRepo) UpdateDynamic(ctx context.Context, id int64, isDynamic bool, dynamicType string) error {
	return r.db.WithContext(ctx).
		Model(&model.Wallpaper{}).
		Where("id = ?", id).
		Updates(map[string]any{
			"is_dynamic":   isDynamic,
			"dynamic_type": dynamicType,
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
