package model

import "time"

type WallpaperEvent struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	WallpaperID int64     `gorm:"not null;index:idx_we_wallpaper_type" json:"wallpaper_id"`
	EventType   string    `gorm:"size:20;not null;index:idx_we_wallpaper_type" json:"event_type"`
	VariantID   *int64    `gorm:"index" json:"variant_id"`
	UserID      int64     `gorm:"not null;default:0" json:"user_id"`
	Client      string    `gorm:"size:32;not null;default:''" json:"client"`
	IP          string    `gorm:"size:64;not null;default:''" json:"ip"`
	UserAgent   string    `gorm:"size:512;not null;default:''" json:"user_agent"`
	Referrer    string    `gorm:"size:512;not null;default:''" json:"referrer"`
	SessionID   string    `gorm:"size:64;not null;default:''" json:"session_id"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime;index:idx_we_created" json:"created_at"`
}

func (WallpaperEvent) TableName() string {
	return "wallpaper_events"
}
