package worker

import (
	"image"
	"image/color"
	"image/draw"
	"math"
)

// addWatermark stamps a tiled diagonal "WallShare" text pattern onto img.
// Uses a pixel-font approach — no external font files required.
func addWatermark(img image.Image) *image.NRGBA {
	bounds := img.Bounds()
	out := image.NewNRGBA(bounds)
	draw.Draw(out, bounds, img, bounds.Min, draw.Src)

	stamp := renderStamp()
	stampW := stamp.Bounds().Dx()
	stampH := stamp.Bounds().Dy()
	spacingX := stampW + 80
	spacingY := stampH + 100

	for y := -bounds.Dy(); y < bounds.Dy()*2; y += spacingY {
		for x := -bounds.Dx(); x < bounds.Dx()*2; x += spacingX {
			rx := int(float64(x)*math.Cos(0.35) - float64(y)*math.Sin(0.35))
			ry := int(float64(x)*math.Sin(0.35) + float64(y)*math.Cos(0.35))
			drawStamp(out, stamp, bounds.Min.X+rx, bounds.Min.Y+ry)
		}
	}

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

// renderStamp creates a small image with "WallShare" text using a built-in pixel font.
func renderStamp() *image.NRGBA {
	glyphs := map[byte][]string{
		'W': {"1   1", "1   1", "1 1 1", "1 1 1", " 1 1 "},
		'a': {"  ", " 11", "1 1", "1 1", " 11"},
		'l': {"1 ", "1 ", "1 ", "1 ", "11"},
		'S': {" 11", "1  ", " 1 ", "  1", "11 "},
		'h': {"1  ", "1  ", "111", "1 1", "1 1"},
		'r': {"  ", "11", "1 ", "1 ", "1 "},
		'e': {" 1 ", "1 1", "111", "1  ", " 11"},
	}
	text := "WallShare"
	scale := 3

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

	wm := color.NRGBA{R: 255, G: 255, B: 255, A: 35}

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
