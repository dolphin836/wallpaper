// [skill: go-team-standards · go-style] downloads always serve the original; device list powers preview filtering
package service

import (
	"context"
	"log/slog"
	"strings"

	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/variant"
	"github.com/wallpaper/backend/internal/repo"
)

func isVideoType(fileType string) bool {
	return strings.HasPrefix(fileType, "video/")
}

// SupportedDevice is one entry in a wallpaper's device picker. Its shape
// mirrors the legacy variant-list response the detail page already consumes
// (id doubles as the device id), so existing clients keep working. The list
// is now purely informational: it tells the client which devices the
// original can serve without upscaling — downloads always return the
// original file.
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

// ListSupportedDevices returns the devices a wallpaper fits — those whose
// resolution the original fully covers (no upscaling). This drives the
// web's multi-device preview filter and the clients' device-fit filtering.
// Dynamic and video wallpapers have no device semantics, so the list is
// empty for them.
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
// returns the original URL. The device id is validated for API compatibility
// with older clients, but no longer selects a derived file — per the
// 2026-07-05 decision, every download serves the original and clients filter
// non-fitting wallpapers instead.
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
	return w.OriginalURL, nil
}
