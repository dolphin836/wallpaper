package handler

import (
	"encoding/xml"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/repo"
)

type SEOHandler struct {
	wallpaperRepo *repo.WallpaperRepo
	categoryRepo  *repo.CategoryRepo
	deviceRepo    *repo.DeviceRepo
}

func NewSEOHandler(wallpaperRepo *repo.WallpaperRepo, categoryRepo *repo.CategoryRepo, deviceRepo *repo.DeviceRepo) *SEOHandler {
	return &SEOHandler{wallpaperRepo: wallpaperRepo, categoryRepo: categoryRepo, deviceRepo: deviceRepo}
}

const robotsTemplate = `User-agent: *
Allow: /
Disallow: /login
Disallow: /register
Disallow: /upload
Disallow: /user/
Disallow: /api/

Sitemap: %s/sitemap.xml
`

func (h *SEOHandler) RobotsTxt(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	fmt.Fprintf(w, robotsTemplate, baseURL(r))
}

type sitemapURL struct {
	Loc        string `xml:"loc"`
	LastMod    string `xml:"lastmod,omitempty"`
	ChangeFreq string `xml:"changefreq,omitempty"`
	Priority   string `xml:"priority,omitempty"`
}

type sitemapDoc struct {
	XMLName xml.Name     `xml:"urlset"`
	Xmlns   string       `xml:"xmlns,attr"`
	URLs    []sitemapURL `xml:"url"`
}

func (h *SEOHandler) Sitemap(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	base := baseURL(r)

	urls := []sitemapURL{
		{Loc: base + "/", ChangeFreq: "daily", Priority: "1.0"},
		{Loc: base + "/uploaders", ChangeFreq: "weekly", Priority: "0.4"},
		{Loc: base + "/collections", ChangeFreq: "daily", Priority: "0.5"},
		{Loc: base + "/about", ChangeFreq: "monthly", Priority: "0.4"},
		{Loc: base + "/contribute", ChangeFreq: "monthly", Priority: "0.5"},
		{Loc: base + "/download/mac", ChangeFreq: "monthly", Priority: "0.5"},
	}

	// Device-specific landing pages — one URL per active device profile.
	// These are SEO long-tail entry points for searches like "iPhone 16
	// Pro wallpaper", so we include them in sitemap.xml at decent priority.
	if devices, derr := h.deviceRepo.ListActive(ctx); derr == nil {
		for _, d := range devices {
			if d.Slug == "" {
				continue
			}
			urls = append(urls, sitemapURL{
				Loc:        base + "/wallpapers-for/" + d.Slug,
				ChangeFreq: "weekly",
				Priority:   "0.6",
			})
		}
	} else {
		slog.ErrorContext(ctx, "sitemap: list active devices failed", "error", derr)
	}

	entries, err := h.wallpaperRepo.ListPublishedForSitemap(ctx)
	if err != nil {
		slog.ErrorContext(ctx, "sitemap: list published failed", "error", err)
		// keep going — homepage entries are still useful
	}
	for _, e := range entries {
		urls = append(urls, sitemapURL{
			Loc:        base + "/wallpaper/" + e.Slug,
			LastMod:    e.UpdatedAt.UTC().Format("2006-01-02"),
			ChangeFreq: "monthly",
			Priority:   "0.6",
		})
	}

	w.Header().Set("Content-Type", "application/xml; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=600")
	_, _ = w.Write([]byte(xml.Header))
	enc := xml.NewEncoder(w)
	enc.Indent("", "  ")
	if err := enc.Encode(sitemapDoc{
		Xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9",
		URLs:  urls,
	}); err != nil {
		slog.ErrorContext(ctx, "sitemap: encode failed", "error", err)
	}
}

// ogPageTemplate is what JS-incapable bots (Twitter, Facebook, WeChat, Slack,
// Telegram, Discord, etc.) see when they hit /wallpaper/:slug. nginx routes
// requests with bot User-Agents to /__og/wallpaper/:slug; everyone else still
// gets the SPA which fills the same meta via React 19's head hoisting.
var ogPageTemplate = template.Must(template.New("og").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{{.Title}}</title>
<meta name="description" content="{{.Description}}">
<link rel="canonical" href="{{.URL}}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Wallpaper Exchange">
<meta property="og:title" content="{{.Title}}">
<meta property="og:description" content="{{.Description}}">
<meta property="og:url" content="{{.URL}}">
<meta property="og:image" content="{{.Image}}">
<meta property="og:image:width" content="{{.Width}}">
<meta property="og:image:height" content="{{.Height}}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{{.Title}}">
<meta name="twitter:description" content="{{.Description}}">
<meta name="twitter:image" content="{{.Image}}">
<script type="application/ld+json">{
"@context":"https://schema.org",
"@type":"ImageObject",
"name":"{{.Title}}",
"contentUrl":"{{.OriginalURL}}",
"thumbnailUrl":"{{.ThumbURL}}",
"width":{{.Width}},
"height":{{.Height}},
"datePublished":"{{.DatePublished}}"
}</script>
</head>
<body>
<h1>{{.Title}}</h1>
<p>{{.Description}}</p>
<img src="{{.Image}}" alt="{{.Title}}" width="{{.Width}}" height="{{.Height}}">
<p><a href="{{.URL}}">View on Wallpaper Exchange</a></p>
</body>
</html>`))

type ogPageData struct {
	Title         string
	Description   string
	URL           string
	Image         string
	OriginalURL   string
	ThumbURL      string
	Width         int
	Height        int
	DatePublished string
}

func (h *SEOHandler) OGWallpaper(w http.ResponseWriter, r *http.Request) {
	slug := chi.URLParam(r, "slug")
	wp, err := h.wallpaperRepo.GetBySlug(r.Context(), slug)
	if err != nil {
		slog.ErrorContext(r.Context(), "og: lookup failed", "slug", slug, "error", err)
		http.Error(w, "internal error", http.StatusInternalServerError)
		return
	}
	if wp == nil {
		http.NotFound(w, r)
		return
	}

	base := baseURL(r)
	dynamic := ""
	if wp.IsDynamic {
		dynamic = " dynamic"
	}
	data := ogPageData{
		Title:         fmt.Sprintf("%d×%d%s Wallpaper", wp.Width, wp.Height, dynamic),
		Description:   fmt.Sprintf("Download this %d×%d%s wallpaper for free on Wallpaper Exchange.", wp.Width, wp.Height, dynamic),
		URL:           base + "/wallpaper/" + wp.Slug,
		Image:         wp.PreviewURL,
		OriginalURL:   wp.OriginalURL,
		ThumbURL:      wp.ThumbURL,
		Width:         wp.Width,
		Height:        wp.Height,
		DatePublished: wp.CreatedAt.UTC().Format("2006-01-02"),
	}
	if data.Image == "" {
		data.Image = wp.OriginalURL
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=3600")
	if err := ogPageTemplate.Execute(w, data); err != nil {
		slog.ErrorContext(r.Context(), "og: template execute failed", "error", err)
	}
}

func baseURL(r *http.Request) string {
	host := r.Host
	if h := r.Header.Get("X-Forwarded-Host"); h != "" {
		host = h
	}
	// Strip the api. prefix because the SEO routes are reached two ways:
	// (1) directly via api.wallpaperexchange.com and (2) via the CF Pages SPA's
	// _redirects rule that proxies /sitemap.xml & /robots.txt to the api
	// subdomain. In both cases the canonical browseable surface is the apex
	// (wallpaperexchange.com), and sitemap entries must point there or Google
	// will treat the entire api.* subdomain as the indexed property.
	if strings.HasPrefix(host, "api.") {
		host = strings.TrimPrefix(host, "api.")
	}
	// Prefer the X-Forwarded-Proto Caddy sets, but nginx in front of us
	// overwrites it with its own $scheme (http on the docker network), so
	// also assume https for any non-loopback host — this is a TLS-fronted
	// service in every real deployment.
	scheme := "https"
	if r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	} else if r.Header.Get("X-Forwarded-Proto") == "http" && (strings.HasPrefix(host, "localhost") || strings.HasPrefix(host, "127.0.0.1")) {
		scheme = "http"
	} else if r.TLS == nil && (strings.HasPrefix(host, "localhost") || strings.HasPrefix(host, "127.0.0.1")) {
		scheme = "http"
	}
	return scheme + "://" + host
}
