package worker

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"image"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	_ "github.com/gen2brain/heic"
	"github.com/google/uuid"
	"github.com/nfnt/resize"
	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

type ImageWorker struct {
	reader     *kafka.Reader
	wpRepo     *repo.WallpaperRepo
	deviceRepo *repo.DeviceRepo
	storage    *storage.Storage
}

func NewImageWorker(brokers []string, wpRepo *repo.WallpaperRepo, deviceRepo *repo.DeviceRepo, st *storage.Storage) *ImageWorker {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  brokers,
		Topic:    "wallpaper.uploaded",
		GroupID:  "image-worker",
		MinBytes: 1,
		MaxBytes: 10e6,
	})
	return &ImageWorker{reader: reader, wpRepo: wpRepo, deviceRepo: deviceRepo, storage: st}
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

		if err := w.processImage(ctx, event); err != nil {
			slog.Error("process image failed",
				"wallpaper_id", event.WallpaperID,
				"error", err,
			)
			if updateErr := w.wpRepo.UpdateStatus(ctx, event.WallpaperID, model.WallpaperStatusFailed); updateErr != nil {
				slog.Error("update status failed", "error", updateErr)
			}
		}

		if err := w.reader.CommitMessages(ctx, msg); err != nil {
			slog.Error("commit message failed", "error", err)
		}
	}
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
		if err := jpeg.Encode(buf, resized, &jpeg.Options{Quality: 80}); err != nil {
			continue
		}

		key := fmt.Sprintf("frames/%s.jpg", uuid.New().String())
		if err := w.storage.Upload(ctx, key, buf, int64(buf.Len()), "image/jpeg"); err != nil {
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

	return nil
}

func (w *ImageWorker) generateThumbAndPreview(ctx context.Context, img image.Image, format string, wallpaperID int64, origW, origH int, dominantColor, colorPalette string) error {
	// thumb: fits within 400×300, JPEG q≈85. Tiny file (~30KB), used as the
	// first-paint placeholder in the home card so something appears instantly
	// while the larger card image streams in.
	thumb := resize.Thumbnail(400, 300, img, resize.Lanczos3)
	thumbBuf := new(bytes.Buffer)
	if err := encodeImage(thumbBuf, thumb, format); err != nil {
		return fmt.Errorf("encode thumb: %w", err)
	}
	thumbKey := fmt.Sprintf("thumbs/%s.jpg", uuid.New().String())
	if err := w.storage.Upload(ctx, thumbKey, thumbBuf, int64(thumbBuf.Len()), "image/jpeg"); err != nil {
		return fmt.Errorf("upload thumb: %w", err)
	}

	bounds := img.Bounds()

	// preview: 1600px wide, watermarked, JPEG q=80. Serves *both* the home card
	// (loaded after the 400px thumb LQIP fades in) and the detail-page hero —
	// loading it once on the home feed means the browser HTTP cache already has
	// it when the user opens a detail page, so detail navigation is instant.
	previewWidth := uint(1600)
	if bounds.Dx() < 1600 {
		previewWidth = uint(bounds.Dx())
	}
	preview := resize.Resize(previewWidth, 0, img, resize.Lanczos3)
	watermarked := addWatermark(preview)
	previewBuf := new(bytes.Buffer)
	if err := jpeg.Encode(previewBuf, watermarked, &jpeg.Options{Quality: 80}); err != nil {
		return fmt.Errorf("encode preview: %w", err)
	}
	previewKey := fmt.Sprintf("previews/%s.jpg", uuid.New().String())
	if err := w.storage.Upload(ctx, previewKey, previewBuf, int64(previewBuf.Len()), "image/jpeg"); err != nil {
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
		if err := jpeg.Encode(buf, resized, &jpeg.Options{Quality: 90}); err != nil {
			slog.Error("encode variant failed",
				"wallpaper_id", wallpaperID,
				"device", dev.Name,
				"error", err,
			)
			continue
		}

		objKey := fmt.Sprintf("variants/%s.jpg", uuid.New().String())
		fileSize := int64(buf.Len())
		if err := w.storage.Upload(ctx, objKey, buf, fileSize, "image/jpeg"); err != nil {
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

func encodeImage(buf *bytes.Buffer, img image.Image, format string) error {
	switch format {
	case "png":
		return png.Encode(buf, img)
	default:
		return jpeg.Encode(buf, img, &jpeg.Options{Quality: 85})
	}
}

func (w *ImageWorker) Close() error {
	return w.reader.Close()
}
