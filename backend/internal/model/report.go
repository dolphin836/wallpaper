package model

import "time"

const (
	ReportStatusOpen     int16 = 0
	ReportStatusResolved int16 = 1
	ReportStatusRejected int16 = 2
)

type Report struct {
	ID             int64     `gorm:"primaryKey" json:"id"`
	WallpaperID    int64     `gorm:"not null;index" json:"wallpaper_id"`
	ReporterUserID int64     `gorm:"not null" json:"reporter_user_id"`
	Reason         string    `gorm:"size:32;not null" json:"reason"`
	Note           string    `gorm:"type:text;not null;default:''" json:"note"`
	Status         int16     `gorm:"not null;default:0" json:"status"`
	CreatedAt      time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}
