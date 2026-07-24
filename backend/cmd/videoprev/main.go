// Command videoprev rebuilds the three still-image tiers for historical video
// wallpapers without re-encoding or replacing original_url. It uploads the new
// assets first, updates the row, and only then deletes the previous thumb,
// preview, full poster, and preview-video objects.
//
// The default minimum-resolution guard skips historical rows below 1080p. An
// operator must opt in explicitly with --allow-below-minimum if those rows are
// intentionally kept and need their still images rebuilt.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/pkg/videoassets"
)

var errBelowMinimum = errors.New("video is below the 1080p minimum")

type videoRow struct {
	ID              int64
	OriginalURL     string
	ThumbURL        string
	PreviewURL      string
	PosterURL       string
	PreviewVideoURL string
	Width           int
	Height          int
}

type uploadedAsset struct {
	key  string
	path string
}

func main() {
	dryRun := flag.Bool("dry-run", false, "report what would be rebuilt; change nothing")
	wallpaperID := flag.Int64("id", 0, "only rebuild one wallpaper id")
	allowBelowMinimum := flag.Bool("allow-below-minimum", false, "also rebuild historical videos below 1080p")
	flag.Parse()

	cfg, err := config.Load()
	if err != nil {
		log.Fatal("load config: ", err)
	}
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		log.Fatal("connect db: ", err)
	}
	store, err := storage.New(cfg.MinIO)
	if err != nil {
		log.Fatal("minio: ", err)
	}

	query := db.Table("wallpapers").
		Select("id, original_url, thumb_url, preview_url, poster_url, preview_video_url, width, height").
		Where("file_type LIKE 'video/%'")
	if *wallpaperID > 0 {
		query = query.Where("id = ?", *wallpaperID)
	}
	var rows []videoRow
	if err := query.Order("id ASC").Find(&rows).Error; err != nil {
		log.Fatal("query videos: ", err)
	}
	log.Printf(
		"video rows: %d (dry-run=%v allow-below-minimum=%v)",
		len(rows), *dryRun, *allowBelowMinimum,
	)

	ctx := context.Background()
	var rebuilt, skipped, failed int
	for _, row := range rows {
		result, err := rebuild(ctx, db, store, row, *dryRun, *allowBelowMinimum)
		if err != nil {
			if errors.Is(err, errBelowMinimum) {
				log.Printf("  [SKIP] wallpaper %d: %v", row.ID, err)
				skipped++
				continue
			}
			log.Printf("  [FAIL] wallpaper %d: %v", row.ID, err)
			failed++
			continue
		}
		log.Printf("  [%s] wallpaper %d", result, row.ID)
		if !*dryRun {
			rebuilt++
		}
	}
	log.Printf("done. rebuilt=%d skipped_below_minimum=%d failed=%d", rebuilt, skipped, failed)
	if failed > 0 {
		os.Exit(1)
	}
}

func rebuild(
	ctx context.Context,
	db *gorm.DB,
	store *storage.Storage,
	row videoRow,
	dryRun bool,
	allowBelowMinimum bool,
) (string, error) {
	srcKey := store.ObjectKeyFromURL(row.OriginalURL)
	if srcKey == "" {
		return "", fmt.Errorf("cannot derive object key from %q", row.OriginalURL)
	}
	if dryRun {
		if !videoassets.MeetsMinimumResolution(row.Width, row.Height) && !allowBelowMinimum {
			return "", fmt.Errorf("%w: %dx%d", errBelowMinimum, row.Width, row.Height)
		}
		return fmt.Sprintf("DRY-RUN %dx%d", row.Width, row.Height), nil
	}

	work, err := os.MkdirTemp("", fmt.Sprintf("video-assets-%d-*", row.ID))
	if err != nil {
		return "", fmt.Errorf("mkdir temp: %w", err)
	}
	defer os.RemoveAll(work)

	inPath := filepath.Join(work, "input.mp4")
	if err := download(ctx, store, srcKey, inPath); err != nil {
		return "", fmt.Errorf("download original: %w", err)
	}
	probe, err := videoassets.Probe(ctx, inPath)
	if err != nil {
		return "", err
	}
	if !videoassets.MeetsMinimumResolution(probe.Width, probe.Height) && !allowBelowMinimum {
		return "", fmt.Errorf("%w: %dx%d", errBelowMinimum, probe.Width, probe.Height)
	}
	paths := videoassets.PosterPaths{
		Thumb:   filepath.Join(work, "thumb.webp"),
		Preview: filepath.Join(work, "preview.webp"),
		Full:    filepath.Join(work, "poster.webp"),
	}
	if err := videoassets.GeneratePosters(ctx, inPath, probe.Duration, paths); err != nil {
		return "", err
	}
	date := time.Now().UTC().Format("2006/01/02")
	assets := []uploadedAsset{
		{key: fmt.Sprintf("thumbs/%s.webp", uuid.New().String()), path: paths.Thumb},
		{key: fmt.Sprintf("previews/%s.webp", uuid.New().String()), path: paths.Preview},
		{key: fmt.Sprintf("posters/%s/%s.webp", date, uuid.New().String()), path: paths.Full},
	}
	for i, asset := range assets {
		if err := upload(ctx, store, asset.key, asset.path); err != nil {
			cleanupUploaded(ctx, store, assets[:i])
			return "", fmt.Errorf("upload %s: %w", asset.key, err)
		}
	}

	updates := map[string]any{
		"thumb_url":         store.GetURL(assets[0].key),
		"preview_url":       store.GetURL(assets[1].key),
		"poster_url":        store.GetURL(assets[2].key),
		"preview_video_url": "",
		"width":             probe.Width,
		"height":            probe.Height,
	}
	if err := db.WithContext(ctx).Table("wallpapers").Where("id = ?", row.ID).Updates(updates).Error; err != nil {
		cleanupUploaded(ctx, store, assets)
		return "", fmt.Errorf("update row: %w", err)
	}

	oldURLs := []string{row.ThumbURL, row.PreviewURL, row.PosterURL, row.PreviewVideoURL}
	seen := make(map[string]struct{}, len(oldURLs))
	for _, oldURL := range oldURLs {
		key := store.ObjectKeyFromURL(oldURL)
		if key == "" {
			continue
		}
		if _, duplicate := seen[key]; duplicate {
			continue
		}
		seen[key] = struct{}{}
		if err := store.Delete(ctx, key); err != nil {
			log.Printf("  [WARN] wallpaper %d: delete old asset %s: %v", row.ID, key, err)
		}
	}
	return fmt.Sprintf("OK %dx%d", probe.Width, probe.Height), nil
}

func download(ctx context.Context, store *storage.Storage, key, path string) error {
	source, err := store.GetObject(ctx, key)
	if err != nil {
		return err
	}
	defer source.Close()
	destination, err := os.Create(path)
	if err != nil {
		return err
	}
	defer destination.Close()
	_, err = io.Copy(destination, source)
	return err
}

func upload(ctx context.Context, store *storage.Storage, key, path string) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	return store.Upload(ctx, key, file, info.Size(), "image/webp")
}

func cleanupUploaded(ctx context.Context, store *storage.Storage, assets []uploadedAsset) {
	for _, asset := range assets {
		if err := store.Delete(ctx, asset.key); err != nil {
			log.Printf("  [WARN] delete newly-uploaded asset %s: %v", asset.key, err)
		}
	}
}
