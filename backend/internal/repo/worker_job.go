package repo

import (
	"context"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type WorkerJobRepo struct {
	db *gorm.DB
}

func NewWorkerJobRepo(db *gorm.DB) *WorkerJobRepo {
	return &WorkerJobRepo{db: db}
}

// Start inserts a new running job row and returns its ID. Workers call this on
// FetchMessage, then Finish() once the work completes — admin console reads
// running rows to see what is in flight right now.
func (r *WorkerJobRepo) Start(ctx context.Context, worker, topic string, refID int64) (int64, error) {
	job := &model.WorkerJob{
		Worker: worker,
		Topic:  topic,
		RefID:  refID,
		Status: model.WorkerJobStatusRunning,
	}
	if err := r.db.WithContext(ctx).Create(job).Error; err != nil {
		return 0, err
	}
	return job.ID, nil
}

func (r *WorkerJobRepo) Finish(ctx context.Context, id int64, status, message string) error {
	if id <= 0 {
		return nil
	}
	now := time.Now()
	updates := map[string]any{
		"status":      status,
		"finished_at": now,
	}
	if message != "" {
		if len(message) > 4000 {
			message = message[:4000]
		}
		updates["message"] = message
	}
	// duration_ms = (now - started_at) in milliseconds. Computed in SQL so we
	// don't have to round-trip the started_at column.
	return r.db.WithContext(ctx).Exec(`
		UPDATE worker_jobs
		   SET status = ?, finished_at = ?, message = COALESCE(NULLIF(?, ''), message),
		       duration_ms = GREATEST(0, EXTRACT(EPOCH FROM (? - started_at)) * 1000)::INT
		 WHERE id = ?
	`, status, now, message, now, id).Error
}

// SweepStale marks rows still "running" but started more than maxAge ago as
// failed. Workers can crash mid-job and leave rows orphaned; admin handler
// invokes this on every read so the UI never shows ancient ghost jobs.
func (r *WorkerJobRepo) SweepStale(ctx context.Context, maxAge time.Duration) error {
	cutoff := time.Now().Add(-maxAge)
	return r.db.WithContext(ctx).Exec(`
		UPDATE worker_jobs
		   SET status = 'failed', finished_at = NOW(),
		       message = CASE WHEN message = '' THEN 'orphaned (worker died mid-job)' ELSE message END,
		       duration_ms = GREATEST(0, EXTRACT(EPOCH FROM (NOW() - started_at)) * 1000)::INT
		 WHERE status = 'running' AND started_at < ?
	`, cutoff).Error
}

type WorkerJobListOpts struct {
	Worker string // image | stats | phash | ""
	Status string // running | done | failed | skipped | ""
	Limit  int
	Cursor int64 // id < cursor
}

func (r *WorkerJobRepo) List(ctx context.Context, opts WorkerJobListOpts) ([]model.WorkerJob, error) {
	q := r.db.WithContext(ctx).Model(&model.WorkerJob{})
	if opts.Worker != "" {
		q = q.Where("worker = ?", opts.Worker)
	}
	if opts.Status != "" {
		q = q.Where("status = ?", opts.Status)
	}
	if opts.Cursor > 0 {
		q = q.Where("id < ?", opts.Cursor)
	}
	limit := opts.Limit
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	var jobs []model.WorkerJob
	err := q.Order("id DESC").Limit(limit).Find(&jobs).Error
	return jobs, err
}

type WorkerSummary struct {
	Worker        string  `json:"worker"`
	Running       int64   `json:"running"`
	DoneLastHour  int64   `json:"done_last_hour"`
	FailedLastDay int64   `json:"failed_last_day"`
	AvgMsLastDay  float64 `json:"avg_ms_last_day"`
}

func (r *WorkerJobRepo) Summary(ctx context.Context) ([]WorkerSummary, error) {
	type row struct {
		Worker        string
		Running       int64
		DoneLastHour  int64
		FailedLastDay int64
		AvgMsLastDay  float64
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT worker,
		       COUNT(*) FILTER (WHERE status = 'running')                                     AS running,
		       COUNT(*) FILTER (WHERE status = 'done'   AND finished_at >= NOW() - INTERVAL '1 hour') AS done_last_hour,
		       COUNT(*) FILTER (WHERE status = 'failed' AND finished_at >= NOW() - INTERVAL '1 day')  AS failed_last_day,
		       COALESCE(AVG(duration_ms) FILTER (WHERE status = 'done' AND finished_at >= NOW() - INTERVAL '1 day'), 0) AS avg_ms_last_day
		  FROM worker_jobs
		 GROUP BY worker
		 ORDER BY worker
	`).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	out := make([]WorkerSummary, len(rows))
	for i, r := range rows {
		out[i] = WorkerSummary(r)
	}
	return out, nil
}
