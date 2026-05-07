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
	Coins        int64     `gorm:"not null;default:0" json:"coins"`
	Status       int16     `gorm:"not null;default:1" json:"status"`
	CreatedAt    time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt    time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
}

const (
	CoinTxRegisterBonus  = "register_bonus"
	CoinTxUploadReward   = "upload_reward"
	CoinTxDownloadCost   = "download_cost"
	CoinTxDownloadEarned = "download_earned"
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
