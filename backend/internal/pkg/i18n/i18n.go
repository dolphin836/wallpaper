// Package i18n resolves the response language for content localization
// (category names, tag names, collection titles). The SPA sends its UI
// language verbatim in Accept-Language; other clients send standard
// browser-style values, so the parser also folds BCP-47 variants onto the
// four supported tags.
package i18n

import (
	"net/http"
	"strings"
)

// Supported UI languages, mirroring frontend/src/i18n/index.ts.
var Supported = []string{"en", "zh-CN", "zh-TW", "ja"}

const Default = "en"

// FromRequest maps the request's Accept-Language onto one of the supported
// language tags. Only the highest-priority entry is considered — the SPA
// sends exactly one tag, and for browsers the first entry is the user's
// primary language anyway.
func FromRequest(r *http.Request) string {
	header := r.Header.Get("Accept-Language")
	if header == "" {
		return Default
	}
	first := header
	if i := strings.IndexByte(first, ','); i >= 0 {
		first = first[:i]
	}
	if i := strings.IndexByte(first, ';'); i >= 0 {
		first = first[:i]
	}
	return normalize(strings.TrimSpace(first))
}

func normalize(tag string) string {
	lower := strings.ToLower(tag)
	switch {
	case strings.HasPrefix(lower, "zh"):
		// Traditional-script variants; everything else under zh is Simplified.
		if strings.Contains(lower, "hant") || strings.Contains(lower, "tw") ||
			strings.Contains(lower, "hk") || strings.Contains(lower, "mo") {
			return "zh-TW"
		}
		return "zh-CN"
	case strings.HasPrefix(lower, "ja"):
		return "ja"
	case strings.HasPrefix(lower, "en"):
		return "en"
	default:
		return Default
	}
}
