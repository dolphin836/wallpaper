package repo

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/wallpaper/backend/internal/model"
)

type CollectionBrief struct {
	ID             int64  `json:"id"`
	Title          string `json:"title"`
	WallpaperCount int    `json:"wallpaper_count"`
}

type CollectionRepo struct {
	db *gorm.DB
}

func NewCollectionRepo(db *gorm.DB) *CollectionRepo {
	return &CollectionRepo{db: db}
}

// CountPublic returns the number of publicly-visible collections — used by
// the public /stats endpoint (Discover masthead).
func (r *CollectionRepo) CountPublic(ctx context.Context) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.Collection{}).
		Where("is_public = ?", true).Count(&n).Error
	return n, err
}

func (r *CollectionRepo) Create(ctx context.Context, c *model.Collection) error {
	return r.db.WithContext(ctx).Create(c).Error
}

func (r *CollectionRepo) GetByID(ctx context.Context, id int64) (*model.Collection, error) {
	var c model.Collection
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, cover_url, is_public, wallpaper_count, view_count, like_count, created_at, updated_at").
		Where("id = ?", id).
		First(&c).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

func (r *CollectionRepo) GetBySlug(ctx context.Context, slug string) (*model.Collection, error) {
	var c model.Collection
	err := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, cover_url, is_public, wallpaper_count, view_count, like_count, created_at, updated_at").
		Where("slug = ?", slug).
		First(&c).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}

func (r *CollectionRepo) Update(ctx context.Context, c *model.Collection) error {
	return r.db.WithContext(ctx).
		Model(c).
		Select("title", "description", "cover_url", "is_public").
		Updates(c).Error
}

func (r *CollectionRepo) Delete(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).Where("id = ?", id).Delete(&model.Collection{}).Error
}

func (r *CollectionRepo) List(ctx context.Context, cursor int64, limit int, userID int64) ([]model.Collection, error) {
	query := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, cover_url, is_public, wallpaper_count, view_count, like_count, created_at, updated_at")

	if cursor > 0 {
		query = query.Where("id < ?", cursor)
	}

	if userID > 0 {
		query = query.Where("is_public = ? OR user_id = ?", true, userID)
	} else {
		query = query.Where("is_public = ?", true)
	}

	var collections []model.Collection
	err := query.Order("id DESC").Limit(limit).Find(&collections).Error
	return collections, err
}

func (r *CollectionRepo) ListByUser(ctx context.Context, ownerID int64, cursor int64, limit int) ([]model.Collection, error) {
	query := r.db.WithContext(ctx).
		Select("id, slug, user_id, title, description, cover_url, is_public, wallpaper_count, view_count, like_count, created_at, updated_at").
		Where("user_id = ? AND is_public = ?", ownerID, true)

	if cursor > 0 {
		query = query.Where("id < ?", cursor)
	}

	var collections []model.Collection
	err := query.Order("id DESC").Limit(limit).Find(&collections).Error
	return collections, err
}

func (r *CollectionRepo) AddWallpaper(ctx context.Context, collectionID, wallpaperID int64) error {
	cw := model.CollectionWallpaper{CollectionID: collectionID, WallpaperID: wallpaperID}
	result := r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&cw)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return nil
	}

	if err := r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id = ?", collectionID).
		UpdateColumn("wallpaper_count", gorm.Expr("wallpaper_count + 1")).Error; err != nil {
		return fmt.Errorf("update wallpaper_count: %w", err)
	}

	var col model.Collection
	if err := r.db.WithContext(ctx).Select("cover_url").Where("id = ?", collectionID).First(&col).Error; err == nil && col.CoverURL == "" {
		var wp model.Wallpaper
		if err := r.db.WithContext(ctx).Select("thumb_url").Where("id = ?", wallpaperID).First(&wp).Error; err == nil && wp.ThumbURL != "" {
			if err := r.db.WithContext(ctx).Model(&model.Collection{}).Where("id = ?", collectionID).Update("cover_url", wp.ThumbURL).Error; err != nil {
				return fmt.Errorf("update cover_url: %w", err)
			}
		}
	}

	return nil
}

func (r *CollectionRepo) RemoveWallpaper(ctx context.Context, collectionID, wallpaperID int64) error {
	result := r.db.WithContext(ctx).
		Where("collection_id = ? AND wallpaper_id = ?", collectionID, wallpaperID).
		Delete(&model.CollectionWallpaper{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return nil
	}

	return r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id = ? AND wallpaper_count > 0", collectionID).
		UpdateColumn("wallpaper_count", gorm.Expr("wallpaper_count - 1")).Error
}

func (r *CollectionRepo) ListWallpapers(ctx context.Context, collectionID int64, cursor, limit int) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Table("wallpapers").
		Select("wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title, wallpapers.category_id, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type, wallpapers.dominant_color, wallpapers.status, wallpapers.view_count, wallpapers.like_count, wallpapers.download_count, wallpapers.favorite_count, wallpapers.created_at").
		Joins("JOIN collection_wallpapers cw ON cw.wallpaper_id = wallpapers.id").
		Where("cw.collection_id = ? AND wallpapers.status = ?", collectionID, model.WallpaperStatusPublished)

	if cursor > 0 {
		query = query.Where("cw.id < ?", cursor)
	}

	var wallpapers []model.Wallpaper
	err := query.Order("cw.sort_order ASC, cw.id DESC").Limit(limit).Find(&wallpapers).Error
	return wallpapers, err
}

func (r *CollectionRepo) LikeCollection(ctx context.Context, userID, collectionID int64) error {
	cl := model.CollectionLike{UserID: userID, CollectionID: collectionID}
	result := r.db.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&cl)
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return nil
	}

	return r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id = ?", collectionID).
		UpdateColumn("like_count", gorm.Expr("like_count + 1")).Error
}

func (r *CollectionRepo) UnlikeCollection(ctx context.Context, userID, collectionID int64) error {
	result := r.db.WithContext(ctx).
		Where("user_id = ? AND collection_id = ?", userID, collectionID).
		Delete(&model.CollectionLike{})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return nil
	}

	return r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id = ? AND like_count > 0", collectionID).
		UpdateColumn("like_count", gorm.Expr("like_count - 1")).Error
}

func (r *CollectionRepo) IsLiked(ctx context.Context, userID, collectionID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.CollectionLike{}).
		Where("user_id = ? AND collection_id = ?", userID, collectionID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

var validCollectionCounterFields = map[string]bool{
	"view_count": true,
	"like_count": true,
}

func (r *CollectionRepo) IncrementCounter(ctx context.Context, id int64, field string, delta int) error {
	if !validCollectionCounterFields[field] {
		return fmt.Errorf("invalid counter field: %s", field)
	}
	return r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id = ?", id).
		Update(field, gorm.Expr(field+" + ?", delta)).Error
}

func (r *CollectionRepo) RemoveWallpaperFromAll(ctx context.Context, wallpaperID int64) error {
	var collectionIDs []int64
	if err := r.db.WithContext(ctx).
		Model(&model.CollectionWallpaper{}).
		Where("wallpaper_id = ?", wallpaperID).
		Pluck("collection_id", &collectionIDs).Error; err != nil {
		return fmt.Errorf("find collections: %w", err)
	}
	if len(collectionIDs) == 0 {
		return nil
	}

	if err := r.db.WithContext(ctx).
		Where("wallpaper_id = ?", wallpaperID).
		Delete(&model.CollectionWallpaper{}).Error; err != nil {
		return fmt.Errorf("delete from collections: %w", err)
	}

	if err := r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Where("id IN ? AND wallpaper_count > 0", collectionIDs).
		UpdateColumn("wallpaper_count", gorm.Expr("wallpaper_count - 1")).Error; err != nil {
		return fmt.Errorf("decrement wallpaper_count: %w", err)
	}

	return nil
}

// RecentTilesForCollections returns up to 3 wallpaper tiles per collection
// id, keyed by collection id. Each tile carries thumb_url, preview_url and
// dominant_color so the frontend can do dominant-color placeholder + thumb-
// then-preview progressive load. Ordered by the collection's own sort_order,
// falling back to insertion id desc — same order ListWallpapers uses, so the
// strip the UI shows matches the first page of the detail view.
func (r *CollectionRepo) RecentTilesForCollections(ctx context.Context, ids []int64) (map[int64][]model.CollectionTile, error) {
	out := make(map[int64][]model.CollectionTile, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	type row struct {
		CollectionID  int64  `gorm:"column:collection_id"`
		ThumbURL      string `gorm:"column:thumb_url"`
		PreviewURL    string `gorm:"column:preview_url"`
		DominantColor string `gorm:"column:dominant_color"`
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT collection_id, thumb_url, preview_url, dominant_color FROM (
			SELECT cw.collection_id, w.thumb_url, w.preview_url, w.dominant_color,
			       ROW_NUMBER() OVER (PARTITION BY cw.collection_id
			                          ORDER BY cw.sort_order ASC, cw.id DESC) AS rn
			  FROM collection_wallpapers cw
			  JOIN wallpapers w ON w.id = cw.wallpaper_id
			 WHERE cw.collection_id IN ?
			   AND w.status = 1
			   AND w.thumb_url <> ''
		) ranked
		WHERE rn <= 3
		ORDER BY collection_id, rn
	`, ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.CollectionID] = append(out[r.CollectionID], model.CollectionTile{
			ThumbURL:      r.ThumbURL,
			PreviewURL:    r.PreviewURL,
			DominantColor: r.DominantColor,
		})
	}
	return out, nil
}

func (r *CollectionRepo) ListUserCollections(ctx context.Context, userID int64) ([]CollectionBrief, error) {
	var items []CollectionBrief
	err := r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Select("id, title, wallpaper_count").
		Where("user_id = ?", userID).
		Order("id DESC").
		Find(&items).Error
	return items, err
}

// ListPublicForSitemap returns public collection slugs + updated_at for
// sitemap generation. Filters to non-empty (wallpaper_count > 0) public
// collections — empty ones aren't worth indexing.
func (r *CollectionRepo) ListPublicForSitemap(ctx context.Context) ([]SitemapCollectionEntry, error) {
	var entries []SitemapCollectionEntry
	err := r.db.WithContext(ctx).
		Model(&model.Collection{}).
		Select("slug, updated_at").
		Where("is_public = TRUE AND slug <> '' AND wallpaper_count > 0").
		Order("updated_at DESC").
		Find(&entries).Error
	return entries, err
}

// SitemapCollectionEntry is the slim row shape returned to the SEO handler.
type SitemapCollectionEntry struct {
	Slug      string
	UpdatedAt time.Time
}
