package handler

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/wallpaper/backend/internal/repo"
)

const (
	wallpaperClientHeader = "X-Wallpaper-Client"
	deviceWidthHeader     = "X-Device-Width"
	deviceHeightHeader    = "X-Device-Height"
)

// parseWallpaperDeviceRequirement keeps the public API backward compatible:
// explicit query parameters still work for web device pages and take
// precedence, while native clients can attach their current screen size once
// at the shared HTTP layer. Web requests and older native clients without a
// complete positive dimension pair remain unfiltered.
func parseWallpaperDeviceRequirement(r *http.Request) (int, int) {
	q := r.URL.Query()
	queryWidth, widthErr := strconv.Atoi(q.Get("device_width"))
	queryHeight, heightErr := strconv.Atoi(q.Get("device_height"))
	if widthErr == nil && heightErr == nil && queryWidth > 0 && queryHeight > 0 {
		return queryWidth, queryHeight
	}

	client := strings.ToLower(strings.TrimSpace(r.Header.Get(wallpaperClientHeader)))
	switch client {
	case "mac", "macos", "ios", "android":
	default:
		return 0, 0
	}

	width, widthErr := strconv.Atoi(r.Header.Get(deviceWidthHeader))
	height, heightErr := strconv.Atoi(r.Header.Get(deviceHeightHeader))
	if widthErr != nil || heightErr != nil || width <= 0 || height <= 0 {
		return 0, 0
	}
	return width, height
}

func parseWallpaperExclusions(r *http.Request) repo.WallpaperExclusionFilters {
	q := r.URL.Query()
	deviceWidth, deviceHeight := parseWallpaperDeviceRequirement(r)
	return repo.WallpaperExclusionFilters{
		ExcludeDynamic: q.Get("exclude_dynamic") == "true",
		ExcludeVideo:   q.Get("exclude_video") == "true",
		DeviceWidth:    deviceWidth,
		DeviceHeight:   deviceHeight,
		Resolution:     repo.NormalizeWallpaperResolution(q.Get("resolution")),
		Color:          repo.NormalizeWallpaperColorFamily(q.Get("color")),
	}
}
