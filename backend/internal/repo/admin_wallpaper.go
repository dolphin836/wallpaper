package repo

import (
	"context"
	"errors"
	"strings"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type AdminWallpaperRow struct {
	model.Wallpaper
	UploaderUsername string `json:"uploader_username"`
	CategoryName     string `json:"category_name"`
}

type AdminWallpaperListOpts struct {
	Search     string
	Status     int16 // -1 means any
	CategoryID int64
	UserID     int64
	Offset     int
	Limit      int
	Sort       string // newest | views | likes | downloads
}

// AdminList returns wallpapers with uploader + category eagerly joined and
// counts the total set for pagination. Unlike the public list it does NOT
// filter by status by default, so removed/failed/duplicate rows surface for
// moderation.
func (r *WallpaperRepo) AdminList(ctx context.Context, opts AdminWallpaperListOpts) ([]AdminWallpaperRow, int64, error) {
	q := r.db.WithContext(ctx).Table("wallpapers").
		Joins("LEFT JOIN users u ON u.id = wallpapers.user_id").
		Joins("LEFT JOIN categories c ON c.id = wallpapers.category_id")

	cq := r.db.WithContext(ctx).Model(&model.Wallpaper{})

	if opts.Status >= 0 {
		q = q.Where("wallpapers.status = ?", opts.Status)
		cq = cq.Where("status = ?", opts.Status)
	}
	if opts.CategoryID > 0 {
		q = q.Where("wallpapers.category_id = ?", opts.CategoryID)
		cq = cq.Where("category_id = ?", opts.CategoryID)
	}
	if opts.UserID > 0 {
		q = q.Where("wallpapers.user_id = ?", opts.UserID)
		cq = cq.Where("user_id = ?", opts.UserID)
	}
	if s := strings.TrimSpace(opts.Search); s != "" {
		like := "%" + s + "%"
		q = q.Where("wallpapers.title ILIKE ? OR wallpapers.description ILIKE ? OR u.username ILIKE ?", like, like, like)
		// keep count cheap — search by title only on count side to avoid the join
		cq = cq.Where("title ILIKE ?", like)
	}

	switch opts.Sort {
	case "views":
		q = q.Order("wallpapers.view_count DESC, wallpapers.id DESC")
	case "likes":
		q = q.Order("wallpapers.like_count DESC, wallpapers.id DESC")
	case "downloads":
		q = q.Order("wallpapers.download_count DESC, wallpapers.id DESC")
	default:
		q = q.Order("wallpapers.id DESC")
	}

	limit := opts.Limit
	if limit <= 0 || limit > 100 {
		limit = 20
	}

	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []AdminWallpaperRow
	err := q.Select(`wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title, wallpapers.description,
                     wallpapers.category_id, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.original_url,
                     wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type,
                     wallpapers.dominant_color, wallpapers.status, wallpapers.view_count, wallpapers.like_count,
                     wallpapers.download_count, wallpapers.favorite_count, wallpapers.is_dynamic, wallpapers.dynamic_type,
                     wallpapers.created_at, wallpapers.updated_at,
                     COALESCE(u.username, '') AS uploader_username,
                     COALESCE(c.name, '')     AS category_name`).
		Offset(opts.Offset).Limit(limit).Find(&rows).Error
	return rows, total, err
}

type AdminWallpaperUpdate struct {
	Title       *string
	Description *string
	CategoryID  *int64
	Status      *int16
}

func (r *WallpaperRepo) AdminUpdate(ctx context.Context, id int64, u AdminWallpaperUpdate) error {
	updates := map[string]any{}
	if u.Title != nil {
		updates["title"] = *u.Title
	}
	if u.Description != nil {
		updates["description"] = *u.Description
	}
	if u.CategoryID != nil {
		updates["category_id"] = *u.CategoryID
	}
	if u.Status != nil {
		updates["status"] = *u.Status
	}
	if len(updates) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.Wallpaper{}).Where("id = ?", id).Updates(updates).Error
}

// AdminHardDelete physically removes a wallpaper row and every child row that
// references it. The caller is responsible for deleting the matching MinIO
// objects (original / thumb / preview / dynamic frames) — those URLs are
// returned via the resulting Wallpaper struct so the handler can issue the
// storage deletes after the DB transaction commits.
//
// Returns gorm.ErrRecordNotFound when the row is gone. No FK constraints are
// declared in init.sql, so child-table cleanup is done explicitly here in a
// single transaction.
func (r *WallpaperRepo) AdminHardDelete(ctx context.Context, id int64) (*model.Wallpaper, error) {
	var w model.Wallpaper
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("id = ?", id).First(&w).Error; err != nil {
			return err
		}
		// Order matters only insofar as child rows must go before the parent;
		// the children are independent of one another.
		children := []struct {
			model any
		}{
			{&model.WallpaperTag{}},
			{&model.WallpaperVariant{}},
			{&model.WallpaperEvent{}},
			{&model.UserLike{}},
			{&model.UserFavorite{}},
			{&model.UserDownload{}},
			{&model.CollectionWallpaper{}},
			{&model.Report{}},
		}
		for _, c := range children {
			if err := tx.Where("wallpaper_id = ?", id).Delete(c.model).Error; err != nil {
				return err
			}
		}
		return tx.Where("id = ?", id).Delete(&model.Wallpaper{}).Error
	})
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, err
		}
		return nil, err
	}
	return &w, nil
}
