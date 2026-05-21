// wallpaper-import takes a PNG/JPEG/HEIC file on stdin and uploads it
// through the regular WallpaperService.Upload flow — same MinIO write,
// same DB insert, same Kafka wallpaper.uploaded event, same worker
// pipeline. Used by scripts/wallpaper-publish.sh so the publish path
// doesn't need to go through HTTP + admin JWT — the CLI runs inside
// the api container where it has direct DB/MinIO/Kafka access.
//
// Usage (from inside the api container via `docker exec -i`):
//
//	cat full.png | /bin/wallpaper-import \
//	    --user-id 1 --ai \
//	    --description "AI-generated. Prompt: 雾气山脉日出" \
//	    --filename ai-gen.png --content-type image/png
//
// All flags are optional except for the file content on stdin.
package main

import (
	"bytes"
	"context"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"github.com/segmentio/kafka-go"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/config"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
	"github.com/wallpaper/backend/internal/service"
)

func main() {
	var (
		userID      int64
		title       string
		description string
		categoryID  int64
		isAI        bool
		filename    string
		contentType string
	)
	flag.Int64Var(&userID, "user-id", 1, "user id for the uploader (default: 1 = admin)")
	flag.StringVar(&title, "title", "", "optional title (empty = let autotag pick)")
	flag.StringVar(&description, "description", "", "optional description")
	flag.Int64Var(&categoryID, "category-id", 0, "optional category id (0 = let autotag pick)")
	flag.BoolVar(&isAI, "ai", false, "mark wallpaper as AI-generated (sets is_ai_generated=true)")
	flag.StringVar(&filename, "filename", "upload.png", "filename for the original (extension matters)")
	flag.StringVar(&contentType, "content-type", "image/png", "MIME type of the uploaded file")
	flag.Parse()

	// Stream the file off stdin so the wrapper can `cat foo.png | docker exec -i …`.
	// We need a Reader the Upload service can stream from, plus the exact
	// size for the MinIO PutObject call — easiest just to buffer it.
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		fatal("read stdin: %v", err)
	}
	if len(data) == 0 {
		fatal("stdin is empty — pipe a file in")
	}

	cfg, err := config.Load()
	if err != nil {
		fatal("config: %v", err)
	}
	db, err := gorm.Open(postgres.Open(cfg.DB.DSN()), &gorm.Config{})
	if err != nil {
		fatal("db: %v", err)
	}
	store, err := storage.New(cfg.MinIO)
	if err != nil {
		fatal("storage: %v", err)
	}
	// Ensure the bucket exists — same defensive step the api server runs.
	if err := store.EnsureBucket(context.Background()); err != nil {
		log.Printf("(warn) ensure bucket: %v", err)
	}

	kafkaWriter := &kafka.Writer{
		Addr:                   kafka.TCP(cfg.Kafka.Brokers...),
		Balancer:               &kafka.LeastBytes{},
		AllowAutoTopicCreation: true,
		BatchSize:              1,
		BatchTimeout:           10 * time.Millisecond,
		WriteTimeout:           10 * time.Second,
		RequiredAcks:           kafka.RequireOne,
	}
	defer kafkaWriter.Close()

	wallpaperRepo := repo.NewWallpaperRepo(db)
	tagRepo := repo.NewTagRepo(db)
	interactionRepo := repo.NewInteractionRepo(db)
	userRepo := repo.NewUserRepo(db)
	eventRepo := repo.NewEventRepo(db)
	coinRepo := repo.NewCoinRepo(db)
	collectionRepo := repo.NewCollectionRepo(db)
	deviceRepo := repo.NewDeviceRepo(db)

	wallpaperSvc := service.NewWallpaperService(
		wallpaperRepo, tagRepo, interactionRepo, userRepo,
		eventRepo, coinRepo, collectionRepo, deviceRepo,
		store, kafkaWriter,
	)

	wp, ec := wallpaperSvc.Upload(context.Background(), userID, service.UploadRequest{
		Title:         title,
		Description:   description,
		CategoryID:    categoryID,
		File:          bytes.NewReader(data),
		FileSize:      int64(len(data)),
		FileType:      contentType,
		FileName:      filename,
		IsAIGenerated: isAI,
	})
	if ec != nil {
		fatal("upload: %s (%d)", ec.Message, ec.Code)
	}

	// One-line, machine-parseable output so the publish script can read
	// the new id / slug back out of stdout.
	fmt.Printf("OK id=%d slug=%s\n", wp.ID, wp.Slug)
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
