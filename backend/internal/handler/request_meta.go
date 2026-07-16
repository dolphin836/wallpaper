package handler

import (
	"net/http"
	"net/url"
	"strings"

	"github.com/wallpaper/backend/internal/repo"
)

func requestClient(r *http.Request, explicit string) string {
	candidates := []string{
		explicit,
		r.Header.Get("X-Wallpaper-Client"),
	}
	for _, v := range candidates {
		if c := normalizeClient(v); c != "" {
			return c
		}
	}

	origin := strings.ToLower(r.Header.Get("Origin"))
	referrer := strings.ToLower(r.Referer())
	if strings.HasPrefix(origin, "chrome-extension://") || strings.HasPrefix(referrer, "chrome-extension://") {
		return "chrome"
	}

	ua := strings.ToLower(r.UserAgent())
	switch {
	case strings.Contains(ua, "wallpaperexchange/mac"):
		return "mac"
	case strings.Contains(ua, "wallpaperexchange/android"):
		return "android"
	case strings.Contains(ua, "wallpaperexchange/ios"):
		return "ios"
	case strings.Contains(ua, "wallpaperexchange/windows"):
		return "windows"
	default:
		return "web"
	}
}

func normalizeClient(value string) string {
	v := strings.ToLower(strings.TrimSpace(value))
	v = strings.ReplaceAll(v, "-", "_")
	switch v {
	case "", "unknown":
		return ""
	case "macos", "mac_app", "mac_client":
		return "mac"
	case "android_app", "android_client":
		return "android"
	case "ios_app", "ios_client":
		return "ios"
	case "win", "win32", "windows_app", "windows_client":
		return "windows"
	case "chrome_extension", "chrome_ext", "extension":
		return "chrome"
	default:
		return v
	}
}

func requestCountry(r *http.Request) string {
	return strings.ToUpper(truncate(r.Header.Get("CF-IPCountry"), 8))
}

func requestReferrer(r *http.Request, explicit string) string {
	if strings.TrimSpace(explicit) != "" {
		return truncate(strings.TrimSpace(explicit), 512)
	}
	return truncate(r.Referer(), 512)
}

func registrationSource(explicit, referrer string) string {
	if s := strings.TrimSpace(explicit); s != "" {
		return truncate(s, 128)
	}
	if referrer == "" {
		return "direct"
	}
	u, err := url.Parse(referrer)
	if err != nil || u.Host == "" {
		if strings.HasPrefix(strings.ToLower(referrer), "chrome-extension://") {
			return "chrome_extension"
		}
		return "direct"
	}
	host := strings.ToLower(strings.TrimPrefix(u.Hostname(), "www."))
	switch host {
	case "wallpaperexchange.com", "api.wallpaperexchange.com":
		return "site"
	default:
		return truncate(host, 128)
	}
}

func requestEventMeta(r *http.Request, explicitClient, sessionID string) repo.EventMeta {
	return repo.EventMeta{
		Client:    requestClient(r, explicitClient),
		IP:        truncate(clientIP(r), 64),
		UserAgent: truncate(r.UserAgent(), 512),
		Referrer:  truncate(r.Referer(), 512),
		SessionID: truncate(sessionID, 64),
	}
}
