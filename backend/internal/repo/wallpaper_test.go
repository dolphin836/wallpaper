package repo

import "testing"

func TestWallpaperResolutionBounds(t *testing.T) {
	tests := []struct {
		value   string
		wantMin int
		wantMax int
	}{
		{value: "720p", wantMin: 1280, wantMax: 1920},
		{value: "1080P", wantMin: 1920, wantMax: 2560},
		{value: "2k", wantMin: 2560, wantMax: 3840},
		{value: "4K", wantMin: 3840, wantMax: 7680},
		{value: "8K", wantMin: 7680, wantMax: 0},
		{value: "invalid", wantMin: 0, wantMax: 0},
	}

	for _, tt := range tests {
		t.Run(tt.value, func(t *testing.T) {
			min, max := wallpaperResolutionBounds(tt.value)
			if min != tt.wantMin || max != tt.wantMax {
				t.Fatalf("got [%d, %d), want [%d, %d)", min, max, tt.wantMin, tt.wantMax)
			}
		})
	}
}

func TestSupportedWallpaperResolutionsReturnsCopy(t *testing.T) {
	first := SupportedWallpaperResolutions()
	first[0] = "changed"
	second := SupportedWallpaperResolutions()
	if second[0] != "720P" {
		t.Fatalf("supported resolutions were mutated: %v", second)
	}
}
