package middleware

import (
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"

	"github.com/wallpaper/backend/internal/model"
	jwtpkg "github.com/wallpaper/backend/internal/pkg/jwt"
	"github.com/wallpaper/backend/internal/repo"
)

// APIRequestRecorder keeps request analytics off the response path. Events are
// buffered and inserted in batches so detailed endpoint telemetry does not add
// a database round-trip to every user-facing API call.
type APIRequestRecorder struct {
	repo      *repo.AnalyticsRepo
	jwtSecret string
	events    chan model.AnalyticsEvent
	stop      chan struct{}
	done      chan struct{}
	closeOnce sync.Once
	dropped   atomic.Int64
}

func NewAPIRequestRecorder(analyticsRepo *repo.AnalyticsRepo, jwtSecret string) *APIRequestRecorder {
	recorder := &APIRequestRecorder{
		repo:      analyticsRepo,
		jwtSecret: jwtSecret,
		events:    make(chan model.AnalyticsEvent, 2048),
		stop:      make(chan struct{}),
		done:      make(chan struct{}),
	}
	go recorder.run()
	return recorder
}

func (a *APIRequestRecorder) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()
		rw := &analyticsResponseWriter{ResponseWriter: w, statusCode: http.StatusOK}
		next.ServeHTTP(rw, r)

		route := chi.RouteContext(r.Context()).RoutePattern()
		if route == "" {
			route = "/api/v1/unmatched"
		}
		client := apiRequestClient(r)
		durationMS := time.Since(start).Milliseconds()
		props, err := json.Marshal(map[string]any{
			"method":         r.Method,
			"route":          route,
			"status":         rw.statusCode,
			"duration_ms":    durationMS,
			"request_bytes":  maxInt64(r.ContentLength, 0),
			"response_bytes": rw.bytesWritten,
			"client":         client,
			"request_id":     chimiddleware.GetReqID(r.Context()),
		})
		if err != nil {
			return
		}

		event := model.AnalyticsEvent{
			SessionID: truncateAnalyticsValue(r.Header.Get("X-Wallpaper-Session"), 64),
			UserID:    requestUserID(r, a.jwtSecret),
			EventType: "api_request",
			Path:      truncateAnalyticsValue(route, 512),
			Referrer:  truncateAnalyticsValue(r.Referer(), 512),
			UserAgent: truncateAnalyticsValue(r.UserAgent(), 512),
			IP:        truncateAnalyticsValue(apiRequestIP(r), 64),
			Country:   strings.ToUpper(truncateAnalyticsValue(r.Header.Get("CF-IPCountry"), 8)),
			Props:     props,
			CreatedAt: time.Now().UTC(),
		}
		select {
		case a.events <- event:
		default:
			a.dropped.Add(1)
		}
	})
}

func (a *APIRequestRecorder) Close(ctx context.Context) error {
	a.closeOnce.Do(func() { close(a.stop) })
	select {
	case <-a.done:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (a *APIRequestRecorder) run() {
	defer close(a.done)
	ticker := time.NewTicker(500 * time.Millisecond)
	defer ticker.Stop()
	pruneTicker := time.NewTicker(24 * time.Hour)
	defer pruneTicker.Stop()

	batch := make([]model.AnalyticsEvent, 0, 100)
	flush := func() {
		if len(batch) == 0 {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err := a.repo.CreateBatch(ctx, batch)
		cancel()
		if err != nil {
			slog.Warn("analytics: api request batch insert failed", "error", err, "count", len(batch))
		}
		batch = batch[:0]
		if dropped := a.dropped.Swap(0); dropped > 0 {
			slog.Warn("analytics: api request events dropped", "count", dropped)
		}
	}
	prune := func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		deleted, err := a.repo.DeleteAPIRequestsBefore(ctx, time.Now().UTC().AddDate(0, 0, -180))
		cancel()
		if err != nil {
			slog.Warn("analytics: api request retention cleanup failed", "error", err)
		} else if deleted > 0 {
			slog.Info("analytics: expired api request events removed", "count", deleted)
		}
	}
	for {
		select {
		case event := <-a.events:
			batch = append(batch, event)
			if len(batch) >= cap(batch) {
				flush()
			}
		case <-ticker.C:
			flush()
		case <-pruneTicker.C:
			prune()
		case <-a.stop:
			for {
				select {
				case event := <-a.events:
					batch = append(batch, event)
				default:
					flush()
					return
				}
			}
		}
	}
}

type analyticsResponseWriter struct {
	http.ResponseWriter
	statusCode   int
	wroteHeader  bool
	bytesWritten int64
}

func (w *analyticsResponseWriter) WriteHeader(code int) {
	if w.wroteHeader {
		return
	}
	w.wroteHeader = true
	w.statusCode = code
	w.ResponseWriter.WriteHeader(code)
}

func (w *analyticsResponseWriter) Write(data []byte) (int, error) {
	if !w.wroteHeader {
		w.wroteHeader = true
	}
	n, err := w.ResponseWriter.Write(data)
	w.bytesWritten += int64(n)
	return n, err
}

func (w *analyticsResponseWriter) Unwrap() http.ResponseWriter {
	return w.ResponseWriter
}

func requestUserID(r *http.Request, secret string) int64 {
	token, ok := extractBearerToken(r)
	if !ok {
		return 0
	}
	claims, err := jwtpkg.ParseToken(token, secret)
	if err != nil {
		return 0
	}
	return claims.UserID
}

func apiRequestClient(r *http.Request) string {
	header := strings.ToLower(strings.TrimSpace(r.Header.Get("X-Wallpaper-Client")))
	header = strings.ReplaceAll(header, "-", "_")
	switch header {
	case "macos", "mac_app", "mac_client":
		return "mac"
	case "android_app", "android_client":
		return "android"
	case "ios_app", "ios_client":
		return "ios"
	case "win", "win32", "windows_app", "windows_client":
		return "windows"
	case "chrome_extension", "chrome_ext", "extension":
		return "chrome"
	case "web", "mac", "android", "ios", "windows", "chrome":
		return header
	}

	ua := strings.ToLower(r.UserAgent())
	switch {
	case strings.Contains(ua, "wallpaperexchange/mac"):
		return "mac"
	case strings.Contains(ua, "wallpaperexchange/android"):
		return "android"
	case strings.Contains(ua, "wallpaperexchange/ios"):
		return "ios"
	case strings.Contains(ua, "wallpaperexchange/windows"):
		return "windows"
	case strings.HasPrefix(strings.ToLower(r.Header.Get("Origin")), "chrome-extension://"):
		return "chrome"
	case containsAny(ua, "bot", "spider", "crawler", "headless", "lighthouse", "curl", "wget"):
		return "bot"
	case strings.Contains(ua, "mozilla/"):
		return "web"
	default:
		return "other"
	}
}

func apiRequestIP(r *http.Request) string {
	if value := strings.TrimSpace(r.Header.Get("CF-Connecting-IP")); value != "" {
		return value
	}
	if value := strings.TrimSpace(r.Header.Get("X-Real-IP")); value != "" {
		return value
	}
	if value := r.Header.Get("X-Forwarded-For"); value != "" {
		return strings.TrimSpace(strings.Split(value, ",")[0])
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

func truncateAnalyticsValue(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit]
}

func containsAny(value string, needles ...string) bool {
	for _, needle := range needles {
		if strings.Contains(value, needle) {
			return true
		}
	}
	return false
}

func maxInt64(value, minimum int64) int64 {
	if value < minimum {
		return minimum
	}
	return value
}
