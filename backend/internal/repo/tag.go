package repo

import (
	"context"
	"errors"
	"fmt"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type TagRepo struct {
	db *gorm.DB
}

func NewTagRepo(db *gorm.DB) *TagRepo {
	return &TagRepo{db: db}
}

func (r *TagRepo) GetOrCreate(ctx context.Context, name string) (*model.Tag, error) {
	var tag model.Tag
	err := r.db.WithContext(ctx).
		Select("id, name").
		Where("name = ?", name).
		First(&tag).Error
	if err == nil {
		return &tag, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, err
	}

	tag = model.Tag{Name: name}
	if err := r.db.WithContext(ctx).Create(&tag).Error; err != nil {
		// Unique constraint race: another request created it concurrently
		var existing model.Tag
		if retryErr := r.db.WithContext(ctx).
			Select("id, name").
			Where("name = ?", name).
			First(&existing).Error; retryErr != nil {
			return nil, fmt.Errorf("create tag: %w, retry find: %w", err, retryErr)
		}
		return &existing, nil
	}
	return &tag, nil
}

func (r *TagRepo) GetByWallpaperID(ctx context.Context, wallpaperID int64) ([]model.Tag, error) {
	var tags []model.Tag
	err := r.db.WithContext(ctx).
		Select("tags.id, tags.name").
		Joins("JOIN wallpaper_tags ON tags.id = wallpaper_tags.tag_id").
		Where("wallpaper_tags.wallpaper_id = ?", wallpaperID).
		Find(&tags).Error
	return tags, err
}

func (r *TagRepo) SetWallpaperTags(ctx context.Context, wallpaperID int64, tagIDs []int64) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("wallpaper_id = ?", wallpaperID).
			Delete(&model.WallpaperTag{}).Error; err != nil {
			return err
		}
		if len(tagIDs) == 0 {
			return nil
		}
		wts := make([]model.WallpaperTag, 0, len(tagIDs))
		for _, tagID := range tagIDs {
			wts = append(wts, model.WallpaperTag{
				WallpaperID: wallpaperID,
				TagID:       tagID,
			})
		}
		return tx.Create(&wts).Error
	})
}

func (r *TagRepo) Popular(ctx context.Context, limit int) ([]model.Tag, error) {
	var tags []model.Tag
	err := r.db.WithContext(ctx).
		Select("tags.id, tags.name").
		Joins("JOIN wallpaper_tags ON tags.id = wallpaper_tags.tag_id").
		Group("tags.id, tags.name").
		Order("COUNT(wallpaper_tags.tag_id) DESC").
		Limit(limit).
		Find(&tags).Error
	return tags, err
}
