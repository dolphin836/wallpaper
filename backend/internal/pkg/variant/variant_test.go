package variant

import (
	"image"
	"testing"
)

func TestOriginalCoversDevice(t *testing.T) {
	tests := []struct {
		name                   string
		origW, origH           int
		devW, devH             int
		want                   bool
	}{
		{"exact match", 1920, 1080, 1920, 1080, true},
		{"original larger both dims", 3840, 2160, 1920, 1080, true},
		{"original too narrow", 1920, 1080, 2560, 1440, false},
		{"original wide enough but too short", 3840, 1080, 1920, 1440, false},
		{"original one pixel short on width", 1919, 1080, 1920, 1080, false},
		{"portrait original covers portrait device", 1290, 2796, 1179, 2556, true},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := OriginalCoversDevice(tc.origW, tc.origH, tc.devW, tc.devH); got != tc.want {
				t.Errorf("OriginalCoversDevice(%d,%d,%d,%d) = %v, want %v",
					tc.origW, tc.origH, tc.devW, tc.devH, got, tc.want)
			}
		})
	}
}

func TestObjectKey(t *testing.T) {
	got := ObjectKey(42, 7)
	want := "derived/42/7.jpg"
	if got != want {
		t.Errorf("ObjectKey(42, 7) = %q, want %q", got, want)
	}
}

func TestCoverResizeProducesExactTargetDimensions(t *testing.T) {
	// A landscape source cropped to a portrait target, and vice versa, must
	// both come out at exactly the requested dimensions (cover + center-crop).
	src := image.NewRGBA(image.Rect(0, 0, 4000, 2000))
	tests := []struct{ w, h int }{
		{1920, 1080},
		{1080, 1920},
		{1000, 1000},
	}
	for _, tc := range tests {
		out := CoverResize(src, tc.w, tc.h)
		b := out.Bounds()
		if b.Dx() != tc.w || b.Dy() != tc.h {
			t.Errorf("CoverResize to %dx%d produced %dx%d", tc.w, tc.h, b.Dx(), b.Dy())
		}
	}
}
