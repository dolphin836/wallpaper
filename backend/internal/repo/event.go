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

type EventMeta struct {
	Client    string
	IP        string
	UserAgent string
	Referrer  string
	SessionID string
}

func (r *EventRepo) Record(ctx context.Context, wallpaperID int64, eventType string, userID int64, variantID *int64) error {
	return r.RecordWithMeta(ctx, wallpaperID, eventType, userID, variantID, EventMeta{})
}

func (r *EventRepo) RecordWithMeta(ctx context.Context, wallpaperID int64, eventType string, userID int64, variantID *int64, meta EventMeta) error {
	event := model.WallpaperEvent{
		WallpaperID: wallpaperID,
		EventType:   eventType,
		UserID:      userID,
		VariantID:   variantID,
		Client:      meta.Client,
		IP:          meta.IP,
		UserAgent:   meta.UserAgent,
		Referrer:    meta.Referrer,
		SessionID:   meta.SessionID,
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

type WallpaperTrafficRow struct {
	ID          int64     `gorm:"column:id" json:"id"`
	WallpaperID int64     `gorm:"column:wallpaper_id" json:"wallpaper_id"`
	EventType   string    `gorm:"column:event_type" json:"event_type"`
	UserID      int64     `gorm:"column:user_id" json:"user_id"`
	Client      string    `gorm:"column:client" json:"client"`
	IP          string    `gorm:"column:ip" json:"ip"`
	CreatedAt   time.Time `gorm:"column:created_at" json:"created_at"`
	Username    string    `gorm:"column:username" json:"username"`
	Nickname    string    `gorm:"column:nickname" json:"nickname"`
	AvatarURL   string    `gorm:"column:avatar_url" json:"avatar_url"`
	Email       string    `gorm:"column:email" json:"email"`
}

type WallpaperTrafficSummary struct {
	EventType string `gorm:"column:event_type" json:"event_type"`
	Count     int64  `gorm:"column:count" json:"count"`
}

func (r *EventRepo) AdminListWallpaperTraffic(ctx context.Context, wallpaperID int64, eventType string, offset, limit int) ([]WallpaperTrafficRow, int64, []WallpaperTrafficSummary, error) {
	q := r.db.WithContext(ctx).
		Table("wallpaper_events we").
		Where("we.wallpaper_id = ?", wallpaperID)
	cq := r.db.WithContext(ctx).
		Table("wallpaper_events we").
		Where("we.wallpaper_id = ?", wallpaperID)
	if eventType != "" {
		q = q.Where("we.event_type = ?", eventType)
		cq = cq.Where("we.event_type = ?", eventType)
	}

	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, nil, err
	}

	var summary []WallpaperTrafficSummary
	if err := r.db.WithContext(ctx).Raw(`
		SELECT event_type, COUNT(*) AS count
		FROM wallpaper_events
		WHERE wallpaper_id = ?
		  AND event_type IN ('view', 'like', 'favorite', 'download')
		GROUP BY event_type
		ORDER BY event_type
	`, wallpaperID).Scan(&summary).Error; err != nil {
		return nil, 0, nil, err
	}

	var rows []WallpaperTrafficRow
	err := q.Select(`
			we.id, we.wallpaper_id, we.event_type, we.user_id, we.client, we.ip, we.created_at,
			COALESCE(u.username, '') AS username,
			COALESCE(u.nickname, '') AS nickname,
			COALESCE(u.avatar_url, '') AS avatar_url,
			COALESCE(u.email, '') AS email
		`).
		Joins("LEFT JOIN users u ON u.id = we.user_id AND we.user_id <> 0").
		Order("we.created_at DESC, we.id DESC").
		Offset(offset).Limit(limit).
		Scan(&rows).Error
	return rows, total, summary, err
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
