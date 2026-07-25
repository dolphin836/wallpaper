package repo

import (
	"strings"
	"testing"
)

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

func TestNormalizeWallpaperColorFamily(t *testing.T) {
	tests := map[string]string{
		" BLUE ":  "blue",
		"Pink":    "pink",
		"#3b82f6": "",
		"teal":    "",
	}
	for input, want := range tests {
		if got := NormalizeWallpaperColorFamily(input); got != want {
			t.Errorf("NormalizeWallpaperColorFamily(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestSupportedWallpaperColorFamiliesReturnsCopy(t *testing.T) {
	first := SupportedWallpaperColorFamilies()
	first[0] = "changed"
	second := SupportedWallpaperColorFamilies()
	if second[0] != "red" {
		t.Fatalf("supported color families were mutated: %v", second)
	}
}

func TestWallpaperColorFamilyPredicateCoversEveryFamily(t *testing.T) {
	for _, family := range SupportedWallpaperColorFamilies() {
		predicate := wallpaperColorFamilyPredicate("w", family)
		if predicate == "" {
			t.Fatalf("missing predicate for %q", family)
		}
		if !strings.Contains(predicate, "w.color_palette") || !strings.Contains(predicate, "w.dominant_color") {
			t.Fatalf("predicate for %q does not inspect the full palette: %s", family, predicate)
		}
	}
	if predicate := wallpaperColorFamilyPredicate("w", "#3b82f6"); predicate != "" {
		t.Fatalf("unexpected predicate for invalid family: %s", predicate)
	}
}
