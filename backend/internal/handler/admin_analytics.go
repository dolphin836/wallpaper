package handler

import (
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/response"
	"github.com/wallpaper/backend/internal/repo"
)

// AnalyticsOverview is the single payload the admin Analytics page
// loads. Bundles the daily timeseries, top breakdowns, and totals for
// the current + previous period (the dashboard uses the previous-period
// number to render delta-vs-last-week arrows).
type AnalyticsOverview struct {
	Days            int               `json:"days"`
	Daily           []repo.DayBucket  `json:"daily"`
	Totals          repo.Totals       `json:"totals"`
	Previous        repo.Totals       `json:"previous"`
	Countries       []repo.LabelCount `json:"countries"`
	Sources         []sourceCount     `json:"sources"`
	Paths           []repo.LabelCount `json:"paths"`
	Clients         []repo.LabelCount `json:"clients"`
	ClientDownloads []repo.LabelCount `json:"client_downloads"`
}

// sourceCount groups one or more referrer hostnames under a friendly
// label like "Google" or "Pinterest". Hosts is included so the admin
// dashboard can show a breakdown ("Google · t.co · …") on hover.
type sourceCount struct {
	Source string   `json:"source"`
	Count  int64    `json:"count"`
	Hosts  []string `json:"hosts,omitempty"`
}

// referrerSource maps a host (or hostname suffix) to a friendly source
// label for the dashboard. Order doesn't matter; longest-match wins
// during classification (so `google.co.jp` doesn't collide with
// `google.com` if we ever specialize).
//
// New entries: prefer the bare second-level domain, matching by suffix
// covers most international TLDs (google.com / google.co.jp / google.de).
var referrerSourceTable = []struct {
	suffix string
	label  string
}{
	{"google.", "Google"},
	{"bing.com", "Bing"},
	{"baidu.com", "Baidu"},
	{"so.com", "360 Search"},
	{"sogou.com", "Sogou"},
	{"yandex.", "Yandex"},
	{"duckduckgo.com", "DuckDuckGo"},
	{"yahoo.com", "Yahoo"},

	{"pinterest.", "Pinterest"},
	{"pin.it", "Pinterest"},

	{"twitter.com", "Twitter/X"},
	{"x.com", "Twitter/X"},
	{"t.co", "Twitter/X"},

	{"facebook.com", "Facebook"},
	{"l.facebook.com", "Facebook"},
	{"fb.me", "Facebook"},

	{"instagram.com", "Instagram"},
	{"reddit.com", "Reddit"},
	{"news.ycombinator.com", "Hacker News"},
	{"linkedin.com", "LinkedIn"},

	{"weixin.qq.com", "WeChat"},
	{"weibo.com", "Weibo"},
	{"t.bilibili.com", "Bilibili"},
	{"bilibili.com", "Bilibili"},
	{"zhihu.com", "Zhihu"},

	{"github.com", "GitHub"},
}

func classifyReferrer(host string) string {
	if host == "" {
		return "Direct"
	}
	h := strings.ToLower(host)
	// Strip leading "www." so google.com / www.google.com bucket together.
	h = strings.TrimPrefix(h, "www.")
	for _, e := range referrerSourceTable {
		if strings.HasSuffix(e.suffix, ".") {
			// Suffix entries like "google." match google.com / google.de /
			// google.co.jp etc. Anchor at start of a host segment so
			// "evilgoogle.com" doesn't sneak in.
			if strings.HasPrefix(h, e.suffix) || strings.Contains(h, "."+e.suffix) {
				return e.label
			}
		} else if h == e.suffix || strings.HasSuffix(h, "."+e.suffix) {
			return e.label
		}
	}
	return "Other"
}

// ownHosts is the list of hostnames considered "same-site" — referrers
// from these get filtered out of the source breakdown so we don't see
// our own pages credit themselves as a traffic source.
var ownHosts = []string{
	"wallpaperexchange.com",
	"www.wallpaperexchange.com",
	"api.wallpaperexchange.com",
	"wallpaper.haibing.site",
}

func (h *AdminHandler) GetAnalytics(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	days := parseIntDefault(r.URL.Query().Get("days"), 7)
	if days <= 0 {
		days = 7
	}
	if days > 90 {
		days = 90
	}

	now := time.Now().UTC()
	curStart := now.AddDate(0, 0, -days)
	prevStart := now.AddDate(0, 0, -2*days)

	daily, err := h.analyticsRepo.DailyTimeseries(ctx, days)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: timeseries failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	totals, err := h.analyticsRepo.Totals(ctx, curStart, now)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: totals failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	prev, err := h.analyticsRepo.Totals(ctx, prevStart, curStart)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: previous totals failed", "error", err)
		// Soft-fail — the dashboard renders without a delta arrow.
		prev = repo.Totals{}
	}
	countries, err := h.analyticsRepo.TopCountries(ctx, days, 10)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: countries failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	paths, err := h.analyticsRepo.TopPaths(ctx, days, 10)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: paths failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	clients, err := h.analyticsRepo.ClientBreakdown(ctx, days, 10)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: clients failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	clientDownloads, err := h.analyticsRepo.ClientDownloads(ctx, days, 10)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: client downloads failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	// Pull a generous referrer pool; classification collapses many hosts
	// into a single bucket so we want headroom.
	refs, err := h.analyticsRepo.TopReferrerHosts(ctx, days, 100, ownHosts)
	if err != nil {
		slog.ErrorContext(ctx, "analytics: referrers failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}

	// Classify referrer hosts into named sources and merge counts.
	bySource := map[string]*sourceCount{}
	order := []string{}
	for _, row := range refs {
		label := classifyReferrer(row.Host)
		if s, ok := bySource[label]; ok {
			s.Count += row.Count
			if row.Host != "" {
				s.Hosts = append(s.Hosts, row.Host)
			}
		} else {
			sc := &sourceCount{Source: label, Count: row.Count}
			if row.Host != "" {
				sc.Hosts = []string{row.Host}
			}
			bySource[label] = sc
			order = append(order, label)
		}
	}
	sources := make([]sourceCount, 0, len(order))
	for _, label := range order {
		sources = append(sources, *bySource[label])
	}
	// Sort descending by count (stable enough — small N).
	for i := 1; i < len(sources); i++ {
		for j := i; j > 0 && sources[j].Count > sources[j-1].Count; j-- {
			sources[j], sources[j-1] = sources[j-1], sources[j]
		}
	}
	if len(sources) > 10 {
		sources = sources[:10]
	}

	response.OK(w, AnalyticsOverview{
		Days:            days,
		Daily:           daily,
		Totals:          totals,
		Previous:        prev,
		Countries:       countries,
		Sources:         sources,
		Paths:           paths,
		Clients:         clients,
		ClientDownloads: clientDownloads,
	})
}

// GetLLMCost summarises the local llm_usage ledger — every Anthropic
// API call writes one row with token counts + computed USD cost, so
// SUM(cost_usd) over a window is our running spend. This sidesteps the
// Anthropic Admin API entirely (which requires an Org Owner key we
// don't have).
func (h *AdminHandler) GetLLMCost(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	summary, err := h.llmUsageRepo.Summary(ctx)
	if err != nil {
		slog.ErrorContext(ctx, "llm cost: summary failed", "error", err)
		response.Error(w, http.StatusInternalServerError, errcode.ErrInternal)
		return
	}
	response.OK(w, map[string]any{
		"configured": true, // local ledger is always available
		"summary":    summary,
	})
}
