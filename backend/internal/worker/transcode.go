package worker

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/pkg/videoassets"
	"github.com/wallpaper/backend/internal/repo"
)

// TranscodeWorker consumes wallpaper.transcode events for video
// uploads (single-file, ≤200 MB, arrived via the tus handler), runs
// ffmpeg to normalize the encoding to H.264 + AAC at source resolution,
// extracts 400px / 1600px / full-size poster images, uploads the four
// resulting assets to MinIO, and moves the wallpaper row from Processing →
// PendingReview so the admin queue picks it up.
//
// Why a separate worker (not the image worker):
//   - Different external binary (ffmpeg vs libheif / libwebp).
//   - Different event topology (one input → two output objects:
//     transcoded mp4 + poster.webp).
//   - Different kafka topic so the image worker doesn't have to
//     pattern-match on file_type, and so a transcode worker pool
//     can scale independently of image processing.
type TranscodeWorker struct {
	reader  *kafka.Reader
	wpRepo  *repo.WallpaperRepo
	jobRepo *repo.WorkerJobRepo
	storage *storage.Storage
	// transcodeDir is a host-mounted scratch directory the worker
	// writes intermediate files into. Sized for max-input × concurrent.
	transcodeDir string
}

func NewTranscodeWorker(
	brokers []string,
	wpRepo *repo.WallpaperRepo,
	jobRepo *repo.WorkerJobRepo,
	st *storage.Storage,
	transcodeDir string,
) (*TranscodeWorker, error) {
	if transcodeDir == "" {
		transcodeDir = filepath.Join(os.TempDir(), "wpe-transcode")
	}
	if err := os.MkdirAll(transcodeDir, 0o755); err != nil {
		return nil, fmt.Errorf("mkdir transcode dir: %w", err)
	}
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:     brokers,
		Topic:       "wallpaper.transcode",
		GroupID:     "transcode-worker",
		MinBytes:    1,
		MaxBytes:    10e6,
		ErrorLogger: readerErrorLogger("transcode-worker"),
	})
	return &TranscodeWorker{
		reader:       reader,
		wpRepo:       wpRepo,
		jobRepo:      jobRepo,
		storage:      st,
		transcodeDir: transcodeDir,
	}, nil
}

func (w *TranscodeWorker) Close() error { return w.reader.Close() }

func (w *TranscodeWorker) Run(ctx context.Context) error {
	slog.Info("transcode worker started")
	for {
		msg, err := w.reader.FetchMessage(ctx)
		if err != nil {
			if errors.Is(err, context.Canceled) {
				return ctx.Err()
			}
			slog.Error("transcode: fetch failed", "error", err)
			continue
		}
		var event WallpaperUploadedEvent
		if err := json.Unmarshal(msg.Value, &event); err != nil {
			slog.Error("transcode: unmarshal failed", "error", err)
			if commitErr := w.reader.CommitMessages(ctx, msg); commitErr != nil {
				slog.Error("transcode: commit (parse-fail) failed", "error", commitErr)
			}
			continue
		}

		jobID, jobErr := w.jobRepo.Start(ctx, "transcode", "wallpaper.transcode", event.WallpaperID)
		if jobErr != nil {
			slog.WarnContext(ctx, "transcode: worker_jobs start failed (non-fatal)", "wallpaper_id", event.WallpaperID, "error", jobErr)
		}

		if err := w.processVideo(ctx, event); err != nil {
			slog.Error("transcode: process video failed",
				"wallpaper_id", event.WallpaperID, "error", err)
			if updErr := w.wpRepo.UpdateStatus(ctx, event.WallpaperID, model.WallpaperStatusFailed); updErr != nil {
				slog.Error("transcode: mark failed failed", "wallpaper_id", event.WallpaperID, "error", updErr)
			}
			if finErr := w.jobRepo.Finish(ctx, jobID, "failed", err.Error()); finErr != nil {
				slog.WarnContext(ctx, "transcode: worker_jobs finish(failed) failed", "wallpaper_id", event.WallpaperID, "error", finErr)
			}
		} else if finErr := w.jobRepo.Finish(ctx, jobID, "done", ""); finErr != nil {
			slog.WarnContext(ctx, "transcode: worker_jobs finish(done) failed", "wallpaper_id", event.WallpaperID, "error", finErr)
		}

		if err := w.reader.CommitMessages(ctx, msg); err != nil {
			slog.Error("transcode: commit failed", "error", err)
		}
	}
}

func (w *TranscodeWorker) processVideo(ctx context.Context, event WallpaperUploadedEvent) error {
	// Working dir per upload — caller cleans up everything in it.
	work := filepath.Join(w.transcodeDir, fmt.Sprintf("wp-%d-%s", event.WallpaperID, uuid.New().String()[:8]))
	if err := os.MkdirAll(work, 0o755); err != nil {
		return fmt.Errorf("mkdir work: %w", err)
	}
	defer os.RemoveAll(work)

	// Pull original from MinIO to local disk. ffmpeg streams from
	// stdin too, but writing to disk lets us probe + give ffmpeg
	// random access (faster + lower memory).
	srcPath := filepath.Join(work, "input"+strings.ToLower(filepath.Ext(event.ObjectKey)))
	if srcPath == filepath.Join(work, "input") {
		srcPath = filepath.Join(work, "input.mp4")
	}
	if err := w.downloadObject(ctx, event.ObjectKey, srcPath); err != nil {
		return fmt.Errorf("download original: %w", err)
	}

	// Probe duration + dimensions for the wallpaper row update.
	probe, err := videoassets.Probe(ctx, srcPath)
	if err != nil {
		return fmt.Errorf("ffprobe: %w", err)
	}
	if probe.Width <= 0 || probe.Height <= 0 {
		return fmt.Errorf("ffprobe returned zero dimensions")
	}
	if !videoassets.MeetsMinimumResolution(probe.Width, probe.Height) {
		// The TUS create hook rejects dimensions supplied by current clients,
		// while this probe remains the authoritative guard for older clients
		// that do not send width/height metadata.
		if err := w.storage.Delete(ctx, event.ObjectKey); err != nil {
			slog.WarnContext(ctx, "transcode: delete rejected source failed", "key", event.ObjectKey, "error", err)
		}
		return fmt.Errorf(
			"video resolution %dx%d is below the minimum %dx%d",
			probe.Width, probe.Height, videoassets.MinLongEdge, videoassets.MinShortEdge,
		)
	}

	// Normalize to H.264 + AAC without reducing the source resolution.
	// -movflags +faststart puts the moov atom at the front so clients can
	// start playback before the whole file downloads.
	outMp4 := filepath.Join(work, "out.mp4")
	if err := videoassets.Transcode(ctx, srcPath, outMp4); err != nil {
		return err
	}
	servedProbe, err := videoassets.Probe(ctx, outMp4)
	if err != nil {
		return fmt.Errorf("ffprobe transcoded mp4: %w", err)
	}
	if servedProbe.Width <= 0 || servedProbe.Height <= 0 {
		return fmt.Errorf("ffprobe transcoded mp4 returned zero dimensions")
	}

	posterPaths := videoassets.PosterPaths{
		Thumb:   filepath.Join(work, "thumb.webp"),
		Preview: filepath.Join(work, "preview.webp"),
		Full:    filepath.Join(work, "poster.webp"),
	}
	if err := videoassets.GeneratePosters(ctx, outMp4, servedProbe.Duration, posterPaths); err != nil {
		return err
	}

	// Upload the transcoded video and all three image tiers. There is no
	// derived preview video; playback loads original_url only after click.
	mp4Key := fmt.Sprintf("videos/%s/%s.mp4",
		time.Now().UTC().Format("2006/01/02"), uuid.New().String())
	if err := w.uploadFile(ctx, mp4Key, outMp4, "video/mp4"); err != nil {
		return fmt.Errorf("upload transcoded mp4: %w", err)
	}
	assetDate := time.Now().UTC().Format("2006/01/02")
	thumbKey := fmt.Sprintf("thumbs/%s.webp", uuid.New().String())
	previewKey := fmt.Sprintf("previews/%s.webp", uuid.New().String())
	posterKey := fmt.Sprintf("posters/%s/%s.webp", assetDate, uuid.New().String())
	for _, asset := range []struct {
		key  string
		path string
		name string
	}{
		{thumbKey, posterPaths.Thumb, "thumb"},
		{previewKey, posterPaths.Preview, "preview"},
		{posterKey, posterPaths.Full, "full poster"},
	} {
		if err := w.uploadFile(ctx, asset.key, asset.path, "image/webp"); err != nil {
			return fmt.Errorf("upload %s: %w", asset.name, err)
		}
	}

	// Update DB:
	//   original_url → transcoded mp4 (the H.264 one is what we
	//                   actually serve to all clients)
	//   thumb_url    → poster (cards / list)
	//   preview_url  → poster (detail page hero before video play)
	//   width/height → transcoded mp4 dimensions, matching what clients
	//                  actually download and filter against
	//   file_size    → transcoded size
	//   status       → PendingReview
	st, _ := os.Stat(outMp4)
	if err := w.wpRepo.UpdateTranscoded(ctx, event.WallpaperID, repo.UpdateTranscodedInput{
		OriginalURL:     w.storage.GetURL(mp4Key),
		ThumbURL:        w.storage.GetURL(thumbKey),
		PreviewURL:      w.storage.GetURL(previewKey),
		PosterURL:       w.storage.GetURL(posterKey),
		PreviewVideoURL: "",
		Width:           servedProbe.Width,
		Height:          servedProbe.Height,
		FileSize:        st.Size(),
		FileType:        "video/mp4",
	}); err != nil {
		return fmt.Errorf("update wallpaper row: %w", err)
	}
	if err := w.storage.Delete(ctx, event.ObjectKey); err != nil {
		slog.WarnContext(ctx, "transcode: delete staged source failed", "key", event.ObjectKey, "error", err)
	}

	slog.Info("transcode: done",
		"wallpaper_id", event.WallpaperID,
		"source_width", probe.Width, "source_height", probe.Height,
		"width", servedProbe.Width, "height", servedProbe.Height,
		"duration_s", probe.Duration,
		"size_mb", float64(st.Size())/1024.0/1024.0,
	)
	return nil
}

// downloadObject streams a MinIO object to a local file.
func (w *TranscodeWorker) downloadObject(ctx context.Context, objectKey, destPath string) error {
	obj, err := w.storage.GetObject(ctx, objectKey)
	if err != nil {
		return err
	}
	defer obj.Close()
	f, err := os.Create(destPath)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, obj)
	return err
}

// uploadFile pushes a local file into MinIO.
func (w *TranscodeWorker) uploadFile(ctx context.Context, objectKey, srcPath, contentType string) error {
	f, err := os.Open(srcPath)
	if err != nil {
		return err
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return err
	}
	return w.storage.Upload(ctx, objectKey, f, st.Size(), contentType)
}
