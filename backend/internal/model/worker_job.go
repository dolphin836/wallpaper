package model

import "time"

const (
	WorkerJobStatusRunning = "running"
	WorkerJobStatusDone    = "done"
	WorkerJobStatusFailed  = "failed"
	WorkerJobStatusSkipped = "skipped"
)

type WorkerJob struct {
	ID         int64      `gorm:"primaryKey" json:"id"`
	Worker     string     `gorm:"size:32;not null" json:"worker"`
	Topic      string     `gorm:"size:64;not null;default:''" json:"topic"`
	RefID      int64      `gorm:"not null;default:0" json:"ref_id"`
	Status     string     `gorm:"size:16;not null;default:'running'" json:"status"`
	Message    string     `gorm:"type:text;not null;default:''" json:"message"`
	StartedAt  time.Time  `gorm:"not null;autoCreateTime" json:"started_at"`
	FinishedAt *time.Time `json:"finished_at,omitempty"`
	DurationMs int        `gorm:"not null;default:0" json:"duration_ms"`
}
