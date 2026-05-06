package model

import "time"

type DeviceProfile struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	Platform  string    `gorm:"size:32;not null;index" json:"platform"`
	Brand     string    `gorm:"size:64;not null" json:"brand"`
	Name      string    `gorm:"size:128;not null" json:"name"`
	Width     int       `gorm:"not null" json:"width"`
	Height    int       `gorm:"not null" json:"height"`
	PPI       int       `gorm:"not null;default:0" json:"ppi"`
	SortOrder int       `gorm:"not null;default:0" json:"sort_order"`
	IsActive  bool      `gorm:"not null;default:true" json:"is_active"`
	CreatedAt time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (DeviceProfile) TableName() string {
	return "device_profiles"
}

type WallpaperVariant struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	WallpaperID int64     `gorm:"not null;index:idx_variants_wallpaper" json:"wallpaper_id"`
	DeviceID    int64     `gorm:"not null;index:idx_variants_wallpaper" json:"device_id"`
	URL         string    `gorm:"size:512;not null" json:"url"`
	Width       int       `gorm:"not null" json:"width"`
	Height      int       `gorm:"not null" json:"height"`
	FileSize      int64     `gorm:"not null;default:0" json:"file_size"`
	DownloadCount int64     `gorm:"not null;default:0" json:"download_count"`
	CreatedAt     time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (WallpaperVariant) TableName() string {
	return "wallpaper_variants"
}

type VariantWithDevice struct {
	WallpaperVariant
	Platform string `json:"platform"`
	Brand    string `json:"brand"`
	DevName  string `json:"device_name"`
}
