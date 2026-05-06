package model

import "time"

type WallpaperEvent struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	WallpaperID int64     `gorm:"not null;index:idx_we_wallpaper_type" json:"wallpaper_id"`
	EventType   string    `gorm:"size:20;not null;index:idx_we_wallpaper_type" json:"event_type"`
	VariantID   *int64    `gorm:"index" json:"variant_id"`
	UserID      int64     `gorm:"not null;default:0" json:"user_id"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime;index:idx_we_created" json:"created_at"`
}

func (WallpaperEvent) TableName() string {
	return "wallpaper_events"
}
