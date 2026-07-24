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
	// WallpaperType is an exclusive admin media bucket: ai, heic, video,
	// or image. Empty means all types.
	WallpaperType string
	// QualityFlag accepts the literal flag values stored in wallpapers
	// (`ok`, `low_aesthetic`, `watermark`, ...) plus synthetic values:
	// `""` = no filter, `"unassessed"` = empty string, `"flagged"` =
	// anything that isn't `''` or `'ok'`, and `"weekly_eligible"` =
	// rows that may be manually added to a weekly slate.
	QualityFlag string
	Offset      int
	Limit       int
	Sort        string // newest | views | likes | downloads
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
	switch opts.WallpaperType {
	case "ai":
		q = q.Where("wallpapers.is_ai_generated = true")
		cq = cq.Where("is_ai_generated = true")
	case "heic":
		q = q.Where("wallpapers.is_ai_generated = false AND LOWER(wallpapers.file_type) IN ('image/heic', 'image/heif')")
		cq = cq.Where("is_ai_generated = false AND LOWER(file_type) IN ('image/heic', 'image/heif')")
	case "video":
		q = q.Where("wallpapers.is_ai_generated = false AND wallpapers.file_type LIKE 'video/%'")
		cq = cq.Where("is_ai_generated = false AND file_type LIKE 'video/%'")
	case "image":
		q = q.Where("wallpapers.is_ai_generated = false AND wallpapers.file_type LIKE 'image/%' AND LOWER(wallpapers.file_type) NOT IN ('image/heic', 'image/heif')")
		cq = cq.Where("is_ai_generated = false AND file_type LIKE 'image/%' AND LOWER(file_type) NOT IN ('image/heic', 'image/heif')")
	}
	switch opts.QualityFlag {
	case "":
		// no filter
	case "unassessed":
		q = q.Where("wallpapers.quality_flag = ''")
		cq = cq.Where("quality_flag = ''")
	case "weekly_eligible":
		q = q.Where("wallpapers.quality_flag IN ('', 'ok')")
		cq = cq.Where("quality_flag IN ('', 'ok')")
	case "flagged":
		q = q.Where("wallpapers.quality_flag NOT IN ('', 'ok')")
		cq = cq.Where("quality_flag NOT IN ('', 'ok')")
	default:
		// exact match against a specific flag like 'ok' or 'low_aesthetic'.
		q = q.Where("wallpapers.quality_flag = ?", opts.QualityFlag)
		cq = cq.Where("quality_flag = ?", opts.QualityFlag)
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
			         wallpapers.category_id, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.poster_url, wallpapers.original_url,
                     wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type,
                     wallpapers.dominant_color, wallpapers.status, wallpapers.view_count, wallpapers.like_count,
                     wallpapers.download_count, wallpapers.favorite_count, wallpapers.is_dynamic, wallpapers.dynamic_type,
                     wallpapers.quality_flag, wallpapers.quality_notes,
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

// HardDeleteResult bundles everything the handler needs to fully purge a
// wallpaper. Wallpaper carries the original/thumb/preview/frame URLs on
// itself; VariantURLs is the URLs from the wallpaper_variants child rows
// that were deleted in the same transaction. The handler joins them and
// best-effort-deletes the matching MinIO objects.
type HardDeleteResult struct {
	Wallpaper   model.Wallpaper
	VariantURLs []string
}

// AdminHardDelete physically removes a wallpaper row and every child row
// that references it. The caller is responsible for deleting the matching
// MinIO objects — the URLs are surfaced via HardDeleteResult so the
// handler can issue the storage deletes after the DB transaction commits.
//
// Returns gorm.ErrRecordNotFound when the row is gone. No FK constraints
// are declared in init.sql, so child-table cleanup is done explicitly here
// in a single transaction.
func (r *WallpaperRepo) AdminHardDelete(ctx context.Context, id int64) (*HardDeleteResult, error) {
	out := HardDeleteResult{}
	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("id = ?", id).First(&out.Wallpaper).Error; err != nil {
			return err
		}
		// Snapshot variant URLs before the child-row delete kills them —
		// the handler needs these to remove the corresponding MinIO
		// objects (the storage layer doesn't know about the DB rows).
		if err := tx.Table("wallpaper_variants").
			Where("wallpaper_id = ?", id).
			Pluck("url", &out.VariantURLs).Error; err != nil {
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
	return &out, nil
}
