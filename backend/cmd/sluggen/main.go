package main

import (
	"fmt"
	"log"
	"os"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/slug"
)

type wallpaperRow struct {
	ID    int64
	Title string
	Slug  string
}

type collectionRow struct {
	ID    int64
	Title string
	Slug  string
}

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}

	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}

	force := len(os.Args) > 1 && os.Args[1] == "--force"

	regenerateWallpapers(db, force)
	regenerateCollections(db, force)
}

func regenerateWallpapers(db *gorm.DB, force bool) {
	var rows []wallpaperRow
	q := db.Table("wallpapers").Select("id, title, slug")
	if !force {
		q = q.Where("slug = '' OR slug LIKE 'wallpaper-%' OR slug LIKE 'wp-%'")
	}
	if err := q.Find(&rows).Error; err != nil {
		log.Fatal("query wallpapers: ", err)
	}

	fmt.Printf("Wallpapers to update: %d\n", len(rows))
	for _, r := range rows {
		src := r.Title
		if src == "" {
			src = fmt.Sprintf("wallpaper-%d", r.ID)
		}
		newSlug := slug.Generate(src)
		if err := db.Table("wallpapers").Where("id = ?", r.ID).Update("slug", newSlug).Error; err != nil {
			log.Printf("  [FAIL] wallpaper %d: %v", r.ID, err)
			continue
		}
		fmt.Printf("  [OK] wallpaper %d: %s -> %s\n", r.ID, r.Slug, newSlug)
	}
	fmt.Println("Wallpapers done.")
}

func regenerateCollections(db *gorm.DB, force bool) {
	var rows []collectionRow
	q := db.Table("collections").Select("id, title, slug")
	if !force {
		q = q.Where("slug = '' OR slug LIKE 'collection-%' OR slug LIKE 'col-%'")
	}
	if err := q.Find(&rows).Error; err != nil {
		log.Fatal("query collections: ", err)
	}

	fmt.Printf("Collections to update: %d\n", len(rows))
	for _, r := range rows {
		src := r.Title
		if src == "" {
			src = fmt.Sprintf("collection-%d", r.ID)
		}
		newSlug := slug.Generate(src)
		if err := db.Table("collections").Where("id = ?", r.ID).Update("slug", newSlug).Error; err != nil {
			log.Printf("  [FAIL] collection %d: %v", r.ID, err)
			continue
		}
		fmt.Printf("  [OK] collection %d: %s -> %s\n", r.ID, r.Slug, newSlug)
	}
	fmt.Println("Collections done.")
}
