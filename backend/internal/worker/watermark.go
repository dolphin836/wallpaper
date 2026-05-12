package worker

import (
	"image"
	"image/color"
	"image/draw"
)

// addWatermark stamps a single "Wallpaper Exchange" mark in the bottom-right corner.
// Stamp size scales with image width so the same logic produces a proportionate
// mark on an 800px card preview and a 3840px detail preview alike.
func addWatermark(img image.Image) *image.NRGBA {
	bounds := img.Bounds()
	out := image.NewNRGBA(bounds)
	draw.Draw(out, bounds, img, bounds.Min, draw.Src)

	// Pixel-font scale targeting ~15-18% of image width for the whole stamp.
	// The text is 18 chars × ~6 columns each ≈ 108 horizontal units, so
	// `width / 250` gives a usable scale: ~3 at 800px, ~6 at 1600px, ~15 at 3840px.
	scale := bounds.Dx() / 250
	if scale < 2 {
		scale = 2
	}

	stamp := renderStamp(scale)
	stampW := stamp.Bounds().Dx()
	stampH := stamp.Bounds().Dy()

	// Inset from the right + bottom edges. Scale the inset with image size so the
	// margin looks consistent on both a 800px card and a 3840px preview.
	insetX := bounds.Dx() / 50
	insetY := bounds.Dy() / 50
	if insetX < 12 {
		insetX = 12
	}
	if insetY < 12 {
		insetY = 12
	}

	ox := bounds.Max.X - stampW - insetX
	oy := bounds.Max.Y - stampH - insetY
	drawStamp(out, stamp, ox, oy)

	return out
}

// drawStamp blends a pre-rendered stamp onto dst at (ox, oy).
func drawStamp(dst *image.NRGBA, stamp *image.NRGBA, ox, oy int) {
	sb := stamp.Bounds()
	db := dst.Bounds()
	for sy := sb.Min.Y; sy < sb.Max.Y; sy++ {
		dy := oy + sy - sb.Min.Y
		if dy < db.Min.Y || dy >= db.Max.Y {
			continue
		}
		for sx := sb.Min.X; sx < sb.Max.X; sx++ {
			dx := ox + sx - sb.Min.X
			if dx < db.Min.X || dx >= db.Max.X {
				continue
			}
			sc := stamp.NRGBAAt(sx, sy)
			if sc.A == 0 {
				continue
			}
			dc := dst.NRGBAAt(dx, dy)
			a := uint32(sc.A)
			ia := 255 - a
			dst.SetNRGBA(dx, dy, color.NRGBA{
				R: uint8((uint32(dc.R)*ia + uint32(sc.R)*a) / 255),
				G: uint8((uint32(dc.G)*ia + uint32(sc.G)*a) / 255),
				B: uint8((uint32(dc.B)*ia + uint32(sc.B)*a) / 255),
				A: 255,
			})
		}
	}
}

// renderStamp creates a small image with "Wallpaper Exchange" text using a built-in pixel font.
// Alpha is higher than the tiled-watermark era (35 → 130) since this is the only mark on
// the image and needs to be legible at a glance without being overbearing.
//
// `scale` is the pixel-font multiplier — caller passes a value derived from the
// target image size so the stamp stays proportionate across resolutions.
func renderStamp(scale int) *image.NRGBA {
	if scale < 1 {
		scale = 1
	}
	glyphs := map[byte][]string{
		'W': {"1   1", "1   1", "1 1 1", "1 1 1", " 1 1 "},
		'a': {"   ", " 11", "1 1", "1 1", " 11"},
		'l': {"1 ", "1 ", "1 ", "1 ", "11"},
		'p': {"   ", "11 ", "1 1", "11 ", "1  "},
		'e': {" 1 ", "1 1", "111", "1  ", " 11"},
		'r': {"  ", "11", "1 ", "1 ", "1 "},
		' ': {"  ", "  ", "  ", "  ", "  "},
		'E': {"111", "1  ", "11 ", "1  ", "111"},
		'x': {"   ", "1 1", " 1 ", "1 1", "1 1"},
		'c': {"  ", " 1", "1 ", "1 ", " 1"},
		'h': {"1  ", "1  ", "111", "1 1", "1 1"},
		'n': {"   ", "11 ", "1 1", "1 1", "1 1"},
		'g': {"   ", " 11", "1 1", " 11", "  1"},
	}
	text := "Wallpaper Exchange"

	totalW := 0
	for _, ch := range []byte(text) {
		g, ok := glyphs[ch]
		if !ok {
			totalW += 2 * scale
			continue
		}
		totalW += len(g[0])*scale + scale
	}

	h := 5 * scale
	img := image.NewNRGBA(image.Rect(0, 0, totalW, h))

	wm := color.NRGBA{R: 255, G: 255, B: 255, A: 130}

	cx := 0
	for _, ch := range []byte(text) {
		g, ok := glyphs[ch]
		if !ok {
			cx += 2 * scale
			continue
		}
		for row, line := range g {
			for col, pixel := range []byte(line) {
				if pixel != '1' {
					continue
				}
				for dy := 0; dy < scale; dy++ {
					for dx := 0; dx < scale; dx++ {
						img.SetNRGBA(cx+col*scale+dx, row*scale+dy, wm)
					}
				}
			}
		}
		cx += len(g[0])*scale + scale
	}

	return img
}
