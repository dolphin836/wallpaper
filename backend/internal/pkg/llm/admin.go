package llm

// Anthropic Admin API integration — pulls organisation-level cost data
// so the admin dashboard can surface how much we've spent on Claude this
// week / month without anyone having to open the Anthropic console.
//
// Note: Anthropic does *not* expose a "remaining credit balance"
// endpoint. The Cost Report is the closest signal — subtract cumulative
// spend from your last top-up amount to estimate remaining credits.
//
// Auth: Admin API uses a *separate* API key from the regular Messages
// key (console → Settings → Admin Keys). Same X-Api-Key header.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"sync"
	"time"
)

const (
	adminBaseURL  = "https://api.anthropic.com/v1/organizations"
	adminVersion  = "2023-06-01"
	adminTimeout  = 15 * time.Second
	costCacheTTL  = 1 * time.Hour // Admin API is slow + rate-limited; admin reloads dashboard often
)

// AdminClient hits the Admin API. Stateless apart from an HTTP client +
// an in-memory cost-report cache (the admin dashboard polls this on
// every page load; caching keeps us under any rate limits).
type AdminClient struct {
	apiKey string
	http   *http.Client

	mu        sync.Mutex
	cached    *CostSummary
	cachedAt  time.Time
}

// NewAdminClient returns a client. apiKey may be empty — Enabled()
// reports false in that case and CostSummary() returns an error.
func NewAdminClient(apiKey string) *AdminClient {
	return &AdminClient{
		apiKey: apiKey,
		http:   &http.Client{Timeout: adminTimeout},
	}
}

func (c *AdminClient) Enabled() bool { return c != nil && c.apiKey != "" }

// CostSummary is the slim shape the admin dashboard renders. Amounts
// are USD (the Anthropic API returns "lowest currency units" — cents —
// as decimal strings; we normalise to dollars here).
type CostSummary struct {
	Last7DaysUSD  float64    `json:"last_7d_usd"`
	Last30DaysUSD float64    `json:"last_30d_usd"`
	TodayUSD      float64    `json:"today_usd"`
	Daily         []DailyCost `json:"daily"` // last 30 days, oldest → newest
	UpdatedAt     time.Time  `json:"updated_at"`
}

type DailyCost struct {
	Day string  `json:"day"` // YYYY-MM-DD UTC
	USD float64 `json:"usd"`
}

// rawCostReport mirrors the Anthropic API response shape. Only the
// fields we actually consume are kept — others left to the JSON decoder
// to ignore.
type rawCostReport struct {
	Data []struct {
		StartingAt string `json:"starting_at"`
		EndingAt   string `json:"ending_at"`
		Results    []struct {
			Amount   string `json:"amount"`
			Currency string `json:"currency"`
		} `json:"results"`
	} `json:"data"`
	HasMore  bool   `json:"has_more"`
	NextPage string `json:"next_page"`
}

// CostSummary returns the 30-day cost rollup. Cached for costCacheTTL.
// Returns the cached value (if any) on a fresh upstream error so the
// dashboard doesn't flicker when Anthropic has a transient blip.
func (c *AdminClient) CostSummary(ctx context.Context) (*CostSummary, error) {
	if !c.Enabled() {
		return nil, errors.New("anthropic admin api key not configured")
	}

	c.mu.Lock()
	if c.cached != nil && time.Since(c.cachedAt) < costCacheTTL {
		out := *c.cached
		c.mu.Unlock()
		return &out, nil
	}
	c.mu.Unlock()

	now := time.Now().UTC()
	starting := now.AddDate(0, 0, -30).Truncate(24 * time.Hour)

	summary, err := c.fetchCostSummary(ctx, starting, now)
	if err != nil {
		// On error, surface stale cache if we have one — better than
		// blanking the dashboard.
		c.mu.Lock()
		if c.cached != nil {
			out := *c.cached
			c.mu.Unlock()
			return &out, nil
		}
		c.mu.Unlock()
		return nil, err
	}

	c.mu.Lock()
	c.cached = summary
	c.cachedAt = time.Now()
	c.mu.Unlock()
	return summary, nil
}

func (c *AdminClient) fetchCostSummary(ctx context.Context, starting, ending time.Time) (*CostSummary, error) {
	q := url.Values{}
	q.Set("starting_at", starting.Format(time.RFC3339))
	q.Set("ending_at", ending.Format(time.RFC3339))
	q.Set("bucket_width", "1d")
	q.Set("limit", "31")

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, adminBaseURL+"/cost_report?"+q.Encode(), nil)
	if err != nil {
		return nil, fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("X-Api-Key", c.apiKey)
	req.Header.Set("anthropic-version", adminVersion)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, fmt.Errorf("admin api request: %w", err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("admin api %d: %s", resp.StatusCode, string(body))
	}
	var raw rawCostReport
	if err := json.Unmarshal(body, &raw); err != nil {
		return nil, fmt.Errorf("decode response: %w", err)
	}

	today := time.Now().UTC().Format("2006-01-02")
	last7Start := time.Now().UTC().AddDate(0, 0, -7)

	out := &CostSummary{UpdatedAt: time.Now().UTC()}
	for _, bucket := range raw.Data {
		var sum float64
		for _, r := range bucket.Results {
			cents, parseErr := strconv.ParseFloat(r.Amount, 64)
			if parseErr != nil {
				continue
			}
			// API returns cents as a decimal string — convert to dollars.
			sum += cents / 100.0
		}
		dayStr := bucket.StartingAt[:10] // YYYY-MM-DD slice
		out.Daily = append(out.Daily, DailyCost{Day: dayStr, USD: sum})
		out.Last30DaysUSD += sum

		bucketStart, _ := time.Parse(time.RFC3339, bucket.StartingAt)
		if !bucketStart.Before(last7Start) {
			out.Last7DaysUSD += sum
		}
		if dayStr == today {
			out.TodayUSD = sum
		}
	}
	return out, nil
}
