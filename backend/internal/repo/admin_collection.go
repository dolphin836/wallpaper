package repo

import (
	"context"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/slug"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

type AdminCollectionRow struct {
	model.Collection
	OwnerUsername string `json:"owner_username"`
}

type AdminCollectionListOpts struct {
	Search   string
	OwnerID  int64
	IsPublic *bool
	Kind     *int
	Offset   int
	Limit    int
	Sort     string // newest | wallpapers | likes
}

func (r *CollectionRepo) AdminList(ctx context.Context, opts AdminCollectionListOpts) ([]AdminCollectionRow, int64, error) {
	q := r.db.WithContext(ctx).Table("collections").
		Joins("LEFT JOIN users u ON u.id = collections.user_id")

	cq := r.db.WithContext(ctx).Model(&model.Collection{})

	if opts.OwnerID > 0 {
		q = q.Where("collections.user_id = ?", opts.OwnerID)
		cq = cq.Where("user_id = ?", opts.OwnerID)
	}
	if opts.IsPublic != nil {
		q = q.Where("collections.is_public = ?", *opts.IsPublic)
		cq = cq.Where("is_public = ?", *opts.IsPublic)
	}
	if opts.Kind != nil {
		q = q.Where("collections.kind = ?", *opts.Kind)
		cq = cq.Where("kind = ?", *opts.Kind)
	}
	if s := strings.TrimSpace(opts.Search); s != "" {
		like := "%" + s + "%"
		q = q.Where("collections.title ILIKE ? OR u.username ILIKE ?", like, like)
		cq = cq.Where("title ILIKE ?", like)
	}

	switch opts.Sort {
	case "wallpapers":
		q = q.Order("collections.wallpaper_count DESC, collections.id DESC")
	case "likes":
		q = q.Order("collections.like_count DESC, collections.id DESC")
	default:
		q = q.Order("collections.id DESC")
	}

	limit := opts.Limit
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []AdminCollectionRow
	err := q.Select(`collections.id, collections.slug, collections.user_id, collections.title, collections.description,
                     collections.cover_url, collections.is_public, collections.wallpaper_count, collections.view_count,
                     collections.like_count, collections.kind, collections.year, collections.week,
                     collections.accent_color, collections.created_at, collections.updated_at,
                     COALESCE(u.username, '') AS owner_username`).
		Offset(opts.Offset).Limit(limit).Find(&rows).Error
	return rows, total, err
}

type AdminCollectionUpdate struct {
	Title        *string
	Description  *string
	IsPublic     *bool
	Kind         *int16
	Year         *int16
	Week         *int16
	AccentColor  *string
	WallpaperIDs *[]int64
}

func (r *CollectionRepo) AdminUpdate(ctx context.Context, id int64, u AdminCollectionUpdate) error {
	updates := map[string]any{}
	if u.Title != nil {
		updates["title"] = *u.Title
		updates["title_i18n"] = model.I18n{}
	}
	if u.Description != nil {
		updates["description"] = *u.Description
		updates["description_i18n"] = model.I18n{}
	}
	if u.IsPublic != nil {
		updates["is_public"] = *u.IsPublic
	}
	if u.Kind != nil {
		updates["kind"] = *u.Kind
	}
	if u.Year != nil {
		updates["year"] = *u.Year
	}
	if u.Week != nil {
		updates["week"] = *u.Week
	}
	if u.AccentColor != nil {
		updates["accent_color"] = *u.AccentColor
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if len(updates) > 0 {
			updates["updated_at"] = time.Now()
			if err := tx.Model(&model.Collection{}).Where("id = ?", id).Updates(updates).Error; err != nil {
				return err
			}
		}
		if u.WallpaperIDs != nil {
			if err := replaceCollectionWallpapers(ctx, tx, id, *u.WallpaperIDs); err != nil {
				return err
			}
		}
		return nil
	})
}

type AdminCollectionDetail struct {
	AdminCollectionRow
	Wallpapers []model.Wallpaper `json:"wallpapers"`
}

func (r *CollectionRepo) AdminGet(ctx context.Context, id int64) (*AdminCollectionDetail, error) {
	var row AdminCollectionRow
	err := r.db.WithContext(ctx).Table("collections").
		Joins("LEFT JOIN users u ON u.id = collections.user_id").
		Select(`collections.id, collections.slug, collections.user_id, collections.title, collections.description,
                 collections.cover_url, collections.is_public, collections.wallpaper_count, collections.view_count,
                 collections.like_count, collections.kind, collections.year, collections.week,
                 collections.accent_color, collections.created_at, collections.updated_at,
                 COALESCE(u.username, '') AS owner_username`).
		Where("collections.id = ?", id).
		First(&row).Error
	if err != nil {
		return nil, err
	}
	wallpapers, err := r.AdminListCollectionWallpapers(ctx, id)
	if err != nil {
		return nil, err
	}
	return &AdminCollectionDetail{AdminCollectionRow: row, Wallpapers: wallpapers}, nil
}

func (r *CollectionRepo) AdminCreate(ctx context.Context, c *model.Collection, wallpaperIDs []int64) error {
	if c.Slug == "" {
		c.Slug = slug.Generate(c.Title)
	}
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Create(c).Error; err != nil {
			return err
		}
		return replaceCollectionWallpapers(ctx, tx, c.ID, wallpaperIDs)
	})
}

func (r *CollectionRepo) AdminListCollectionWallpapers(ctx context.Context, id int64) ([]model.Wallpaper, error) {
	var wallpapers []model.Wallpaper
	err := r.db.WithContext(ctx).
		Table("wallpapers").
		Select(`wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title,
		        wallpapers.category_id, wallpapers.thumb_url, wallpapers.preview_url,
		        wallpapers.preview_video_url, wallpapers.width, wallpapers.height,
		        wallpapers.file_size, wallpapers.file_type, wallpapers.dominant_color,
		        wallpapers.color_palette, wallpapers.status, wallpapers.view_count,
		        wallpapers.like_count, wallpapers.download_count, wallpapers.favorite_count,
		        wallpapers.is_dynamic, wallpapers.dynamic_type, wallpapers.is_ai_generated,
		        wallpapers.created_at, wallpapers.updated_at`).
		Joins("JOIN collection_wallpapers cw ON cw.wallpaper_id = wallpapers.id").
		Where("cw.collection_id = ?", id).
		Order("cw.sort_order ASC, cw.id ASC").
		Find(&wallpapers).Error
	return wallpapers, err
}

func replaceCollectionWallpapers(ctx context.Context, tx *gorm.DB, collectionID int64, wallpaperIDs []int64) error {
	ids := dedupePositiveIDs(wallpaperIDs)
	if err := tx.WithContext(ctx).Where("collection_id = ?", collectionID).Delete(&model.CollectionWallpaper{}).Error; err != nil {
		return err
	}
	rows := make([]model.CollectionWallpaper, 0, len(ids))
	for i, id := range ids {
		rows = append(rows, model.CollectionWallpaper{
			CollectionID: collectionID,
			WallpaperID:  id,
			SortOrder:    i,
		})
	}
	if len(rows) > 0 {
		if err := tx.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&rows).Error; err != nil {
			return err
		}
	}
	cover := ""
	if len(ids) > 0 {
		var wp model.Wallpaper
		if err := tx.WithContext(ctx).Select("preview_url, thumb_url").Where("id = ?", ids[0]).First(&wp).Error; err == nil {
			cover = wp.PreviewURL
			if cover == "" {
				cover = wp.ThumbURL
			}
		}
	}
	return tx.WithContext(ctx).Model(&model.Collection{}).
		Where("id = ?", collectionID).
		Updates(map[string]any{
			"wallpaper_count": len(ids),
			"cover_url":       cover,
			"updated_at":      time.Now(),
		}).Error
}

func dedupePositiveIDs(ids []int64) []int64 {
	out := make([]int64, 0, len(ids))
	seen := make(map[int64]bool, len(ids))
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

// AdminDelete hard-deletes the collection and detaches its wallpapers. Likes
// are cleared too so the foreign side doesn't grow stale rows.
func (r *CollectionRepo) AdminDelete(ctx context.Context, id int64) error {
	tx := r.db.WithContext(ctx).Begin()
	if tx.Error != nil {
		return tx.Error
	}
	if err := tx.Where("collection_id = ?", id).Delete(&model.CollectionWallpaper{}).Error; err != nil {
		tx.Rollback()
		return err
	}
	if err := tx.Where("collection_id = ?", id).Delete(&model.CollectionLike{}).Error; err != nil {
		tx.Rollback()
		return err
	}
	if err := tx.Where("id = ?", id).Delete(&model.Collection{}).Error; err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit().Error
}
