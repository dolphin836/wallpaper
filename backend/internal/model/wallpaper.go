package model

import "time"

const (
	WallpaperStatusProcessing int16 = 0
	WallpaperStatusPublished  int16 = 1
	WallpaperStatusFailed     int16 = 2
	WallpaperStatusRemoved    int16 = 3
	WallpaperStatusDuplicate  int16 = 4
)

type Wallpaper struct {
	ID            int64     `gorm:"primaryKey" json:"id"`
	Slug          string    `gorm:"size:160;not null;default:'';uniqueIndex" json:"slug"`
	UserID        int64     `gorm:"not null;index" json:"user_id"`
	CategoryID    int64     `gorm:"not null;default:0;index" json:"category_id"`
	Title         string    `gorm:"size:128;not null;default:''" json:"title"`
	Description   string    `gorm:"size:1000;not null;default:''" json:"description"`
	OriginalURL   string    `gorm:"size:512;not null" json:"original_url"`
	ThumbURL      string    `gorm:"size:512;not null;default:''" json:"thumb_url"`
	PreviewURL    string    `gorm:"size:512;not null;default:''" json:"preview_url"`
	Width         int       `gorm:"not null;default:0" json:"width"`
	Height        int       `gorm:"not null;default:0" json:"height"`
	FileSize      int64     `gorm:"not null;default:0" json:"file_size"`
	FileType      string    `gorm:"size:64;not null;default:''" json:"file_type"`
	DominantColor string    `gorm:"size:7;not null;default:''" json:"dominant_color"`
	ColorPalette  string    `gorm:"size:64;not null;default:''" json:"color_palette"`
	Status        int16     `gorm:"not null;default:0;index:idx_wallpapers_status_created" json:"status"`
	ViewCount     int64     `gorm:"not null;default:0" json:"view_count"`
	LikeCount     int64     `gorm:"not null;default:0" json:"like_count"`
	DownloadCount int64     `gorm:"not null;default:0" json:"download_count"`
	FavoriteCount int64     `gorm:"not null;default:0" json:"favorite_count"`
	IsDynamic     bool      `gorm:"not null;default:false" json:"is_dynamic"`
	DynamicType   string    `gorm:"size:16;not null;default:''" json:"dynamic_type"`
	FrameURLs     string    `gorm:"type:text;not null;default:''" json:"frame_urls"`
	Phash         int64     `gorm:"not null;default:0" json:"-"`
	QualityFlag   string    `gorm:"size:32;not null;default:''" json:"quality_flag,omitempty"`
	QualityNotes  string    `gorm:"type:text;not null;default:''" json:"quality_notes,omitempty"`
	CreatedAt     time.Time `gorm:"not null;autoCreateTime;index:idx_wallpapers_status_created" json:"created_at"`
	UpdatedAt     time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
}
