package worker

import (
	"fmt"
	"image"
	"image/color"
	"math"
	"sort"
	"strings"
)

type colorBucket struct {
	r, g, b int64
	count   int64
}

func (b *colorBucket) avg() (uint8, uint8, uint8) {
	if b.count == 0 {
		return 0, 0, 0
	}
	return uint8(b.r / b.count), uint8(b.g / b.count), uint8(b.b / b.count)
}

func extractPalette(img image.Image, n int) []string {
	bounds := img.Bounds()
	w, h := bounds.Dx(), bounds.Dy()

	step := 1
	total := w * h
	if total > 10000 {
		step = int(math.Sqrt(float64(total) / 10000))
		if step < 1 {
			step = 1
		}
	}

	var pixels [][3]uint8
	for y := bounds.Min.Y; y < bounds.Max.Y; y += step {
		for x := bounds.Min.X; x < bounds.Max.X; x += step {
			r, g, b, a := img.At(x, y).RGBA()
			if a < 0x8000 {
				continue
			}
			pixels = append(pixels, [3]uint8{uint8(r >> 8), uint8(g >> 8), uint8(b >> 8)})
		}
	}

	if len(pixels) == 0 {
		return nil
	}

	centers := kMeans(pixels, n, 20)

	sort.Slice(centers, func(i, j int) bool {
		return centers[i].count > centers[j].count
	})

	result := dedup(centers, n)

	var hexColors []string
	for _, c := range result {
		r, g, b := c.avg()
		hexColors = append(hexColors, fmt.Sprintf("#%02X%02X%02X", r, g, b))
	}
	return hexColors
}

func kMeans(pixels [][3]uint8, k, iterations int) []colorBucket {
	if k > len(pixels) {
		k = len(pixels)
	}

	step := len(pixels) / k
	centers := make([][3]float64, k)
	for i := 0; i < k; i++ {
		p := pixels[i*step]
		centers[i] = [3]float64{float64(p[0]), float64(p[1]), float64(p[2])}
	}

	buckets := make([]colorBucket, k)

	for iter := 0; iter < iterations; iter++ {
		for i := range buckets {
			buckets[i] = colorBucket{}
		}

		for _, p := range pixels {
			best := 0
			bestDist := math.MaxFloat64
			pr, pg, pb := float64(p[0]), float64(p[1]), float64(p[2])
			for ci, c := range centers {
				d := (pr-c[0])*(pr-c[0]) + (pg-c[1])*(pg-c[1]) + (pb-c[2])*(pb-c[2])
				if d < bestDist {
					bestDist = d
					best = ci
				}
			}
			buckets[best].r += int64(p[0])
			buckets[best].g += int64(p[1])
			buckets[best].b += int64(p[2])
			buckets[best].count++
		}

		for i, b := range buckets {
			if b.count > 0 {
				centers[i] = [3]float64{
					float64(b.r) / float64(b.count),
					float64(b.g) / float64(b.count),
					float64(b.b) / float64(b.count),
				}
			}
		}
	}

	return buckets
}

func colorDist(a, b [3]uint8) float64 {
	dr := float64(a[0]) - float64(b[0])
	dg := float64(a[1]) - float64(b[1])
	db := float64(a[2]) - float64(b[2])
	return math.Sqrt(dr*dr + dg*dg + db*db)
}

func dedup(buckets []colorBucket, max int) []colorBucket {
	const minDist = 30.0
	var result []colorBucket
	for _, b := range buckets {
		if b.count == 0 {
			continue
		}
		r, g, bl := b.avg()
		curr := [3]uint8{r, g, bl}
		tooClose := false
		for _, existing := range result {
			er, eg, eb := existing.avg()
			if colorDist(curr, [3]uint8{er, eg, eb}) < minDist {
				tooClose = true
				break
			}
		}
		if !tooClose {
			result = append(result, b)
		}
		if len(result) >= max {
			break
		}
	}
	return result
}

func sortByLuminance(colors []string) {
	sort.Slice(colors, func(i, j int) bool {
		ri, gi, bi := parseHex(colors[i])
		rj, gj, bj := parseHex(colors[j])
		li := 0.299*float64(ri) + 0.587*float64(gi) + 0.114*float64(bi)
		lj := 0.299*float64(rj) + 0.587*float64(gj) + 0.114*float64(bj)
		return li < lj
	})
}

func parseHex(hex string) (uint8, uint8, uint8) {
	hex = strings.TrimPrefix(hex, "#")
	if len(hex) != 6 {
		return 0, 0, 0
	}
	var r, g, b uint8
	_, _ = fmt.Sscanf(hex, "%02x%02x%02x", &r, &g, &b)
	return r, g, b
}

func extractColors(img image.Image) (dominant string, palette string) {
	nrgba := toNRGBA(img)
	colors := extractPalette(nrgba, 8)
	if len(colors) == 0 {
		return "", ""
	}

	dominant = colors[0]

	display := colors
	if len(display) > 5 {
		display = display[:5]
	}
	sortByLuminance(display)

	return dominant, strings.Join(display, ",")
}

func toNRGBA(img image.Image) *image.NRGBA {
	if nrgba, ok := img.(*image.NRGBA); ok {
		return nrgba
	}
	bounds := img.Bounds()
	dst := image.NewNRGBA(bounds)
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			dst.Set(x, y, color.NRGBAModel.Convert(img.At(x, y)))
		}
	}
	return dst
}
