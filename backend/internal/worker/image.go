package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/draw"
	_ "image/jpeg" // register JPEG decoder for image.Decode (originals are often JPEG)
	_ "image/png"  // register PNG decoder for image.Decode
	"io"
	"log/slog"
	"math/bits"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/chai2010/webp"
	"github.com/corona10/goimagehash"
	_ "github.com/gen2brain/heic"
	"github.com/google/uuid"
	"github.com/nfnt/resize"
	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/indexnow"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

type ImageWorker struct {
	reader     *kafka.Reader
	wpRepo     *repo.WallpaperRepo
	deviceRepo *repo.DeviceRepo
	jobRepo    *repo.WorkerJobRepo
	storage    *storage.Storage
	indexNow   *indexnow.Client // optional; nil means no notifier
	siteURL    string           // canonical origin used to build feed/sitemap URLs
}

func NewImageWorker(
	brokers []string,
	wpRepo *repo.WallpaperRepo,
	deviceRepo *repo.DeviceRepo,
	jobRepo *repo.WorkerJobRepo,
	st *storage.Storage,
	idx *indexnow.Client,
	siteURL string,
) *ImageWorker {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  brokers,
		Topic:    "wallpaper.uploaded",
		GroupID:  "image-worker",
		MinBytes: 1,
		MaxBytes: 10e6,
	})
	return &ImageWorker{
		reader:     reader,
		wpRepo:     wpRepo,
		deviceRepo: deviceRepo,
		jobRepo:    jobRepo,
		storage:    st,
		indexNow:   idx,
		siteURL:    siteURL,
	}
}

type WallpaperUploadedEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	UserID      int64  `json:"user_id"`
	ObjectKey   string `json:"object_key"`
	Timestamp   string `json:"timestamp"`
}

func (w *ImageWorker) Run(ctx context.Context) error {
	slog.Info("image worker started")
	for {
		msg, err := w.reader.FetchMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			slog.Error("fetch message failed", "error", err)
			continue
		}

		var event WallpaperUploadedEvent
		if err := json.Unmarshal(msg.Value, &event); err != nil {
			slog.Error("unmarshal event failed", "error", err)
			if commitErr := w.reader.CommitMessages(ctx, msg); commitErr != nil {
				slog.Error("commit message failed", "error", commitErr)
			}
			continue
		}

		jobID, jobErr := w.jobRepo.Start(ctx, "image", "wallpaper.uploaded", event.WallpaperID)
		if jobErr != nil {
			slog.WarnContext(ctx, "worker_jobs start failed (non-fatal)", "wallpaper_id", event.WallpaperID, "error", jobErr)
		}

		if err := w.processImage(ctx, event); err != nil {
			slog.Error("process image failed",
				"wallpaper_id", event.WallpaperID,
				"error", err,
			)
			if updateErr := w.wpRepo.UpdateStatus(ctx, event.WallpaperID, model.WallpaperStatusFailed); updateErr != nil {
				slog.Error("update status failed", "error", updateErr)
			}
			if finErr := w.jobRepo.Finish(ctx, jobID, "failed", err.Error()); finErr != nil {
				slog.WarnContext(ctx, "worker_jobs finish(failed) failed", "wallpaper_id", event.WallpaperID, "error", finErr)
			}
		} else {
			if finErr := w.jobRepo.Finish(ctx, jobID, "done", ""); finErr != nil {
				slog.WarnContext(ctx, "worker_jobs finish(done) failed", "wallpaper_id", event.WallpaperID, "error", finErr)
			}
			// Newly-published wallpaper → ping IndexNow so Bing/Yandex
			// don't have to wait for a crawl to discover it. No-op if
			// the client isn't configured.
			w.notifyIndexNow(ctx, event.WallpaperID)
		}

		if err := w.reader.CommitMessages(ctx, msg); err != nil {
			slog.Error("commit message failed", "error", err)
		}
	}
}

// dupHammingThreshold is the max Hamming distance (out of 64 bits) below which
// two perceptual hashes are considered the same image. 5 is the value used by
// most pHash-based dedup implementations.
const dupHammingThreshold = 5

func (w *ImageWorker) isDuplicate(ctx context.Context, img image.Image, wallpaperID int64) bool {
	h, err := goimagehash.PerceptionHash(img)
	if err != nil {
		slog.WarnContext(ctx, "phash compute failed (skipping dedup)", "wallpaper_id", wallpaperID, "error", err)
		return false
	}
	hashVal := int64(h.GetHash())

	entries, err := w.wpRepo.ListPublishedPhashes(ctx, wallpaperID)
	if err != nil {
		slog.WarnContext(ctx, "phash list failed (skipping dedup)", "wallpaper_id", wallpaperID, "error", err)
		return false
	}
	for _, e := range entries {
		if bits.OnesCount64(uint64(hashVal^e.Phash)) <= dupHammingThreshold {
			slog.InfoContext(ctx, "duplicate wallpaper detected",
				"wallpaper_id", wallpaperID,
				"matches_id", e.ID,
				"hamming", bits.OnesCount64(uint64(hashVal^e.Phash)),
			)
			if err := w.wpRepo.SetStatus(ctx, wallpaperID, model.WallpaperStatusDuplicate); err != nil {
				slog.ErrorContext(ctx, "set duplicate status failed", "wallpaper_id", wallpaperID, "error", err)
			}
			return true
		}
	}

	if err := w.wpRepo.SetPhash(ctx, wallpaperID, hashVal); err != nil {
		slog.WarnContext(ctx, "set phash failed (non-fatal)", "wallpaper_id", wallpaperID, "error", err)
	}
	return false
}

func detectDynamicType(data []byte) string {
	if bytes.Contains(data, []byte("apple_desktop:solar")) {
		return "solar"
	}
	if bytes.Contains(data, []byte("apple_desktop:h24")) {
		return "h24"
	}
	if bytes.Contains(data, []byte("apple_desktop:apr")) {
		return "apr"
	}
	return ""
}

// extractDynamicFrames uses heif-convert to extract all frames from a dynamic
// HEIC file, resizes each to preview width, and uploads to storage.
// Returns a list of frame URLs. Non-fatal: returns empty slice on failure.
func (w *ImageWorker) extractDynamicFrames(ctx context.Context, data []byte, wallpaperID int64) []string {
	if _, err := exec.LookPath("heif-convert"); err != nil {
		slog.Warn("heif-convert not available, skipping frame extraction", "wallpaper_id", wallpaperID)
		return nil
	}

	tmpDir, err := os.MkdirTemp("", fmt.Sprintf("heic-frames-%d-*", wallpaperID))
	if err != nil {
		slog.Error("create temp dir failed", "error", err)
		return nil
	}
	defer os.RemoveAll(tmpDir)

	inputPath := filepath.Join(tmpDir, "input.heic")
	if err := os.WriteFile(inputPath, data, 0644); err != nil {
		slog.Error("write temp heic failed", "error", err)
		return nil
	}

	outputBase := filepath.Join(tmpDir, "frame.jpg")
	cmd := exec.CommandContext(ctx, "heif-convert", "-q", "85", inputPath, outputBase)
	if out, err := cmd.CombinedOutput(); err != nil {
		slog.Error("heif-convert failed", "error", err, "output", string(out))
		return nil
	}

	matches, _ := filepath.Glob(filepath.Join(tmpDir, "frame*.jpg"))
	if len(matches) <= 1 {
		return nil
	}

	sort.Slice(matches, func(i, j int) bool {
		return extractFrameIndex(matches[i]) < extractFrameIndex(matches[j])
	})

	var urls []string
	for i, path := range matches {
		f, err := os.Open(path)
		if err != nil {
			continue
		}
		fImg, _, err := image.Decode(f)
		f.Close()
		if err != nil {
			continue
		}

		previewWidth := uint(1600)
		if fImg.Bounds().Dx() < 1600 {
			previewWidth = uint(fImg.Bounds().Dx())
		}
		resized := resize.Resize(previewWidth, 0, fImg, resize.Lanczos3)

		buf := new(bytes.Buffer)
		if err := webp.Encode(buf, resized, &webp.Options{Quality: 80}); err != nil {
			continue
		}

		key := fmt.Sprintf("frames/%s.webp", uuid.New().String())
		if err := w.storage.Upload(ctx, key, buf, int64(buf.Len()), "image/webp"); err != nil {
			slog.Error("upload frame failed", "wallpaper_id", wallpaperID, "frame", i, "error", err)
			continue
		}
		urls = append(urls, w.storage.GetURL(key))
	}

	slog.Info("dynamic frames extracted", "wallpaper_id", wallpaperID, "count", len(urls))
	return urls
}

func extractFrameIndex(path string) int {
	base := filepath.Base(path)
	base = strings.TrimSuffix(base, filepath.Ext(base))
	parts := strings.Split(base, "-")
	if len(parts) < 2 {
		return 0
	}
	n, _ := strconv.Atoi(parts[len(parts)-1])
	return n
}

func (w *ImageWorker) processImage(ctx context.Context, event WallpaperUploadedEvent) error {
	obj, err := w.storage.GetObject(ctx, event.ObjectKey)
	if err != nil {
		return fmt.Errorf("get original: %w", err)
	}
	defer obj.Close()

	data, err := io.ReadAll(obj)
	if err != nil {
		return fmt.Errorf("read original: %w", err)
	}

	dynType := detectDynamicType(data)
	isDynamic := dynType != ""

	img, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return fmt.Errorf("decode image: %w", err)
	}

	bounds := img.Bounds()
	origW, origH := bounds.Dx(), bounds.Dy()

	dominantColor, colorPalette := extractColors(img)

	if w.isDuplicate(ctx, img, event.WallpaperID) {
		// Marked status=duplicate already; skip variants so the file
		// never gets a public URL.
		return nil
	}

	// Idempotency for reprocess: if this wallpaper was already processed
	// before (an admin re-queued it, or a one-off recompress pass is
	// running), wipe the previous-generation artifacts so we don't leave
	// orphaned MinIO objects and duplicate wallpaper_variants rows
	// behind. First-time processing finds no artifacts and this is a
	// no-op. Failure is non-fatal — better to leave orphans than refuse
	// to regenerate.
	w.cleanupOldArtifacts(ctx, event.WallpaperID)

	if err := w.generateThumbAndPreview(ctx, img, format, event.WallpaperID, origW, origH, dominantColor, colorPalette); err != nil {
		return fmt.Errorf("thumb/preview: %w", err)
	}

	if isDynamic {
		frameURLs := w.extractDynamicFrames(ctx, data, event.WallpaperID)
		if err := w.wpRepo.UpdateDynamic(ctx, event.WallpaperID, true, dynType, strings.Join(frameURLs, ",")); err != nil {
			return fmt.Errorf("update dynamic: %w", err)
		}
		slog.Info("dynamic wallpaper processed",
			"wallpaper_id", event.WallpaperID,
			"dynamic_type", dynType,
			"frames", len(frameURLs),
			"original_size", fmt.Sprintf("%dx%d", origW, origH),
		)
	} else {
		if err := w.generateDeviceVariants(ctx, img, format, event.WallpaperID, origW, origH); err != nil {
			slog.Error("device variants partially failed (non-fatal)",
				"wallpaper_id", event.WallpaperID,
				"error", err,
			)
		}
		slog.Info("image processed",
			"wallpaper_id", event.WallpaperID,
			"original_size", fmt.Sprintf("%dx%d", origW, origH),
			"format", format,
		)
	}

	// Inline autotag (worker → Anthropic) used to run here, but the prod
	// host's IP is blocked by Anthropic with 403 "Request not allowed".
	// Classification now happens out-of-band from a developer Mac via
	// scripts/autotag-prod.sh (SSH-tunneled DB + local Claude access).
	return nil
}

func (w *ImageWorker) generateThumbAndPreview(ctx context.Context, img image.Image, format string, wallpaperID int64, origW, origH int, dominantColor, colorPalette string) error {
	// All derived assets (thumb, preview, variants, dynamic frames) are
	// encoded as WebP q=80 — the format is supported by every browser and
	// macOS 11+ NSImage natively, and saves ~25–30% over equivalent-quality
	// JPEG. Originals are kept in their uploaded format and never re-encoded.
	thumb := resize.Thumbnail(400, 300, img, resize.Lanczos3)
	thumbBuf := new(bytes.Buffer)
	if err := webp.Encode(thumbBuf, thumb, &webp.Options{Quality: 80}); err != nil {
		return fmt.Errorf("encode thumb: %w", err)
	}
	thumbKey := fmt.Sprintf("thumbs/%s.webp", uuid.New().String())
	if err := w.storage.Upload(ctx, thumbKey, thumbBuf, int64(thumbBuf.Len()), "image/webp"); err != nil {
		return fmt.Errorf("upload thumb: %w", err)
	}

	bounds := img.Bounds()

	// preview: 1600px wide, watermarked. Serves *both* the home card (loaded
	// after the 400px thumb LQIP fades in) and the detail-page hero — loading
	// it once on the home feed means the browser HTTP cache already has it
	// when the user opens a detail page, so detail navigation is instant.
	previewWidth := uint(1600)
	if bounds.Dx() < 1600 {
		previewWidth = uint(bounds.Dx())
	}
	preview := resize.Resize(previewWidth, 0, img, resize.Lanczos3)
	watermarked := addWatermark(preview)
	previewBuf := new(bytes.Buffer)
	if err := webp.Encode(previewBuf, watermarked, &webp.Options{Quality: 80}); err != nil {
		return fmt.Errorf("encode preview: %w", err)
	}
	previewKey := fmt.Sprintf("previews/%s.webp", uuid.New().String())
	if err := w.storage.Upload(ctx, previewKey, previewBuf, int64(previewBuf.Len()), "image/webp"); err != nil {
		return fmt.Errorf("upload preview: %w", err)
	}

	if err := w.wpRepo.UpdateProcessed(ctx, wallpaperID,
		w.storage.GetURL(thumbKey), w.storage.GetURL(previewKey),
		origW, origH, dominantColor, colorPalette); err != nil {
		return fmt.Errorf("update processed: %w", err)
	}
	return nil
}

func (w *ImageWorker) generateDeviceVariants(ctx context.Context, img image.Image, format string, wallpaperID int64, origW, origH int) error {
	devices, err := w.deviceRepo.ListActive(ctx)
	if err != nil {
		return fmt.Errorf("list devices: %w", err)
	}

	var variants []model.WallpaperVariant
	for _, dev := range devices {
		if origW < dev.Width || origH < dev.Height {
			slog.Debug("skipping device (original too small)",
				"wallpaper_id", wallpaperID,
				"device", dev.Name,
				"need", fmt.Sprintf("%dx%d", dev.Width, dev.Height),
				"have", fmt.Sprintf("%dx%d", origW, origH),
			)
			continue
		}

		resized := coverResize(img, dev.Width, dev.Height)
		buf := new(bytes.Buffer)
		// WebP q=80 is roughly visually equivalent to JPEG q=85 while
		// saving another 25–30% on top — variants dominate MinIO storage,
		// so the compounding effect matters here even if the per-image
		// difference is small.
		if err := webp.Encode(buf, resized, &webp.Options{Quality: 80}); err != nil {
			slog.Error("encode variant failed",
				"wallpaper_id", wallpaperID,
				"device", dev.Name,
				"error", err,
			)
			continue
		}

		objKey := fmt.Sprintf("variants/%s.webp", uuid.New().String())
		fileSize := int64(buf.Len())
		if err := w.storage.Upload(ctx, objKey, buf, fileSize, "image/webp"); err != nil {
			slog.Error("upload variant failed",
				"wallpaper_id", wallpaperID,
				"device", dev.Name,
				"error", err,
			)
			continue
		}

		variants = append(variants, model.WallpaperVariant{
			WallpaperID: wallpaperID,
			DeviceID:    dev.ID,
			URL:         w.storage.GetURL(objKey),
			Width:       dev.Width,
			Height:      dev.Height,
			FileSize:    fileSize,
		})

		slog.Info("variant generated",
			"wallpaper_id", wallpaperID,
			"device", dev.Name,
			"size", fmt.Sprintf("%dx%d", dev.Width, dev.Height),
		)
	}

	if len(variants) > 0 {
		if err := w.deviceRepo.CreateVariants(ctx, variants); err != nil {
			return fmt.Errorf("save variants: %w", err)
		}
	}

	slog.Info("device variants done",
		"wallpaper_id", wallpaperID,
		"generated", len(variants),
		"skipped", len(devices)-len(variants),
	)
	return nil
}

// coverResize scales the image to cover the target dimensions, then center-crops.
func coverResize(img image.Image, targetW, targetH int) image.Image {
	bounds := img.Bounds()
	srcW, srcH := bounds.Dx(), bounds.Dy()

	scaleW := float64(targetW) / float64(srcW)
	scaleH := float64(targetH) / float64(srcH)
	scale := scaleW
	if scaleH > scaleW {
		scale = scaleH
	}

	newW := uint(float64(srcW) * scale)
	newH := uint(float64(srcH) * scale)
	scaled := resize.Resize(newW, newH, img, resize.Lanczos3)

	scaledBounds := scaled.Bounds()
	offsetX := (scaledBounds.Dx() - targetW) / 2
	offsetY := (scaledBounds.Dy() - targetH) / 2
	cropRect := image.Rect(0, 0, targetW, targetH)

	cropped := image.NewRGBA(cropRect)
	draw.Draw(cropped, cropRect, scaled, image.Pt(scaledBounds.Min.X+offsetX, scaledBounds.Min.Y+offsetY), draw.Src)

	return cropped
}

func (w *ImageWorker) Close() error {
	return w.reader.Close()
}

// cleanupOldArtifacts removes any artifacts from a previous processing run
// of the same wallpaper — thumb, preview, dynamic frames, and every device
// variant (DB row + MinIO object). Called at the top of processImage so the
// reprocess path doesn't leak orphans into MinIO. Best-effort: a failure
// here logs and keeps going, since the goal is regeneration, not cleanup.
func (w *ImageWorker) cleanupOldArtifacts(ctx context.Context, wallpaperID int64) {
	wp, err := w.wpRepo.GetByIDAnyStatus(ctx, wallpaperID)
	if err != nil || wp == nil {
		if err != nil {
			slog.WarnContext(ctx, "cleanup: lookup failed", "wallpaper_id", wallpaperID, "error", err)
		}
		return
	}

	urls := []string{wp.ThumbURL, wp.PreviewURL}
	if wp.FrameURLs != "" {
		for _, u := range strings.Split(wp.FrameURLs, ",") {
			if u = strings.TrimSpace(u); u != "" {
				urls = append(urls, u)
			}
		}
	}

	variants, err := w.deviceRepo.ListVariantsByWallpaper(ctx, wallpaperID)
	if err != nil {
		slog.WarnContext(ctx, "cleanup: list variants failed", "wallpaper_id", wallpaperID, "error", err)
	}
	for _, v := range variants {
		urls = append(urls, v.URL)
	}

	for _, u := range urls {
		key := w.storage.ObjectKeyFromURL(u)
		if key == "" {
			continue
		}
		if err := w.storage.Delete(ctx, key); err != nil {
			slog.WarnContext(ctx, "cleanup: minio delete failed", "key", key, "error", err)
		}
	}

	if len(variants) > 0 {
		if err := w.deviceRepo.DeleteVariantsByWallpaper(ctx, wallpaperID); err != nil {
			slog.WarnContext(ctx, "cleanup: db variant delete failed", "wallpaper_id", wallpaperID, "error", err)
		}
	}
}

// notifyIndexNow looks up the published wallpaper's slug and posts the
// detail URL to IndexNow asynchronously. Best-effort: any error is
// logged inside the indexnow client and never propagated.
func (w *ImageWorker) notifyIndexNow(ctx context.Context, wallpaperID int64) {
	if w.indexNow == nil || !w.indexNow.Enabled() || w.siteURL == "" {
		return
	}
	wp, err := w.wpRepo.GetByIDAnyStatus(ctx, wallpaperID)
	if err != nil || wp == nil || wp.Slug == "" {
		return
	}
	w.indexNow.SubmitAsync([]string{w.siteURL + "/wallpaper/" + wp.Slug})
}
