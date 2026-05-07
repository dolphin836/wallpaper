package model

import "time"

type UserLike struct {
	UserID      int64     `gorm:"primaryKey" json:"user_id"`
	WallpaperID int64     `gorm:"primaryKey" json:"wallpaper_id"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

type UserFavorite struct {
	UserID      int64     `gorm:"primaryKey" json:"user_id"`
	WallpaperID int64     `gorm:"primaryKey;index:idx_user_favorites_user" json:"wallpaper_id"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime;index:idx_user_favorites_user" json:"created_at"`
}

type UserDownload struct {
	UserID      int64     `gorm:"primaryKey" json:"user_id"`
	WallpaperID int64     `gorm:"primaryKey;index:idx_user_downloads_user" json:"wallpaper_id"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime;index:idx_user_downloads_user" json:"created_at"`
}
