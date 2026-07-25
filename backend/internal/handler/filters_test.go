package handler

import (
	"net/http/httptest"
	"testing"
)

func TestParseWallpaperDeviceRequirement(t *testing.T) {
	tests := []struct {
		name       string
		url        string
		client     string
		headerW    string
		headerH    string
		wantWidth  int
		wantHeight int
	}{
		{
			name:   "web stays unfiltered even with device headers",
			url:    "/api/v1/wallpapers",
			client: "web", headerW: "1920", headerH: "1080",
		},
		{
			name:   "mac native headers",
			url:    "/api/v1/wallpapers",
			client: "mac", headerW: "2560", headerH: "1440",
			wantWidth: 2560, wantHeight: 1440,
		},
		{
			name:   "ios native headers",
			url:    "/api/v1/wallpapers",
			client: "iOS", headerW: "1179", headerH: "2556",
			wantWidth: 1179, wantHeight: 2556,
		},
		{
			name:   "android requires complete dimensions",
			url:    "/api/v1/wallpapers",
			client: "android", headerW: "1080",
		},
		{
			name:   "old native clients stay compatible",
			url:    "/api/v1/wallpapers",
			client: "mac",
		},
		{
			name:   "explicit query works for web",
			url:    "/api/v1/wallpapers?device_width=3840&device_height=2160",
			client: "web", headerW: "1920", headerH: "1080",
			wantWidth: 3840, wantHeight: 2160,
		},
		{
			name:   "explicit query overrides native headers",
			url:    "/api/v1/wallpapers?device_width=1280&device_height=720",
			client: "mac", headerW: "2560", headerH: "1440",
			wantWidth: 1280, wantHeight: 720,
		},
		{
			name:   "invalid native dimensions are ignored",
			url:    "/api/v1/wallpapers",
			client: "android", headerW: "wide", headerH: "1920",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := httptest.NewRequest("GET", tt.url, nil)
			r.Header.Set(wallpaperClientHeader, tt.client)
			if tt.headerW != "" {
				r.Header.Set(deviceWidthHeader, tt.headerW)
			}
			if tt.headerH != "" {
				r.Header.Set(deviceHeightHeader, tt.headerH)
			}

			width, height := parseWallpaperDeviceRequirement(r)
			if width != tt.wantWidth || height != tt.wantHeight {
				t.Fatalf("got %dx%d, want %dx%d", width, height, tt.wantWidth, tt.wantHeight)
			}
		})
	}
}

func TestParseWallpaperExclusionsIncludesNativeDimensions(t *testing.T) {
	r := httptest.NewRequest("GET", "/api/v1/wallpapers?exclude_video=true&resolution=4k&color=%2305374F", nil)
	r.Header.Set(wallpaperClientHeader, "android")
	r.Header.Set(deviceWidthHeader, "1080")
	r.Header.Set(deviceHeightHeader, "2400")

	filters := parseWallpaperExclusions(r)
	if !filters.ExcludeVideo {
		t.Fatal("expected exclude_video to remain enabled")
	}
	if filters.DeviceWidth != 1080 || filters.DeviceHeight != 2400 {
		t.Fatalf("got %dx%d, want 1080x2400", filters.DeviceWidth, filters.DeviceHeight)
	}
	if filters.Resolution != "4K" {
		t.Fatalf("got resolution %q, want 4K", filters.Resolution)
	}
	if filters.Color != "#05374f" {
		t.Fatalf("got color %q, want #05374f", filters.Color)
	}
}

func TestNormalizeWallpaperColor(t *testing.T) {
	tests := map[string]string{
		"#A1B2C3": "#a1b2c3",
		"#000000": "#000000",
		"A1B2C3":  "",
		"#XYZ123": "",
		"#123":    "",
	}
	for input, want := range tests {
		if got := normalizeWallpaperColor(input); got != want {
			t.Errorf("normalizeWallpaperColor(%q) = %q, want %q", input, got, want)
		}
	}
}
