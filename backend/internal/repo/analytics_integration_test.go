package repo

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

func TestAnalyticsDetailedQueriesPostgres(t *testing.T) {
	dsn := os.Getenv("WPE_ANALYTICS_TEST_DSN")
	if dsn == "" {
		t.Skip("WPE_ANALYTICS_TEST_DSN is not set")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		t.Fatal(err)
	}

	var database string
	if err := db.Raw("SELECT current_database()").Scan(&database).Error; err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(database, "_test") {
		t.Fatalf("refusing to mutate non-test database %q", database)
	}

	ctx := context.Background()
	const wallpaperID int64 = 900001
	if err := db.Exec("DELETE FROM wallpaper_events WHERE wallpaper_id = ?", wallpaperID).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Exec("DELETE FROM wallpapers WHERE id = ?", wallpaperID).Error; err != nil {
		t.Fatal(err)
	}
	if err := db.Exec(`
		INSERT INTO wallpapers (id, user_id, category_id, title, original_url, thumb_url, slug, status)
		OVERRIDING SYSTEM VALUE VALUES (?, 0, 1, 'Analytics Test', 'test.jpg', 'thumb.jpg', 'analytics-test', 1)
	`, wallpaperID).Error; err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		db.Exec("DELETE FROM wallpaper_events WHERE wallpaper_id = ?", wallpaperID)
		db.Exec("DELETE FROM wallpapers WHERE id = ?", wallpaperID)
		db.Exec("DELETE FROM analytics_events WHERE session_id = 'analytics-test-session'")
	})

	repository := NewAnalyticsRepo(db)
	now := time.Now().UTC()
	pageProps, _ := json.Marshal(map[string]any{"client": "web"})
	apiProps, _ := json.Marshal(map[string]any{
		"client": "web", "method": "GET", "route": "/api/v1/wallpapers/{id}",
		"status": 200, "duration_ms": 12, "request_bytes": 0, "response_bytes": 128,
	})
	for _, event := range []model.AnalyticsEvent{
		{SessionID: "analytics-test-session", EventType: "page_view", Path: "/wallpaper/analytics-test", UserAgent: "Mozilla/5.0", IP: "127.0.0.1", Props: pageProps, CreatedAt: now},
		{SessionID: "analytics-test-session", EventType: "api_request", Path: "/api/v1/wallpapers/{id}", UserAgent: "Mozilla/5.0", IP: "127.0.0.1", Props: apiProps, CreatedAt: now},
	} {
		if err := repository.Create(ctx, &event); err != nil {
			t.Fatal(err)
		}
	}
	if err := db.Create(&model.WallpaperEvent{
		WallpaperID: wallpaperID, EventType: "view", Client: "web", IP: "127.0.0.1",
		SessionID: "analytics-test-session", CreatedAt: now,
	}).Error; err != nil {
		t.Fatal(err)
	}

	from := now.Add(-time.Hour)
	to := now.Add(time.Hour)
	totals, err := repository.Totals(ctx, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if totals.PageViews != 1 || totals.WallpaperViews != 1 || totals.APIRequests != 1 {
		t.Fatalf("unexpected totals: %+v", totals)
	}

	daily, err := repository.DailyTimeseries(ctx, from, to, "Asia/Tokyo")
	if err != nil || len(daily) == 0 {
		t.Fatalf("daily query failed: rows=%d err=%v", len(daily), err)
	}
	pages, pageTotal, err := repository.PageViewsDaily(ctx, from, to, "Asia/Tokyo", "web", "analytics-test", 0, 20)
	if err != nil || pageTotal != 1 || len(pages) != 1 {
		t.Fatalf("page details failed: rows=%d total=%d err=%v", len(pages), pageTotal, err)
	}
	wallpapers, wallpaperTotal, err := repository.WallpaperViewsDaily(ctx, from, to, "Asia/Tokyo", "web", "900001", 0, 20)
	if err != nil || wallpaperTotal != 1 || len(wallpapers) != 1 {
		t.Fatalf("wallpaper details failed: rows=%d total=%d err=%v", len(wallpapers), wallpaperTotal, err)
	}
	requests, requestTotal, err := repository.APIRequestsDaily(ctx, from, to, "Asia/Tokyo", "web", "wallpapers", 0, 20)
	if err != nil || requestTotal != 1 || len(requests) != 1 {
		t.Fatalf("request details failed: rows=%d total=%d err=%v", len(requests), requestTotal, err)
	}
}
