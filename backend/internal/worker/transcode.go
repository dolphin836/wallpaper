package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

// TranscodeWorker consumes wallpaper.transcode events for video
// uploads (single-file, ≤200 MB, arrived via the tus handler), runs
// ffmpeg to normalize the encoding to H.264 + AAC at ≤1080p,
// extracts a poster image from the first second, uploads both back
// to MinIO, and moves the wallpaper row from Processing →
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
		Brokers:  brokers,
		Topic:    "wallpaper.transcode",
		GroupID:  "transcode-worker",
		MinBytes: 1,
		MaxBytes: 10e6,
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
	probe, err := ffprobe(ctx, srcPath)
	if err != nil {
		return fmt.Errorf("ffprobe: %w", err)
	}
	if probe.Width <= 0 || probe.Height <= 0 {
		return fmt.Errorf("ffprobe returned zero dimensions")
	}

	// Transcode → H.264 + AAC, cap height at 1080p (preserves aspect
	// via -2 for width). CRF 23 is the ffmpeg sweet-spot for delivery.
	// -movflags +faststart puts the moov atom at the front so the
	// browser can start playback before the whole file downloads.
	outMp4 := filepath.Join(work, "out.mp4")
	transcodeArgs := []string{
		"-y", "-hide_banner", "-loglevel", "error",
		"-i", srcPath,
		"-c:v", "libx264", "-profile:v", "high", "-preset", "medium", "-crf", "23",
		"-vf", "scale=-2:'min(1080,ih)'",
		"-c:a", "aac", "-b:a", "128k",
		"-movflags", "+faststart",
		"-max_muxing_queue_size", "1024",
		outMp4,
	}
	if out, err := exec.CommandContext(ctx, "ffmpeg", transcodeArgs...).CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg transcode: %w (%s)", err, snippet(out, 400))
	}

	// Poster from the 1s mark (or the first frame if the video is
	// shorter). webp keeps the file ≈10× smaller than jpeg for the
	// same quality and matches what the image worker writes.
	posterPath := filepath.Join(work, "poster.webp")
	seek := "1"
	if probe.Duration > 0 && probe.Duration < 1 {
		seek = "0"
	}
	posterArgs := []string{
		"-y", "-hide_banner", "-loglevel", "error",
		"-ss", seek, "-i", outMp4,
		"-vframes", "1",
		"-vf", "scale=-2:'min(720,ih)'",
		"-c:v", "libwebp", "-quality", "80",
		posterPath,
	}
	if out, err := exec.CommandContext(ctx, "ffmpeg", posterArgs...).CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg poster: %w (%s)", err, snippet(out, 400))
	}

	// Upload both back to MinIO.
	mp4Key := fmt.Sprintf("videos/%s/%s.mp4",
		time.Now().UTC().Format("2006/01/02"), uuid.New().String())
	if err := w.uploadFile(ctx, mp4Key, outMp4, "video/mp4"); err != nil {
		return fmt.Errorf("upload transcoded mp4: %w", err)
	}
	posterKey := fmt.Sprintf("posters/%s/%s.webp",
		time.Now().UTC().Format("2006/01/02"), uuid.New().String())
	if err := w.uploadFile(ctx, posterKey, posterPath, "image/webp"); err != nil {
		return fmt.Errorf("upload poster: %w", err)
	}

	// Update DB:
	//   original_url → transcoded mp4 (the H.264 one is what we
	//                   actually serve to all clients)
	//   thumb_url    → poster (cards / list)
	//   preview_url  → poster (detail page hero before video play)
	//   width/height → from probe (for aspect-ratio styling)
	//   file_size    → transcoded size
	//   status       → PendingReview
	st, _ := os.Stat(outMp4)
	if err := w.wpRepo.UpdateTranscoded(ctx, event.WallpaperID, repo.UpdateTranscodedInput{
		OriginalURL: w.storage.GetURL(mp4Key),
		ThumbURL:    w.storage.GetURL(posterKey),
		PreviewURL:  w.storage.GetURL(posterKey),
		Width:       probe.Width,
		Height:      probe.Height,
		FileSize:    st.Size(),
		FileType:    "video/mp4",
	}); err != nil {
		return fmt.Errorf("update wallpaper row: %w", err)
	}

	slog.Info("transcode: done",
		"wallpaper_id", event.WallpaperID,
		"width", probe.Width, "height", probe.Height,
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

type probeResult struct {
	Width    int
	Height   int
	Duration float64
}

// ffprobe returns dimensions + duration of the first video stream.
// Plain `ffprobe` JSON output keeps the parsing trivial.
func ffprobe(ctx context.Context, path string) (probeResult, error) {
	args := []string{
		"-v", "error",
		"-select_streams", "v:0",
		"-show_entries", "stream=width,height,duration:format=duration",
		"-print_format", "json",
		path,
	}
	out, err := exec.CommandContext(ctx, "ffprobe", args...).Output()
	if err != nil {
		return probeResult{}, fmt.Errorf("ffprobe: %w", err)
	}
	var parsed struct {
		Streams []struct {
			Width    int    `json:"width"`
			Height   int    `json:"height"`
			Duration string `json:"duration"`
		} `json:"streams"`
		Format struct {
			Duration string `json:"duration"`
		} `json:"format"`
	}
	if err := json.Unmarshal(out, &parsed); err != nil {
		return probeResult{}, fmt.Errorf("ffprobe parse: %w", err)
	}
	if len(parsed.Streams) == 0 {
		return probeResult{}, fmt.Errorf("ffprobe found no video streams")
	}
	r := probeResult{
		Width:  parsed.Streams[0].Width,
		Height: parsed.Streams[0].Height,
	}
	// Stream-level duration is empty on some containers; fall back
	// to format-level.
	if d, err := strconv.ParseFloat(parsed.Streams[0].Duration, 64); err == nil {
		r.Duration = d
	} else if d, err := strconv.ParseFloat(parsed.Format.Duration, 64); err == nil {
		r.Duration = d
	}
	return r, nil
}

func snippet(b []byte, n int) string {
	if len(b) <= n {
		return string(bytes.TrimSpace(b))
	}
	return string(bytes.TrimSpace(b[:n])) + "…"
}
