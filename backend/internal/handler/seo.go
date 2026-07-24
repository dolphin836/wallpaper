package handler

import (
	"encoding/xml"
	"fmt"
	"html/template"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/wallpaper/backend/internal/repo"
)

type SEOHandler struct {
	wallpaperRepo  *repo.WallpaperRepo
	categoryRepo   *repo.CategoryRepo
	deviceRepo     *repo.DeviceRepo
	collectionRepo *repo.CollectionRepo
	userRepo       *repo.UserRepo
	indexNowKey    string // served as text from /{key}.txt for verification
	// canonicalURL overrides the request-derived base in sitemap/feed/
	// robots output. CF Pages proxies wallpaperexchange.com requests to
	// a private origin, which would otherwise leak that hostname into <loc>
	// tags and confuse search engines about the canonical site.
	canonicalURL string
}

func NewSEOHandler(
	wallpaperRepo *repo.WallpaperRepo,
	categoryRepo *repo.CategoryRepo,
	deviceRepo *repo.DeviceRepo,
	collectionRepo *repo.CollectionRepo,
	userRepo *repo.UserRepo,
	indexNowKey string,
	canonicalURL string,
) *SEOHandler {
	return &SEOHandler{
		wallpaperRepo:  wallpaperRepo,
		categoryRepo:   categoryRepo,
		deviceRepo:     deviceRepo,
		collectionRepo: collectionRepo,
		userRepo:       userRepo,
		indexNowKey:    indexNowKey,
		canonicalURL:   strings.TrimSuffix(canonicalURL, "/"),
	}
}

// base returns the canonical origin for sitemap/feed entries. Uses the
// configured canonicalURL when set, otherwise falls back to whatever
// the request itself indicates.
func (h *SEOHandler) base(r *http.Request) string {
	if h.canonicalURL != "" {
		return h.canonicalURL
	}
	return baseURL(r)
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
	fmt.Fprintf(w, robotsTemplate, h.base(r))
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
	base := h.base(r)

	urls := []sitemapURL{
		{Loc: base + "/", ChangeFreq: "daily", Priority: "1.0"},
		{Loc: base + "/uploaders", ChangeFreq: "weekly", Priority: "0.4"},
		{Loc: base + "/collections", ChangeFreq: "daily", Priority: "0.5"},
		{Loc: base + "/about", ChangeFreq: "monthly", Priority: "0.4"},
		{Loc: base + "/contribute", ChangeFreq: "monthly", Priority: "0.5"},
		{Loc: base + "/wallpapers-for", ChangeFreq: "weekly", Priority: "0.7"},
		{Loc: base + "/download", ChangeFreq: "monthly", Priority: "0.5"},
		{Loc: base + "/download/mac", ChangeFreq: "monthly", Priority: "0.4"},
	}

	// Category landing pages — one URL per category. Stable, small set
	// (10 today) of high-intent SEO entries (e.g. "nature wallpapers").
	if cats, cerr := h.categoryRepo.List(ctx); cerr == nil {
		for _, c := range cats {
			if c.Slug == "" {
				continue
			}
			urls = append(urls, sitemapURL{
				Loc:        base + "/category/" + c.Slug,
				ChangeFreq: "daily",
				Priority:   "0.7",
			})
		}
	} else {
		slog.ErrorContext(ctx, "sitemap: list categories failed", "error", cerr)
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

	// Public collection landing pages.
	if cols, cerr := h.collectionRepo.ListPublicForSitemap(ctx); cerr == nil {
		for _, c := range cols {
			if c.Slug == "" {
				continue
			}
			urls = append(urls, sitemapURL{
				Loc:        base + "/collections/" + c.Slug,
				LastMod:    c.UpdatedAt.UTC().Format("2006-01-02"),
				ChangeFreq: "weekly",
				Priority:   "0.5",
			})
		}
	} else {
		slog.ErrorContext(ctx, "sitemap: list public collections failed", "error", cerr)
	}

	// Uploader profile pages — only users with at least one published
	// wallpaper, so empty profiles don't pad the index.
	if uploaders, uerr := h.userRepo.ListUploadersForSitemap(ctx); uerr == nil {
		for _, u := range uploaders {
			if u.Username == "" {
				continue
			}
			urls = append(urls, sitemapURL{
				Loc:        base + "/user/" + u.Username,
				LastMod:    u.UpdatedAt.UTC().Format("2006-01-02"),
				ChangeFreq: "weekly",
				Priority:   "0.4",
			})
		}
	} else {
		slog.ErrorContext(ctx, "sitemap: list uploaders failed", "error", uerr)
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

// IndexNowKey serves the verification file. Bing/Yandex GET
// /{key}.txt during URL submission and expect the response body to
// exactly match the key. We expose a single fixed path so the CF Pages
// middleware (and nginx) can proxy by exact match — easier than a
// catch-all dynamic txt route.
func (h *SEOHandler) IndexNowKey(w http.ResponseWriter, r *http.Request) {
	if h.indexNowKey == "" {
		http.NotFound(w, r)
		return
	}
	// Guard against accidental path mismatch — the search engine fetches
	// /{KEY}.txt and we want a 404 (not the key) if a curious crawler
	// pokes around a different filename.
	want := h.indexNowKey + ".txt"
	if got := strings.TrimPrefix(r.URL.Path, "/"); got != want {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=86400")
	_, _ = w.Write([]byte(h.indexNowKey))
}

// Feed serves /feed.xml — RSS 2.0 of the 50 most recent published
// wallpapers. Pinterest, Pocket, IFTTT, and a long tail of aggregators
// poll this for free, so it's worth the ~1ms a request costs.
type rssGUID struct {
	Value       string `xml:",chardata"`
	IsPermaLink bool   `xml:"isPermaLink,attr"`
}

type rssEnclosure struct {
	URL    string `xml:"url,attr"`
	Length int    `xml:"length,attr,omitempty"`
	Type   string `xml:"type,attr"`
}

type rssItem struct {
	Title       string       `xml:"title"`
	Link        string       `xml:"link"`
	Description string       `xml:"description"`
	GUID        rssGUID      `xml:"guid"`
	PubDate     string       `xml:"pubDate"`
	Enclosure   rssEnclosure `xml:"enclosure,omitempty"`
}

type rssChannel struct {
	Title         string    `xml:"title"`
	Link          string    `xml:"link"`
	Description   string    `xml:"description"`
	Language      string    `xml:"language"`
	LastBuildDate string    `xml:"lastBuildDate"`
	Items         []rssItem `xml:"item"`
}

type rssDoc struct {
	XMLName xml.Name   `xml:"rss"`
	Version string     `xml:"version,attr"`
	Channel rssChannel `xml:"channel"`
}

func (h *SEOHandler) Feed(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	base := h.base(r)

	entries, err := h.wallpaperRepo.ListRecentForFeed(ctx, 50)
	if err != nil {
		slog.ErrorContext(ctx, "feed: list recent failed", "error", err)
		// still return a valid empty feed so subscribed readers don't
		// drop the subscription on a transient error.
		entries = nil
	}

	items := make([]rssItem, 0, len(entries))
	for _, e := range entries {
		link := base + "/wallpaper/" + e.Slug
		title := strings.TrimSpace(e.Title)
		if title == "" {
			title = "Untitled wallpaper"
		}
		desc := strings.TrimSpace(e.Description)
		if desc == "" {
			desc = fmt.Sprintf("%dx%d wallpaper", e.Width, e.Height)
		}
		img := e.PreviewURL
		if img == "" {
			img = e.ThumbURL
		}
		items = append(items, rssItem{
			Title:       title,
			Link:        link,
			Description: desc,
			GUID:        rssGUID{Value: link, IsPermaLink: true},
			PubDate:     e.CreatedAt.UTC().Format(time.RFC1123Z),
			Enclosure: rssEnclosure{
				URL:  img,
				Type: "image/webp",
			},
		})
	}

	doc := rssDoc{
		Version: "2.0",
		Channel: rssChannel{
			Title:         "Wallpaper Exchange — Latest Wallpapers",
			Link:          base,
			Description:   "The newest wallpapers shared on Wallpaper Exchange.",
			Language:      "en",
			LastBuildDate: time.Now().UTC().Format(time.RFC1123Z),
			Items:         items,
		},
	}

	w.Header().Set("Content-Type", "application/rss+xml; charset=utf-8")
	w.Header().Set("Cache-Control", "public, max-age=300")
	_, _ = w.Write([]byte(xml.Header))
	enc := xml.NewEncoder(w)
	enc.Indent("", "  ")
	if err := enc.Encode(doc); err != nil {
		slog.ErrorContext(ctx, "feed: encode failed", "error", err)
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
<script type="application/ld+json">{
"@context":"https://schema.org",
"@type":"BreadcrumbList",
"itemListElement":[
  {"@type":"ListItem","position":1,"name":"Home","item":"{{.SiteURL}}/"},
  {"@type":"ListItem","position":2,"name":"Browse","item":"{{.SiteURL}}/discover"}{{if .CategoryName}},
  {"@type":"ListItem","position":3,"name":"{{.CategoryName}}","item":"{{.SiteURL}}/category/{{.CategorySlug}}"},
  {"@type":"ListItem","position":4,"name":"{{.Title}}","item":"{{.URL}}"}{{else}},
  {"@type":"ListItem","position":3,"name":"{{.Title}}","item":"{{.URL}}"}{{end}}
]
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
	SiteURL       string // canonical apex, used for breadcrumb itemListElement.item
	CategoryName  string // optional; when empty, breadcrumb skips the category step
	CategorySlug  string
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

	base := h.base(r)
	dynamic := ""
	if wp.IsDynamic {
		dynamic = " dynamic"
	}
	data := ogPageData{
		Title:         fmt.Sprintf("%d×%d%s Wallpaper", wp.Width, wp.Height, dynamic),
		Description:   fmt.Sprintf("Download this %d×%d%s wallpaper for free on Wallpaper Exchange.", wp.Width, wp.Height, dynamic),
		URL:           base + "/wallpaper/" + wp.Slug,
		Image:         wp.PreviewURL,
		OriginalURL:   wp.PreviewURL,
		ThumbURL:      wp.ThumbURL,
		Width:         wp.Width,
		Height:        wp.Height,
		DatePublished: wp.CreatedAt.UTC().Format("2006-01-02"),
		SiteURL:       base,
	}
	if data.Image == "" {
		data.Image = wp.ThumbURL
	}
	if data.OriginalURL == "" {
		data.OriginalURL = data.Image
	}
	// Best-effort category lookup for the BreadcrumbList step. A missing
	// category (or a transient DB error) just collapses the breadcrumb to
	// Home > Browse > Title — never blocks the prerender.
	if wp.CategoryID > 0 {
		if cat, cerr := h.categoryRepo.GetByID(r.Context(), wp.CategoryID); cerr == nil && cat != nil {
			data.CategoryName = cat.Name
			data.CategorySlug = cat.Slug
		}
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
