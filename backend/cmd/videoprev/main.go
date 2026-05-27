// Command videoprev backfills the low-quality preview clip for video
// wallpapers uploaded before the preview feature existed. For each video
// missing a preview_video_url it downloads the current transcode, produces the
// same 480p / CRF30 / muted preview the transcode worker now emits, uploads it,
// and sets preview_video_url. Status is left untouched (no re-approval needed).
//
// Needs ffmpeg, so it ships in the worker image. Run:
//
//	docker compose exec worker /bin/videoprev          # backfill all missing
//	docker compose exec worker /bin/videoprev --dry-run
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/google/uuid"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
)

type videoRow struct {
	ID          int64
	OriginalURL string
}

func main() {
	dryRun := flag.Bool("dry-run", false, "report what would be backfilled; change nothing")
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

	var rows []videoRow
	if err := db.Table("wallpapers").
		Select("id, original_url").
		Where("file_type LIKE 'video/%' AND preview_video_url = ''").
		Find(&rows).Error; err != nil {
		log.Fatal("query videos: ", err)
	}
	log.Printf("videos missing a preview: %d (dry-run=%v)", len(rows), *dryRun)

	ctx := context.Background()
	var done, failed int
	for _, r := range rows {
		if *dryRun {
			log.Printf("  [dry-run] would backfill wallpaper %d (%s)", r.ID, r.OriginalURL)
			continue
		}
		if err := backfill(ctx, db, store, r); err != nil {
			log.Printf("  [FAIL] wallpaper %d: %v", r.ID, err)
			failed++
			continue
		}
		log.Printf("  [OK] wallpaper %d", r.ID)
		done++
	}
	log.Printf("done. backfilled=%d failed=%d", done, failed)
}

func backfill(ctx context.Context, db *gorm.DB, store *storage.Storage, r videoRow) error {
	srcKey := store.ObjectKeyFromURL(r.OriginalURL)
	if srcKey == "" {
		return fmt.Errorf("cannot derive object key from %q", r.OriginalURL)
	}

	work, err := os.MkdirTemp("", "videoprev")
	if err != nil {
		return fmt.Errorf("mkdir temp: %w", err)
	}
	defer os.RemoveAll(work)

	// Download the current transcode.
	rc, err := store.GetObject(ctx, srcKey)
	if err != nil {
		return fmt.Errorf("get source: %w", err)
	}
	inPath := filepath.Join(work, "in.mp4")
	f, err := os.Create(inPath)
	if err != nil {
		rc.Close()
		return fmt.Errorf("create temp: %w", err)
	}
	if _, err := io.Copy(f, rc); err != nil {
		f.Close()
		rc.Close()
		return fmt.Errorf("copy source: %w", err)
	}
	f.Close()
	rc.Close()

	// Same 480p / CRF30 / muted preview the transcode worker emits.
	outPath := filepath.Join(work, "preview.mp4")
	args := []string{
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", inPath,
		"-c:v", "libx264", "-profile:v", "high", "-preset", "veryfast", "-crf", "30",
		"-vf", "scale=-2:'min(480,ih)'",
		"-an",
		"-movflags", "+faststart",
		"-max_muxing_queue_size", "1024",
		outPath,
	}
	if out, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg: %w (%s)", err, string(out))
	}

	previewKey := fmt.Sprintf("video-previews/%s/%s.mp4",
		time.Now().UTC().Format("2006/01/02"), uuid.New().String())
	pf, err := os.Open(outPath)
	if err != nil {
		return fmt.Errorf("open preview: %w", err)
	}
	defer pf.Close()
	st, _ := pf.Stat()
	if err := store.Upload(ctx, previewKey, pf, st.Size(), "video/mp4"); err != nil {
		return fmt.Errorf("upload preview: %w", err)
	}

	if err := db.Table("wallpapers").
		Where("id = ?", r.ID).
		Update("preview_video_url", store.GetURL(previewKey)).Error; err != nil {
		return fmt.Errorf("update row: %w", err)
	}
	return nil
}
