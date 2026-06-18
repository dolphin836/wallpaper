package repo

import (
	"context"
	"errors"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/wallpaper/backend/internal/model"
)

type IntegrationRepo struct {
	db *gorm.DB
}

func NewIntegrationRepo(db *gorm.DB) *IntegrationRepo {
	return &IntegrationRepo{db: db}
}

func (r *IntegrationRepo) GetByProvider(ctx context.Context, provider string) (*model.ExternalIntegration, error) {
	var integration model.ExternalIntegration
	err := r.db.WithContext(ctx).
		Where("provider = ?", provider).
		First(&integration).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &integration, nil
}

func (r *IntegrationRepo) Upsert(ctx context.Context, integration *model.ExternalIntegration) error {
	return r.db.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "provider"}},
			DoUpdates: clause.AssignmentColumns([]string{
				"account_id",
				"account_name",
				"access_token",
				"refresh_token",
				"scopes",
				"token_type",
				"expires_at",
				"metadata",
				"updated_at",
			}),
		}).
		Create(integration).Error
}

type PinterestPostRepo struct {
	db *gorm.DB
}

func NewPinterestPostRepo(db *gorm.DB) *PinterestPostRepo {
	return &PinterestPostRepo{db: db}
}

func (r *PinterestPostRepo) GetByWallpaperID(ctx context.Context, wallpaperID int64) (*model.PinterestPinPost, error) {
	var post model.PinterestPinPost
	err := r.db.WithContext(ctx).
		Where("wallpaper_id = ?", wallpaperID).
		First(&post).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &post, nil
}

func (r *PinterestPostRepo) Upsert(ctx context.Context, post *model.PinterestPinPost) error {
	return r.db.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "wallpaper_id"}},
			DoUpdates: clause.AssignmentColumns([]string{
				"board_id",
				"board_name",
				"pin_id",
				"pin_url",
				"status",
				"message",
				"updated_at",
			}),
		}).
		Create(post).Error
}

type RedditPostRepo struct {
	db *gorm.DB
}

func NewRedditPostRepo(db *gorm.DB) *RedditPostRepo {
	return &RedditPostRepo{db: db}
}

func (r *RedditPostRepo) GetByWeek(ctx context.Context, year, week int16) (*model.RedditWeeklyPost, error) {
	var post model.RedditWeeklyPost
	err := r.db.WithContext(ctx).
		Where("year = ? AND week = ?", year, week).
		First(&post).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &post, nil
}

func (r *RedditPostRepo) Upsert(ctx context.Context, post *model.RedditWeeklyPost) error {
	return r.db.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "year"}, {Name: "week"}},
			DoUpdates: clause.AssignmentColumns([]string{
				"collection_id",
				"subreddit",
				"post_id",
				"post_url",
				"title",
				"body",
				"status",
				"message",
				"updated_at",
			}),
		}).
		Create(post).Error
}
