package service

import (
	"context"
	"fmt"
	"mime"
	"path"

	"github.com/wallpaper/backend/internal/pkg/errcode"
)

const (
	MediaKindOriginal = "original"
)

type MediaAsset struct {
	ObjectKey   string
	Filename    string
	ContentType string
}

// ResolveMediaAsset maps a signed, opaque media claim back to a current DB
// record. Object keys never need to appear in browser-visible URLs.
func (s *WallpaperService) ResolveMediaAsset(ctx context.Context, wallpaperID int64, kind string) (*MediaAsset, *errcode.ErrCode) {
	wp, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		return nil, errcode.ErrInternal
	}
	if wp == nil {
		return nil, errcode.ErrNotFound
	}

	if kind != MediaKindOriginal {
		return nil, errcode.ErrNotFound
	}
	rawURL := wp.OriginalURL
	contentType := wp.FileType

	objectKey := s.storage.ObjectKeyFromURL(rawURL)
	if objectKey == "" {
		return nil, errcode.ErrNotFound
	}
	ext := path.Ext(objectKey)
	if ext == "" {
		if exts, _ := mime.ExtensionsByType(contentType); len(exts) > 0 {
			ext = exts[0]
		}
	}
	return &MediaAsset{
		ObjectKey:   objectKey,
		Filename:    fmt.Sprintf("wallpaper_%d%s", wallpaperID, ext),
		ContentType: contentType,
	}, nil
}
