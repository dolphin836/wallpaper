package repo

import (
	"context"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type CategoryRepo struct {
	db *gorm.DB
}

func NewCategoryRepo(db *gorm.DB) *CategoryRepo {
	return &CategoryRepo{db: db}
}

func (r *CategoryRepo) List(ctx context.Context) ([]model.Category, error) {
	var categories []model.Category
	err := r.db.WithContext(ctx).
		Select("id, name, slug, sort_order").
		Order("sort_order ASC").
		Find(&categories).Error
	return categories, err
}
