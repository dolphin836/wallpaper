// Package indexnow implements the IndexNow protocol (indexnow.org) used
// by Bing, Yandex, and Seznam for instant URL indexing. We use the
// shared api.indexnow.org endpoint so submitting once notifies every
// participating search engine in a single call.
//
// Spec: https://www.indexnow.org/documentation
package indexnow

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	endpoint       = "https://api.indexnow.org/IndexNow"
	maxURLsPerCall = 10000 // protocol cap; we never approach this in practice
	clientTimeout  = 15 * time.Second
)

type Client struct {
	http        *http.Client
	key         string
	keyLocation string // public URL returning the key text
	host        string // bare host (e.g. wallpaperexchange.com)
	siteOrigin  string // scheme://host (e.g. https://wallpaperexchange.com)
}

// New builds a client. siteURL must be the canonical https://host origin
// the URLs are submitted under. key is the IndexNow secret string; if
// empty, Submit becomes a no-op so the rest of the pipeline can run in
// non-production environments without complaint.
func New(key, siteURL string) (*Client, error) {
	if key == "" {
		return &Client{}, nil
	}
	u, err := url.Parse(siteURL)
	if err != nil {
		return nil, fmt.Errorf("invalid site url: %w", err)
	}
	if u.Host == "" {
		return nil, errors.New("site url missing host")
	}
	return &Client{
		http:        &http.Client{Timeout: clientTimeout},
		key:         key,
		host:        u.Host,
		siteOrigin:  strings.TrimSuffix(u.Scheme+"://"+u.Host, "/"),
		keyLocation: strings.TrimSuffix(u.Scheme+"://"+u.Host, "/") + "/" + key + ".txt",
	}, nil
}

// Enabled reports whether the client will actually call out (i.e. has a
// configured key). Callers can use this to avoid wasted work building a
// URL list when the integration isn't configured.
func (c *Client) Enabled() bool { return c != nil && c.key != "" }

// Submit posts up to maxURLsPerCall URLs to IndexNow. Each URL must be
// on the same host as c.host; anything else is silently dropped (the
// spec requires it and the endpoint will 422 otherwise). On 2xx the
// request returns nil; non-2xx responses are reported but treated as
// recoverable — the caller should log and move on.
func (c *Client) Submit(ctx context.Context, urls []string) error {
	if !c.Enabled() {
		return nil
	}

	clean := make([]string, 0, len(urls))
	seen := make(map[string]bool, len(urls))
	for _, raw := range urls {
		u, err := url.Parse(raw)
		if err != nil || u.Host != c.host || seen[raw] {
			continue
		}
		seen[raw] = true
		clean = append(clean, raw)
		if len(clean) >= maxURLsPerCall {
			break
		}
	}
	if len(clean) == 0 {
		return nil
	}

	payload := map[string]any{
		"host":        c.host,
		"key":         c.key,
		"keyLocation": c.keyLocation,
		"urlList":     clean,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal payload: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("post: %w", err)
	}
	defer resp.Body.Close()

	// 200 = accepted, 202 = accepted, 200/202 are the success codes.
	// 400/422 mean a malformed payload (logic bug on our side); 429 is
	// throttle (rare). Surface everything else for the caller to log.
	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return nil
	}
	return fmt.Errorf("indexnow returned %d", resp.StatusCode)
}

// SubmitAsync schedules Submit in a goroutine and logs the outcome. Use
// this from request-handler hot paths where the caller doesn't want to
// wait for the search-engine round-trip.
func (c *Client) SubmitAsync(urls []string) {
	if !c.Enabled() || len(urls) == 0 {
		return
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), clientTimeout)
		defer cancel()
		if err := c.Submit(ctx, urls); err != nil {
			slog.WarnContext(ctx, "indexnow submit failed", "urls", len(urls), "error", err)
		} else {
			slog.InfoContext(ctx, "indexnow submitted", "urls", len(urls))
		}
	}()
}

// Key returns the configured key text so handler code can serve the
// verification file content without reaching into the client internals.
func (c *Client) Key() string { return c.key }
