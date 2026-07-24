package handler

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/service"
)

func TestViewMediaTokenIsBoundToAnonymousSession(t *testing.T) {
	now := time.Date(2026, time.July, 25, 12, 0, 0, 0, time.UTC)
	h := NewMediaHandler(nil, nil, "test-secret", "https://wallpaperexchange.com")
	h.now = func() time.Time { return now }

	sessionRequest := httptest.NewRequest(http.MethodGet, "https://wallpaperexchange.com/api/v1/wallpapers/example", nil)
	recorder := httptest.NewRecorder()
	session, err := h.EnsureViewSession(recorder, sessionRequest)
	if err != nil {
		t.Fatal(err)
	}
	cookies := recorder.Result().Cookies()
	if len(cookies) != 1 || cookies[0].Name != mediaSessionCookie {
		t.Fatalf("unexpected media session cookies: %#v", cookies)
	}

	signed, err := h.signedURL(sessionRequest, mediaClaims{
		WallpaperID: 42,
		Kind:        service.MediaKindOriginal,
		Mode:        "view",
		ExpiresAt:   now.Add(time.Minute).Unix(),
	}, session, "wallpaper_42.jpg")
	if err != nil {
		t.Fatal(err)
	}

	request := mediaTokenRequest(t, signed)
	request.AddCookie(cookies[0])
	claims, err := h.verifyRequestToken(request)
	if err != nil {
		t.Fatalf("valid session-bound token rejected: %v", err)
	}
	if claims.WallpaperID != 42 || claims.Mode != "view" {
		t.Fatalf("unexpected claims: %#v", claims)
	}

	if _, err := h.verifyRequestToken(mediaTokenRequest(t, signed)); err == nil {
		t.Fatal("view token unexpectedly worked without its session cookie")
	}

	wrongSession := mediaTokenRequest(t, signed)
	wrongSession.AddCookie(&http.Cookie{
		Name:  mediaSessionCookie,
		Value: "bWlzbWF0Y2hlZC1zZXNzaW9uLXZhbHVlLTEyMzQ1",
	})
	if _, err := h.verifyRequestToken(wrongSession); err == nil {
		t.Fatal("view token unexpectedly worked in a different anonymous session")
	}
}

func TestDownloadMediaTokenDoesNotRequireViewSession(t *testing.T) {
	now := time.Date(2026, time.July, 25, 12, 0, 0, 0, time.UTC)
	h := NewMediaHandler(nil, nil, "test-secret", "https://wallpaperexchange.com")
	h.now = func() time.Time { return now }
	request := httptest.NewRequest(http.MethodGet, "https://wallpaperexchange.com/api/v1/wallpapers/7/download", nil)

	signed, err := h.signedURL(request, mediaClaims{
		WallpaperID: 7,
		Kind:        service.MediaKindOriginal,
		Mode:        "download",
		ExpiresAt:   now.Add(time.Minute).Unix(),
	}, "", "wallpaper_7.png")
	if err != nil {
		t.Fatal(err)
	}

	claims, err := h.verifyRequestToken(mediaTokenRequest(t, signed))
	if err != nil {
		t.Fatalf("download token rejected without cookie: %v", err)
	}
	if claims.Mode != "download" {
		t.Fatalf("got mode %q, want download", claims.Mode)
	}
}

func TestExpiredMediaTokenIsRejected(t *testing.T) {
	now := time.Date(2026, time.July, 25, 12, 0, 0, 0, time.UTC)
	h := NewMediaHandler(nil, nil, "test-secret", "https://wallpaperexchange.com")
	h.now = func() time.Time { return now }
	request := httptest.NewRequest(http.MethodGet, "https://wallpaperexchange.com/api/v1/wallpapers/7/download", nil)

	signed, err := h.signedURL(request, mediaClaims{
		WallpaperID: 7,
		Kind:        service.MediaKindOriginal,
		Mode:        "download",
		ExpiresAt:   now.Unix(),
	}, "", "wallpaper_7.png")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.verifyRequestToken(mediaTokenRequest(t, signed)); err == nil {
		t.Fatal("token valid at its expiration instant")
	}
}

func TestParseSingleByteRange(t *testing.T) {
	tests := []struct {
		header      string
		size        int64
		wantStart   int64
		wantEnd     int64
		wantPartial bool
		wantErr     bool
	}{
		{header: "", size: 100, wantStart: 0, wantEnd: 99},
		{header: "bytes=10-19", size: 100, wantStart: 10, wantEnd: 19, wantPartial: true},
		{header: "bytes=90-", size: 100, wantStart: 90, wantEnd: 99, wantPartial: true},
		{header: "bytes=-8", size: 100, wantStart: 92, wantEnd: 99, wantPartial: true},
		{header: "bytes=90-200", size: 100, wantStart: 90, wantEnd: 99, wantPartial: true},
		{header: "bytes=100-", size: 100, wantErr: true},
		{header: "bytes=0-1,5-8", size: 100, wantErr: true},
		{header: "items=0-1", size: 100, wantErr: true},
	}

	for _, tt := range tests {
		t.Run(tt.header, func(t *testing.T) {
			start, end, partial, err := parseSingleByteRange(tt.header, tt.size)
			if (err != nil) != tt.wantErr {
				t.Fatalf("error = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				return
			}
			if start != tt.wantStart || end != tt.wantEnd || partial != tt.wantPartial {
				t.Fatalf("got (%d,%d,%v), want (%d,%d,%v)", start, end, partial, tt.wantStart, tt.wantEnd, tt.wantPartial)
			}
		})
	}
}

func mediaTokenRequest(t *testing.T, signedURL string) *http.Request {
	t.Helper()
	parsed, err := url.Parse(signedURL)
	if err != nil {
		t.Fatal(err)
	}
	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
	if len(parts) < 5 {
		t.Fatalf("unexpected signed media path: %s", parsed.Path)
	}
	request := httptest.NewRequest(http.MethodGet, signedURL, nil)
	routeContext := chi.NewRouteContext()
	routeContext.URLParams.Add("token", parts[3])
	return request.WithContext(context.WithValue(request.Context(), chi.RouteCtxKey, routeContext))
}
