package repo

import (
	"context"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/llm"
)

// LLMUsageRepo writes and aggregates the per-call ledger. Implements
// llm.Recorder so pkg/llm.Client can hand the response usage off without
// importing repo/ (that would be a cyclic dep).
type LLMUsageRepo struct {
	db *gorm.DB
}

func NewLLMUsageRepo(db *gorm.DB) *LLMUsageRepo {
	return &LLMUsageRepo{db: db}
}

// Record implements llm.Recorder. Cost is computed at insert time so the
// admin dashboard's SUM(cost_usd) is correct even if pricing changes
// later — we want historical rows to reflect what we *would* have paid
// at the time of the call, not the latest price list.
func (r *LLMUsageRepo) Record(purpose, model_ string, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens int) error {
	costUSD := llm.CostUSD(model_, inputTokens, outputTokens, cacheReadTokens, cacheCreationTokens)
	row := &model.LLMUsage{
		Purpose:             purpose,
		Model:               model_,
		InputTokens:         inputTokens,
		OutputTokens:        outputTokens,
		CacheReadTokens:     cacheReadTokens,
		CacheCreationTokens: cacheCreationTokens,
		CostUSD:             costUSD,
	}
	return r.db.Create(row).Error
}

// LLMDailyCost is one bucket of the cost timeseries.
type LLMDailyCost struct {
	Day string  `gorm:"column:day"  json:"day"` // YYYY-MM-DD UTC
	USD float64 `gorm:"column:usd"  json:"usd"`
}

// LLMCostSummary mirrors the legacy Admin-API shape the dashboard
// already consumes — switching the data source is invisible to the SPA.
type LLMCostSummary struct {
	Last7DaysUSD  float64        `json:"last_7d_usd"`
	Last30DaysUSD float64        `json:"last_30d_usd"`
	TodayUSD      float64        `json:"today_usd"`
	TotalCalls    int64          `json:"total_calls"`     // total rows in window
	ByPurpose     []LabelUSD     `json:"by_purpose"`      // 30-day breakdown
	Daily         []LLMDailyCost `json:"daily"`           // last 30 days, oldest→newest
	UpdatedAt     time.Time      `json:"updated_at"`
}

// LabelUSD is purpose/model → cost mapping for the breakdown card.
type LabelUSD struct {
	Label string  `gorm:"column:label" json:"label"`
	USD   float64 `gorm:"column:usd"   json:"usd"`
	Count int64   `gorm:"column:count" json:"count"`
}

// Summary returns the 30-day cost rollup used by the admin dashboard.
// All slices are guaranteed non-nil (empty slice rather than nil) so the
// SPA never has to defend against JSON null.
func (r *LLMUsageRepo) Summary(ctx context.Context) (*LLMCostSummary, error) {
	now := time.Now().UTC()
	start30 := now.AddDate(0, 0, -30).Truncate(24 * time.Hour)
	start7 := now.AddDate(0, 0, -7)
	startToday := now.Truncate(24 * time.Hour)

	out := &LLMCostSummary{
		UpdatedAt: now,
		Daily:     []LLMDailyCost{},
		ByPurpose: []LabelUSD{},
	}

	// 30d total + total call count in one query.
	type aggRow struct {
		USD   float64
		Calls int64
	}
	var agg aggRow
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(cost_usd), 0) AS usd, COUNT(*) AS calls
		FROM llm_usage WHERE created_at >= ?
	`, start30).Scan(&agg).Error; err != nil {
		return nil, err
	}
	out.Last30DaysUSD = agg.USD
	out.TotalCalls = agg.Calls

	// 7d + today (small queries, two more roundtrips is fine).
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(cost_usd), 0) FROM llm_usage WHERE created_at >= ?
	`, start7).Row().Scan(&out.Last7DaysUSD); err != nil {
		return nil, err
	}
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(SUM(cost_usd), 0) FROM llm_usage WHERE created_at >= ?
	`, startToday).Row().Scan(&out.TodayUSD); err != nil {
		return nil, err
	}

	// Daily timeseries — gap-fill so days with zero calls still show 0
	// instead of dropping out of the series (and breaking the sparkline).
	var daily []LLMDailyCost
	if err := r.db.WithContext(ctx).Raw(`
		WITH days AS (
			SELECT generate_series(?::date, CURRENT_DATE, '1 day'::interval)::date AS day
		)
		SELECT
			to_char(d.day, 'YYYY-MM-DD')       AS day,
			COALESCE(SUM(u.cost_usd), 0)        AS usd
		FROM days d
		LEFT JOIN llm_usage u ON date_trunc('day', u.created_at)::date = d.day
		GROUP BY d.day
		ORDER BY d.day ASC
	`, start30).Scan(&daily).Error; err != nil {
		return nil, err
	}
	if daily != nil {
		out.Daily = daily
	}

	// Per-purpose breakdown (30d window).
	var purposes []LabelUSD
	if err := r.db.WithContext(ctx).Raw(`
		SELECT purpose AS label, SUM(cost_usd) AS usd, COUNT(*) AS count
		FROM llm_usage
		WHERE created_at >= ?
		GROUP BY purpose
		ORDER BY usd DESC
	`, start30).Scan(&purposes).Error; err != nil {
		return nil, err
	}
	if purposes != nil {
		out.ByPurpose = purposes
	}

	return out, nil
}
