package videoassets

import "testing"

func TestMeetsMinimumResolution(t *testing.T) {
	tests := []struct {
		name          string
		width, height int
		want          bool
	}{
		{"landscape 1080p", 1920, 1080, true},
		{"portrait 1080p", 1080, 1920, true},
		{"4k", 3840, 2160, true},
		{"720p", 1280, 720, false},
		{"ultrawide with short edge below 1080", 2560, 900, false},
		{"missing dimensions", 0, 0, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := MeetsMinimumResolution(tt.width, tt.height); got != tt.want {
				t.Fatalf("MeetsMinimumResolution(%d, %d) = %v, want %v", tt.width, tt.height, got, tt.want)
			}
		})
	}
}
