package handler

import (
	"net/http"

	"github.com/wallpaper/backend/internal/repo"
)

func parseWallpaperExclusions(r *http.Request) repo.WallpaperExclusionFilters {
	q := r.URL.Query()
	return repo.WallpaperExclusionFilters{
		ExcludeDynamic: q.Get("exclude_dynamic") == "true",
		ExcludeVideo:   q.Get("exclude_video") == "true",
	}
}
