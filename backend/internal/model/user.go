package model

import "time"

type User struct {
	ID           int64     `gorm:"primaryKey" json:"id"`
	Username     string    `gorm:"uniqueIndex;size:32;not null" json:"username"`
	Email        string    `gorm:"uniqueIndex;size:255;not null" json:"email"`
	PasswordHash string    `gorm:"size:255;not null" json:"-"`
	Nickname     string    `gorm:"size:64;not null;default:''" json:"nickname"`
	AvatarURL    string    `gorm:"size:512;not null;default:''" json:"avatar_url"`
	Bio          string    `gorm:"size:500;not null;default:''" json:"bio"`
	Status       int16     `gorm:"not null;default:1" json:"status"`
	CreatedAt    time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
}
