package model

type Tag struct {
	ID   int64  `gorm:"primaryKey" json:"id"`
	Name string `gorm:"size:32;not null;uniqueIndex" json:"name"`
}

type WallpaperTag struct {
	WallpaperID int64 `gorm:"primaryKey" json:"wallpaper_id"`
	TagID       int64 `gorm:"primaryKey" json:"tag_id"`
}
