package model

import "time"

type User struct {
	ID           int64  `gorm:"primaryKey" json:"id"`
	Username     string `gorm:"uniqueIndex;size:32;not null" json:"username"`
	Email        string `gorm:"uniqueIndex;size:255;not null" json:"email"`
	PasswordHash string `gorm:"size:255;not null" json:"-"`
	Nickname     string `gorm:"size:64;not null;default:''" json:"nickname"`
	AvatarURL    string `gorm:"size:512;not null;default:''" json:"avatar_url"`
	Bio          string `gorm:"size:500;not null;default:''" json:"bio"`
	Coins        int64  `gorm:"not null;default:0" json:"coins"`
	Status       int16  `gorm:"not null;default:1" json:"status"`
	IsAdmin      bool   `gorm:"not null;default:false" json:"is_admin"`
	// Per-list privacy flags. Default false → list is private to the
	// owner. Each one is toggled independently from the Profile page.
	LikesPublic       bool      `gorm:"not null;default:false" json:"likes_public"`
	FavoritesPublic   bool      `gorm:"not null;default:false" json:"favorites_public"`
	DownloadsPublic   bool      `gorm:"not null;default:false" json:"downloads_public"`
	RegisterClient    string    `gorm:"size:32;not null;default:''" json:"register_client,omitempty"`
	RegisterSource    string    `gorm:"size:128;not null;default:''" json:"register_source,omitempty"`
	RegisterReferrer  string    `gorm:"size:512;not null;default:''" json:"register_referrer,omitempty"`
	RegisterPath      string    `gorm:"size:512;not null;default:''" json:"register_path,omitempty"`
	RegisterIP        string    `gorm:"size:64;not null;default:''" json:"register_ip,omitempty"`
	RegisterUserAgent string    `gorm:"size:512;not null;default:''" json:"register_user_agent,omitempty"`
	RegisterCountry   string    `gorm:"size:8;not null;default:''" json:"register_country,omitempty"`
	CreatedAt         time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt         time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
}

const (
	CoinTxRegisterBonus  = "register_bonus"
	CoinTxUploadReward   = "upload_reward"
	CoinTxDownloadCost   = "download_cost"
	CoinTxDownloadEarned = "download_earned"
	CoinTxAdminGrant     = "admin_grant"
)

type CoinTransaction struct {
	ID          int64     `gorm:"primaryKey" json:"id"`
	UserID      int64     `gorm:"not null;index:idx_coin_tx_user" json:"user_id"`
	Amount      int64     `gorm:"not null" json:"amount"`
	Balance     int64     `gorm:"not null" json:"balance"`
	TxType      string    `gorm:"size:32;not null" json:"tx_type"`
	RefID       int64     `gorm:"not null;default:0" json:"ref_id"`
	Description string    `gorm:"size:256;not null;default:''" json:"description"`
	CreatedAt   time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

type LoginLog struct {
	ID        int64     `gorm:"primaryKey" json:"id"`
	UserID    int64     `gorm:"not null;index:idx_login_logs_user" json:"user_id"`
	Client    string    `gorm:"size:32;not null;default:''" json:"client"`
	IP        string    `gorm:"size:64;not null;default:''" json:"ip"`
	UserAgent string    `gorm:"size:512;not null;default:''" json:"user_agent"`
	Country   string    `gorm:"size:8;not null;default:''" json:"country"`
	CreatedAt time.Time `gorm:"not null;autoCreateTime;index:idx_login_logs_created" json:"created_at"`
}

func (LoginLog) TableName() string {
	return "login_logs"
}
