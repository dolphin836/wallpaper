// Package variant holds the pure logic behind on-demand (lazy) wallpaper
// device variants: deciding which devices an original can serve, the MinIO
// object key a generated variant lives at, and the cover-resize used to
// produce it. Generation IO (download original / upload result) lives in the
// service layer; everything here is deterministic and unit-tested.
package variant

import (
	"fmt"
	"image"
	"image/draw"

	"github.com/nfnt/resize"
)

// OriginalCoversDevice reports whether an original of origW×origH can produce
// a variant for a device of devW×devH without upscaling. Both dimensions must
// fit — a 1920-wide original can't serve a 2560-wide screen. This is the same
// rule the upload worker used to skip too-small devices, now also driving the
// detail page's device list.
func OriginalCoversDevice(origW, origH, devW, devH int) bool {
	return origW >= devW && origH >= devH
}

// ObjectKey is the MinIO key for a lazily-generated variant. The `derived/`
// prefix keeps these separate from the legacy `variants/` objects so the
// one-time purge of the old pre-generated set is unambiguous. Lazy variants
// are JPEG (pure-Go encoder — keeps cgo/libwebp out of the api binary).
func ObjectKey(wallpaperID, deviceID int64) string {
	return fmt.Sprintf("derived/%d/%d.jpg", wallpaperID, deviceID)
}

// CoverResize scales img to fully cover targetW×targetH (preserving aspect
// ratio via the larger scale factor) and center-crops to exactly that size.
func CoverResize(img image.Image, targetW, targetH int) image.Image {
	bounds := img.Bounds()
	srcW, srcH := bounds.Dx(), bounds.Dy()

	scaleW := float64(targetW) / float64(srcW)
	scaleH := float64(targetH) / float64(srcH)
	scale := scaleW
	if scaleH > scaleW {
		scale = scaleH
	}

	newW := uint(float64(srcW) * scale)
	newH := uint(float64(srcH) * scale)
	scaled := resize.Resize(newW, newH, img, resize.Lanczos3)

	scaledBounds := scaled.Bounds()
	offsetX := (scaledBounds.Dx() - targetW) / 2
	offsetY := (scaledBounds.Dy() - targetH) / 2
	cropRect := image.Rect(0, 0, targetW, targetH)

	cropped := image.NewRGBA(cropRect)
	draw.Draw(cropped, cropRect, scaled, image.Pt(scaledBounds.Min.X+offsetX, scaledBounds.Min.Y+offsetY), draw.Src)

	return cropped
}
