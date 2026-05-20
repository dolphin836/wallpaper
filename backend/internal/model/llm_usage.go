package model

import "time"

// LLMUsage is one Anthropic Claude API call's token accounting. Inserted
// after every successful Messages.New from pkg/llm.Client.
type LLMUsage struct {
	ID                  int64     `gorm:"primaryKey" json:"id"`
	Purpose             string    `gorm:"size:64;not null" json:"purpose"`
	Model               string    `gorm:"size:64;not null" json:"model"`
	InputTokens         int       `gorm:"not null;default:0" json:"input_tokens"`
	OutputTokens        int       `gorm:"not null;default:0" json:"output_tokens"`
	CacheReadTokens     int       `gorm:"not null;default:0" json:"cache_read_tokens"`
	CacheCreationTokens int       `gorm:"not null;default:0" json:"cache_creation_tokens"`
	CostUSD             float64   `gorm:"type:numeric(12,6);not null;default:0" json:"cost_usd"`
	CreatedAt           time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (LLMUsage) TableName() string {
	return "llm_usage"
}
