package handler

import (
	"encoding/xml"
	"fmt"
	"log/slog"
	"net/http"

	"github.com/wallpaper/backend/internal/repo"
)

type SEOHandler struct {
	wallpaperRepo *repo.WallpaperRepo
	categoryRepo  *repo.CategoryRepo
}

func NewSEOHandler(wallpaperRepo *repo.WallpaperRepo, categoryRepo *repo.CategoryRepo) *SEOHandler {
	return &SEOHandler{wallpaperRepo: wallpaperRepo, categoryRepo: categoryRepo}
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
		{Loc: base + "/download/mac", ChangeFreq: "monthly", Priority: "0.5"},
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

func baseURL(r *http.Request) string {
	scheme := "http"
	if r.TLS != nil || r.Header.Get("X-Forwarded-Proto") == "https" {
		scheme = "https"
	}
	host := r.Host
	if h := r.Header.Get("X-Forwarded-Host"); h != "" {
		host = h
	}
	return scheme + "://" + host
}
