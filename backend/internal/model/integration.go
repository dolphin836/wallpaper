package model

import "time"

const IntegrationProviderPinterest = "pinterest"

type ExternalIntegration struct {
	ID           int64      `gorm:"primaryKey" json:"id"`
	Provider     string     `gorm:"size:32;not null;uniqueIndex" json:"provider"`
	AccountID    string     `gorm:"size:128;not null;default:''" json:"account_id"`
	AccountName  string     `gorm:"size:256;not null;default:''" json:"account_name"`
	AccessToken  string     `gorm:"type:text;not null;default:''" json:"-"`
	RefreshToken string     `gorm:"type:text;not null;default:''" json:"-"`
	Scopes       string     `gorm:"type:text;not null;default:''" json:"scopes"`
	TokenType    string     `gorm:"size:32;not null;default:''" json:"token_type"`
	ExpiresAt    *time.Time `json:"expires_at"`
	Metadata     string     `gorm:"type:text;not null;default:'{}'" json:"metadata"`
	CreatedAt    time.Time  `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time  `gorm:"not null;autoUpdateTime" json:"updated_at"`
}

func (ExternalIntegration) TableName() string {
	return "external_integrations"
}

type PinterestPinPost struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	WallpaperID int64     `gorm:"not null;uniqueIndex" json:"wallpaper_id"`
	BoardID     string    `gorm:"size:128;not null;default:''" json:"board_id"`
	BoardName   string    `gorm:"size:256;not null;default:''" json:"board_name"`
	PinID       string    `gorm:"size:128;not null;default:''" json:"pin_id"`
	PinURL      string    `gorm:"size:512;not null;default:''" json:"pin_url"`
	Status      string    `gorm:"size:32;not null;default:'posted'" json:"status"`
	Message     string    `gorm:"type:text;not null;default:''" json:"message"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt   time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
}

func (PinterestPinPost) TableName() string {
	return "pinterest_pin_posts"
}
