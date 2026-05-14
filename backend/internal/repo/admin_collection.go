package repo

import (
	"context"
	"strings"

	"github.com/wallpaper/backend/internal/model"
)

type AdminCollectionRow struct {
	model.Collection
	OwnerUsername string `json:"owner_username"`
}

type AdminCollectionListOpts struct {
	Search   string
	OwnerID  int64
	IsPublic *bool
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
                     collections.like_count, collections.created_at, collections.updated_at,
                     COALESCE(u.username, '') AS owner_username`).
		Offset(opts.Offset).Limit(limit).Find(&rows).Error
	return rows, total, err
}

type AdminCollectionUpdate struct {
	Title       *string
	Description *string
	IsPublic    *bool
}

func (r *CollectionRepo) AdminUpdate(ctx context.Context, id int64, u AdminCollectionUpdate) error {
	updates := map[string]any{}
	if u.Title != nil {
		updates["title"] = *u.Title
	}
	if u.Description != nil {
		updates["description"] = *u.Description
	}
	if u.IsPublic != nil {
		updates["is_public"] = *u.IsPublic
	}
	if len(updates) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.Collection{}).Where("id = ?", id).Updates(updates).Error
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
