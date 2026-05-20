// indexnow-backfill posts every browseable URL on the site to IndexNow.
// Run this once after enabling IndexNow (or after a major sitemap
// refresh) so Bing/Yandex don't have to wait for incremental notifies
// to catch up on existing content.
//
// Usage:
//
//	./indexnow-backfill            # dry-run: print URL count, no POST
//	./indexnow-backfill --commit   # actually submit
//
// Submits in batches of 1000 URLs (IndexNow allows up to 10k per call,
// but 1k batches keep the request body small and let us recover from
// transient errors mid-list).
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"strings"
	"time"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/indexnow"
	"github.com/wallpaper/backend/internal/repo"
)

const batchSize = 1000

func main() {
	var commit bool
	flag.BoolVar(&commit, "commit", false, "actually POST to IndexNow (default: dry-run)")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	if cfg.IndexNow.Key == "" {
		log.Fatal("INDEXNOW_KEY is not set in env")
	}
	site := strings.TrimSuffix(cfg.IndexNow.SiteURL, "/")
	if site == "" {
		log.Fatal("INDEXNOW_SITE_URL is not set")
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}
	ctx := context.Background()

	wpRepo := repo.NewWallpaperRepo(db)
	catRepo := repo.NewCategoryRepo(db)
	devRepo := repo.NewDeviceRepo(db)
	colRepo := repo.NewCollectionRepo(db)
	userRepo := repo.NewUserRepo(db)

	urls := []string{
		site + "/",
		site + "/discover",
		site + "/collections",
		site + "/uploaders",
		site + "/wallpapers-for",
		site + "/weekly-picks",
		site + "/download/mac",
		site + "/about",
		site + "/contribute",
	}

	if cats, err := catRepo.List(ctx); err == nil {
		for _, c := range cats {
			if c.Slug != "" {
				urls = append(urls, site+"/category/"+c.Slug)
			}
		}
	} else {
		fmt.Printf("list categories: %v\n", err)
	}

	if devs, err := devRepo.ListActiveWithCounts(ctx); err == nil {
		for _, d := range devs {
			if d.Slug != "" {
				urls = append(urls, site+"/wallpapers-for/"+d.Slug)
			}
		}
	} else {
		fmt.Printf("list devices: %v\n", err)
	}

	if cols, err := colRepo.ListPublicForSitemap(ctx); err == nil {
		for _, c := range cols {
			if c.Slug != "" {
				urls = append(urls, site+"/collections/"+c.Slug)
			}
		}
	} else {
		fmt.Printf("list collections: %v\n", err)
	}

	if users, err := userRepo.ListUploadersForSitemap(ctx); err == nil {
		for _, u := range users {
			if u.Username != "" {
				urls = append(urls, site+"/user/"+u.Username)
			}
		}
	} else {
		fmt.Printf("list uploaders: %v\n", err)
	}

	if wps, err := wpRepo.ListPublishedForSitemap(ctx); err == nil {
		for _, w := range wps {
			if w.Slug != "" {
				urls = append(urls, site+"/wallpaper/"+w.Slug)
			}
		}
	} else {
		fmt.Printf("list wallpapers: %v\n", err)
	}

	fmt.Printf("==> Prepared %d URLs for IndexNow submission\n", len(urls))
	if !commit {
		fmt.Println("--- dry-run; pass --commit to POST ---")
		return
	}

	client, err := indexnow.New(cfg.IndexNow.Key, cfg.IndexNow.SiteURL)
	if err != nil {
		log.Fatal("init indexnow: ", err)
	}

	batches := 0
	for i := 0; i < len(urls); i += batchSize {
		end := i + batchSize
		if end > len(urls) {
			end = len(urls)
		}
		batch := urls[i:end]
		batches++
		fmt.Printf("  batch %d: submitting %d URLs...\n", batches, len(batch))
		batchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		if err := client.Submit(batchCtx, batch); err != nil {
			fmt.Printf("  batch %d FAILED: %v\n", batches, err)
		}
		cancel()
		// Throttle to be polite — IndexNow is fast but no need to bury it.
		time.Sleep(500 * time.Millisecond)
	}

	fmt.Println("Done.")
}
