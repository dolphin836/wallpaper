package model

import "time"

type Category struct {
	ID   int64  `gorm:"primaryKey" json:"id"`
	Name string `gorm:"size:64;not null;uniqueIndex" json:"name"`
	// Hand-maintained translations, seeded in init.sql (categories are
	// fixed seed data with no mutation endpoint).
	NameI18n  I18n      `gorm:"column:name_i18n;type:jsonb" json:"-"`
	Slug      string    `gorm:"size:64;not null;uniqueIndex" json:"slug"`
	SortOrder int       `gorm:"not null;default:0" json:"sort_order"`
	CreatedAt time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}
