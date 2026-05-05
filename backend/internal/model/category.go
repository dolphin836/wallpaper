package model

import "time"

type Category struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	Name      string    `gorm:"size:64;not null;uniqueIndex" json:"name"`
	Slug      string    `gorm:"size:64;not null;uniqueIndex" json:"slug"`
	SortOrder int       `gorm:"not null;default:0" json:"sort_order"`
	CreatedAt time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}
