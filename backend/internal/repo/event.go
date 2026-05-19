package repo

import (
	"context"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type EventRepo struct {
	db *gorm.DB
}

func NewEventRepo(db *gorm.DB) *EventRepo {
	return &EventRepo{db: db}
}

func (r *EventRepo) Record(ctx context.Context, wallpaperID int64, eventType string, userID int64, variantID *int64) error {
	event := model.WallpaperEvent{
		WallpaperID: wallpaperID,
		EventType:   eventType,
		UserID:      userID,
		VariantID:   variantID,
	}
	return r.db.WithContext(ctx).Create(&event).Error
}

type TrendingItem struct {
	WallpaperID int64 `json:"wallpaper_id"`
	Score       int64 `json:"score"`
}

// GetTrending ranks wallpapers by an event-weighted score over the window
// [since, now]. When categoryID > 0 the candidate set is narrowed to
// published wallpapers in that category before scoring — without the JOIN
// the "Trending in City" combo would silently fall back to global
// trending and the downstream filter would just trim an already-mixed
// top-N list.
func (r *EventRepo) GetTrending(ctx context.Context, since time.Time, limit int, categoryID int64) ([]int64, error) {
	var items []TrendingItem
	q := r.db.WithContext(ctx).
		Table("wallpaper_events AS we").
		Select(`we.wallpaper_id,
			SUM(CASE WHEN we.event_type = 'download' THEN 3
			         WHEN we.event_type = 'variant_download' THEN 3
			         WHEN we.event_type = 'like' THEN 2
			         ELSE 1 END) AS score`).
		Where("we.created_at >= ?", since)
	if categoryID > 0 {
		q = q.Joins("JOIN wallpapers w ON w.id = we.wallpaper_id").
			Where("w.category_id = ?", categoryID).
			Where("w.status = ?", model.WallpaperStatusPublished)
	}
	err := q.
		Group("we.wallpaper_id").
		Order("score DESC").
		Limit(limit).
		Find(&items).Error
	if err != nil {
		return nil, err
	}
	ids := make([]int64, len(items))
	for i, item := range items {
		ids[i] = item.WallpaperID
	}
	return ids, nil
}

type VariantStat struct {
	VariantID     int64 `json:"variant_id"`
	DownloadCount int64 `json:"download_count"`
}

func (r *EventRepo) GetVariantStats(ctx context.Context, wallpaperID int64) ([]VariantStat, error) {
	var stats []VariantStat
	err := r.db.WithContext(ctx).
		Model(&model.WallpaperEvent{}).
		Select("variant_id, COUNT(*) as download_count").
		Where("wallpaper_id = ? AND event_type = 'variant_download' AND variant_id IS NOT NULL", wallpaperID).
		Group("variant_id").
		Order("download_count DESC").
		Find(&stats).Error
	return stats, err
}
