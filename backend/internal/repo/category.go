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

// GetByID returns the category with the given ID, or (nil, nil) when
// the row doesn't exist. Used by SEO breadcrumb rendering so we don't
// hard-fail wallpaper OG pages when the FK has been orphaned.
func (r *CategoryRepo) GetByID(ctx context.Context, id int64) (*model.Category, error) {
	var c model.Category
	err := r.db.WithContext(ctx).
		Select("id, name, slug, sort_order").
		Where("id = ?", id).
		First(&c).Error
	if err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return &c, nil
}
