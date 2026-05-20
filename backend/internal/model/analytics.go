package model

import (
	"encoding/json"
	"time"
)

type AnalyticsEvent struct {
	ID        int64           `gorm:"primaryKey" json:"id"`
	SessionID string          `gorm:"size:64;not null;index" json:"session_id"`
	UserID    int64           `gorm:"not null;default:0" json:"user_id"`
	EventType string          `gorm:"size:64;not null" json:"event_type"`
	Path      string          `gorm:"size:512;not null;default:''" json:"path"`
	Referrer  string          `gorm:"size:512;not null;default:''" json:"referrer"`
	UserAgent string          `gorm:"size:512;not null;default:''" json:"user_agent"`
	IP        string          `gorm:"size:64;not null;default:''" json:"ip"`
	Country   string          `gorm:"size:8;not null;default:''" json:"country"`
	Props     json.RawMessage `gorm:"type:jsonb;not null;default:'{}'::jsonb" json:"props"`
	CreatedAt time.Time       `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (AnalyticsEvent) TableName() string {
	return "analytics_events"
}
