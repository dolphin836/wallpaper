package repo

import (
	"context"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type AnalyticsRepo struct {
	db *gorm.DB
}

func NewAnalyticsRepo(db *gorm.DB) *AnalyticsRepo {
	return &AnalyticsRepo{db: db}
}

func (r *AnalyticsRepo) Create(ctx context.Context, e *model.AnalyticsEvent) error {
	return r.db.WithContext(ctx).Create(e).Error
}
