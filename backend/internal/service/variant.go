package service

import (
	"bytes"
	"context"
	"fmt"
	"image"
	"image/jpeg"  // decode + encode JPEG (pure Go — no cgo in the api binary)
	_ "image/png" // register PNG decoder
	"log/slog"
	"strings"
	"time"

	_ "github.com/gen2brain/heic" // register HEIC decoder (iPhone originals)

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/variant"
	"github.com/wallpaper/backend/internal/repo"
)

// variantGenTimeout caps a single on-demand resize+upload so a slow MinIO
// round-trip can't pin a request goroutine (iron rule 13: external IO needs a
// timeout). One downscale+WebP encode is normally well under a second.
const variantGenTimeout = 30 * time.Second

func isVideoType(fileType string) bool {
	return strings.HasPrefix(fileType, "video/")
}

// SupportedDevice is one entry in a wallpaper's device picker. Its shape
// mirrors the legacy variant-list response the detail page already consumes
// (id doubles as the download key, now a device id), so the frontend didn't
// need to change when variants went lazy. No url: the page renders previews
// from the wallpaper's preview_url.
type SupportedDevice struct {
	ID         int64  `json:"id"`
	DeviceID   int64  `json:"device_id"`
	Platform   string `json:"platform"`
	Brand      string `json:"brand"`
	DeviceName string `json:"device_name"`
	DeviceSlug string `json:"device_slug"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
}

// ListSupportedDevices returns the devices a wallpaper can be downloaded for —
// those whose resolution the original fully covers (no upscaling). Dynamic and
// video wallpapers have no device variants, so the list is empty for them.
func (s *WallpaperService) ListSupportedDevices(ctx context.Context, wallpaperID int64) ([]SupportedDevice, *errcode.ErrCode) {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper", "error", err, "wallpaper_id", wallpaperID)
		return nil, errcode.ErrInternal
	}
	if w == nil {
		return nil, errcode.ErrNotFound
	}
	if w.IsDynamic || isVideoType(w.FileType) {
		return []SupportedDevice{}, nil
	}

	devices, err := s.deviceRepo.ListActive(ctx)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list devices", "error", err)
		return nil, errcode.ErrInternal
	}
	out := make([]SupportedDevice, 0, len(devices))
	for _, d := range devices {
		if variant.OriginalCoversDevice(w.Width, w.Height, d.Width, d.Height) {
			out = append(out, SupportedDevice{
				ID:         d.ID,
				DeviceID:   d.ID,
				Platform:   d.Platform,
				Brand:      d.Brand,
				DeviceName: d.Name,
				DeviceSlug: d.Slug,
				Width:      d.Width,
				Height:     d.Height,
			})
		}
	}
	return out, nil
}

// DownloadForDevice charges the download (owner exempt, first-time only) and
// returns a URL sized for the given device, materializing the variant on first
// request. Falls back to the original when the wallpaper has no device variant
// (dynamic/video) or the original can't cover the device.
func (s *WallpaperService) DownloadForDevice(ctx context.Context, wallpaperID, deviceID, userID int64, meta repo.EventMeta) (string, *errcode.ErrCode) {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper", "error", err, "wallpaper_id", wallpaperID)
		return "", errcode.ErrInternal
	}
	if w == nil {
		return "", errcode.ErrNotFound
	}

	dev, err := s.deviceRepo.GetByID(ctx, deviceID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get device", "error", err, "device_id", deviceID)
		return "", errcode.ErrInternal
	}
	if dev == nil {
		return "", errcode.ErrNotFound
	}

	if ec := s.chargeAndRecordDownload(ctx, w, userID, meta); ec != nil {
		return "", ec
	}

	if w.IsDynamic || isVideoType(w.FileType) ||
		!variant.OriginalCoversDevice(w.Width, w.Height, dev.Width, dev.Height) {
		return w.OriginalURL, nil
	}

	url, err := s.resolveOrGenerateVariant(ctx, w, dev)
	if err != nil {
		slog.ErrorContext(ctx, "variant generation failed (serving original)",
			"error", err, "wallpaper_id", wallpaperID, "device_id", deviceID)
		return w.OriginalURL, nil
	}
	return url, nil
}

// pickDeviceForTarget returns the smallest active device that both covers the
// requested width/height and is itself covered by the original — i.e. the
// least-oversized variant we can serve without upscaling. nil when none fits.
func (s *WallpaperService) pickDeviceForTarget(ctx context.Context, w *model.Wallpaper, target DownloadTarget) *model.DeviceProfile {
	devices, err := s.deviceRepo.ListActive(ctx)
	if err != nil {
		slog.WarnContext(ctx, "device lookup failed (serving original)", "error", err)
		return nil
	}
	var best *model.DeviceProfile
	bestPixels := 0
	for i := range devices {
		d := &devices[i]
		if d.Width < target.Width || d.Height < target.Height {
			continue
		}
		if !variant.OriginalCoversDevice(w.Width, w.Height, d.Width, d.Height) {
			continue
		}
		p := d.Width * d.Height
		if best == nil || p < bestPixels {
			best = d
			bestPixels = p
		}
	}
	return best
}

// resolveOrGenerateVariant returns the URL of the (wallpaper, device) variant,
// serving the cached object when present and otherwise generating it once
// (concurrent first hits collapse via singleflight).
func (s *WallpaperService) resolveOrGenerateVariant(ctx context.Context, w *model.Wallpaper, dev *model.DeviceProfile) (string, error) {
	if v, err := s.deviceRepo.GetVariantForDevice(ctx, w.ID, dev.ID); err == nil && v != nil {
		if err := s.deviceRepo.TouchVariant(ctx, v.ID); err != nil {
			slog.WarnContext(ctx, "touch variant failed", "error", err, "variant_id", v.ID)
		}
		return v.URL, nil
	}

	key := variant.ObjectKey(w.ID, dev.ID)
	res, err, _ := s.variantSF.Do(key, func() (any, error) {
		return s.generateVariant(ctx, w, dev, key)
	})
	if err != nil {
		return "", err
	}
	return res.(string), nil
}

// generateVariant downloads the original, cover-resizes it to the device size,
// encodes WebP, uploads to the derived key, and records the row. Runs on a
// detached timeout context so a cancelled HTTP request mid-singleflight can't
// abort generation already shared with other waiters.
func (s *WallpaperService) generateVariant(ctx context.Context, w *model.Wallpaper, dev *model.DeviceProfile, key string) (string, error) {
	genCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), variantGenTimeout)
	defer cancel()

	origKey := s.storage.ObjectKeyFromURL(w.OriginalURL)
	rc, err := s.storage.GetObject(genCtx, origKey)
	if err != nil {
		return "", fmt.Errorf("get original %q: %w", origKey, err)
	}
	defer rc.Close()

	img, _, err := image.Decode(rc)
	if err != nil {
		return "", fmt.Errorf("decode original: %w", err)
	}

	resized := variant.CoverResize(img, dev.Width, dev.Height)
	buf := new(bytes.Buffer)
	if err := jpeg.Encode(buf, resized, &jpeg.Options{Quality: 90}); err != nil {
		return "", fmt.Errorf("encode jpeg: %w", err)
	}
	size := int64(buf.Len())
	if err := s.storage.Upload(genCtx, key, buf, size, "image/jpeg"); err != nil {
		return "", fmt.Errorf("upload variant: %w", err)
	}

	url := s.storage.GetURL(key)
	now := time.Now().UTC()
	row := &model.WallpaperVariant{
		WallpaperID:      w.ID,
		DeviceID:         dev.ID,
		URL:              url,
		Width:            dev.Width,
		Height:           dev.Height,
		FileSize:         size,
		DownloadCount:    1,
		LastDownloadedAt: &now,
	}
	if err := s.deviceRepo.CreateVariant(genCtx, row); err != nil {
		// Object is already in MinIO; a failed row just means we'll regenerate
		// the row (overwriting the same key) on the next request. Non-fatal.
		slog.ErrorContext(genCtx, "save variant row failed", "error", err,
			"wallpaper_id", w.ID, "device_id", dev.ID)
	}
	return url, nil
}
