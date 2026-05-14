package repo

import (
	"context"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type ReportRepo struct {
	db *gorm.DB
}

func NewReportRepo(db *gorm.DB) *ReportRepo {
	return &ReportRepo{db: db}
}

func (r *ReportRepo) Create(ctx context.Context, report *model.Report) error {
	return r.db.WithContext(ctx).Create(report).Error
}
