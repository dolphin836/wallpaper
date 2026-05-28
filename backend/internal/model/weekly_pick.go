package model

import "time"

// WeeklyPick is one of the 10 wallpapers selected for a given ISO week's
// "Friday Drop". The table doubles as the historical archive — a
// wallpaper that appears once is excluded from every subsequent pick so
// users always see fresh selections.
type WeeklyPick struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	Year        int16     `gorm:"not null" json:"year"`
	Week        int16     `gorm:"not null" json:"week"`
	WallpaperID int64     `gorm:"not null" json:"wallpaper_id"`
	SortOrder   int       `gorm:"not null;default:0" json:"sort_order"`
	// IsHero marks the single "main image" of a week — drives the home
	// page hero and is the only pick whose original_url is exposed
	// publicly. At most one per (year, week); see partial unique index.
	IsHero    bool      `gorm:"not null;default:false" json:"is_hero"`
	CreatedAt time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (WeeklyPick) TableName() string { return "weekly_picks" }
