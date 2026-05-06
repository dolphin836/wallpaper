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

	_ "github.com/gen2brain/heic"
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
		if err := w.wpRepo.UpdateDynamic(ctx, event.WallpaperID, true, dynType); err != nil {
			return fmt.Errorf("update dynamic: %w", err)
		}
		slog.Info("dynamic wallpaper detected, skipping variant generation",
			"wallpaper_id", event.WallpaperID,
			"dynamic_type", dynType,
			"original_size", fmt.Sprintf("%dx%d", origW, origH),
			"format", format,
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
	thumb := resize.Thumbnail(300, 200, img, resize.Lanczos3)
	thumbBuf := new(bytes.Buffer)
	if err := encodeImage(thumbBuf, thumb, format); err != nil {
		return fmt.Errorf("encode thumb: %w", err)
	}
	thumbKey := fmt.Sprintf("thumbs/%d_thumb.jpg", wallpaperID)
	if err := w.storage.Upload(ctx, thumbKey, thumbBuf, int64(thumbBuf.Len()), "image/jpeg"); err != nil {
		return fmt.Errorf("upload thumb: %w", err)
	}

	bounds := img.Bounds()
	previewWidth := uint(800)
	if bounds.Dx() < 800 {
		previewWidth = uint(bounds.Dx())
	}
	preview := resize.Resize(previewWidth, 0, img, resize.Lanczos3)
	previewBuf := new(bytes.Buffer)
	if err := encodeImage(previewBuf, preview, format); err != nil {
		return fmt.Errorf("encode preview: %w", err)
	}
	previewKey := fmt.Sprintf("previews/%d_preview.jpg", wallpaperID)
	if err := w.storage.Upload(ctx, previewKey, previewBuf, int64(previewBuf.Len()), "image/jpeg"); err != nil {
		return fmt.Errorf("upload preview: %w", err)
	}

	if err := w.wpRepo.UpdateProcessed(ctx, wallpaperID,
		w.storage.GetURL(thumbKey), w.storage.GetURL(previewKey), origW, origH, dominantColor, colorPalette); err != nil {
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

		objKey := fmt.Sprintf("variants/%d/%dx%d.jpg", wallpaperID, dev.Width, dev.Height)
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
