package service

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"path"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/segmentio/kafka-go"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

type WallpaperService struct {
	wallpaperRepo   *repo.WallpaperRepo
	tagRepo         *repo.TagRepo
	interactionRepo *repo.InteractionRepo
	userRepo        *repo.UserRepo
	storage         *storage.Storage
	kafkaWriter     *kafka.Writer
}

func NewWallpaperService(
	wr *repo.WallpaperRepo,
	tr *repo.TagRepo,
	ir *repo.InteractionRepo,
	ur *repo.UserRepo,
	st *storage.Storage,
	kw *kafka.Writer,
) *WallpaperService {
	return &WallpaperService{
		wallpaperRepo:   wr,
		tagRepo:         tr,
		interactionRepo: ir,
		userRepo:        ur,
		storage:         st,
		kafkaWriter:     kw,
	}
}

type UploadRequest struct {
	Title       string
	Description string
	CategoryID  int64
	Tags        []string
	File        io.Reader
	FileSize    int64
	FileType    string
	FileName    string
}

type WallpaperDetail struct {
	model.Wallpaper
	Tags        []model.Tag `json:"tags"`
	IsLiked     bool        `json:"is_liked"`
	IsFavorited bool        `json:"is_favorited"`
	Uploader    *model.User `json:"uploader"`
}

type ListResponse struct {
	Items      []model.Wallpaper `json:"items"`
	NextCursor int64             `json:"next_cursor"`
	HasMore    bool              `json:"has_more"`
}

type WallpaperUploadedEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	UserID      int64  `json:"user_id"`
	OriginalURL string `json:"original_url"`
	Timestamp   string `json:"timestamp"`
}

type WallpaperStatsEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	EventType   string `json:"event_type"`
	UserID      int64  `json:"user_id"`
	Timestamp   string `json:"timestamp"`
}

func (s *WallpaperService) Upload(ctx context.Context, userID int64, req UploadRequest) (*model.Wallpaper, *errcode.ErrCode) {
	ext := path.Ext(req.FileName)
	objectName := "originals/" + time.Now().UTC().Format("2006/01/02") + "/" + uuid.New().String() + ext

	if err := s.storage.Upload(ctx, objectName, req.File, req.FileSize, req.FileType); err != nil {
		slog.ErrorContext(ctx, "failed to upload file to storage", "error", err)
		return nil, errcode.ErrUploadFailed
	}
	originalURL := s.storage.GetURL(objectName)

	w := &model.Wallpaper{
		UserID:      userID,
		Title:       req.Title,
		Description: req.Description,
		CategoryID:  req.CategoryID,
		OriginalURL: originalURL,
		Status:      model.WallpaperStatusProcessing,
		FileSize:    req.FileSize,
		FileType:    req.FileType,
	}

	if err := s.wallpaperRepo.Create(ctx, w); err != nil {
		slog.ErrorContext(ctx, "failed to create wallpaper record", "error", err)
		return nil, errcode.ErrInternal
	}

	if len(req.Tags) > 0 {
		tagIDs := make([]int64, 0, len(req.Tags))
		for _, tagName := range req.Tags {
			tag, err := s.tagRepo.GetOrCreate(ctx, tagName)
			if err != nil {
				slog.ErrorContext(ctx, "failed to get or create tag",
					"error", err, "tag_name", tagName)
				return nil, errcode.ErrInternal
			}
			tagIDs = append(tagIDs, tag.ID)
		}
		if err := s.tagRepo.SetWallpaperTags(ctx, w.ID, tagIDs); err != nil {
			slog.ErrorContext(ctx, "failed to set wallpaper tags", "error", err)
			return nil, errcode.ErrInternal
		}
	}

	s.publishUploadedEvent(ctx, w, userID, originalURL)

	return w, nil
}

func (s *WallpaperService) Get(ctx context.Context, id int64, currentUserID int64) (*WallpaperDetail, *errcode.ErrCode) {
	w, err := s.wallpaperRepo.GetByID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", id)
		return nil, errcode.ErrInternal
	}
	if w == nil {
		return nil, errcode.ErrNotFound
	}

	tags, err := s.tagRepo.GetByWallpaperID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper tags",
			"error", err, "wallpaper_id", id)
		return nil, errcode.ErrInternal
	}

	uploader, err := s.userRepo.GetByID(ctx, w.UserID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get uploader",
			"error", err, "user_id", w.UserID)
		return nil, errcode.ErrInternal
	}

	detail := &WallpaperDetail{
		Wallpaper: *w,
		Tags:      tags,
		Uploader:  uploader,
	}

	if currentUserID > 0 {
		liked, err := s.interactionRepo.IsLiked(ctx, currentUserID, id)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check like status", "error", err)
			return nil, errcode.ErrInternal
		}
		detail.IsLiked = liked

		favorited, err := s.interactionRepo.IsFavorited(ctx, currentUserID, id)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check favorite status", "error", err)
			return nil, errcode.ErrInternal
		}
		detail.IsFavorited = favorited
	}

	return detail, nil
}

func (s *WallpaperService) List(ctx context.Context, opts repo.ListOptions) (*ListResponse, *errcode.ErrCode) {
	if opts.Limit <= 0 || opts.Limit > 100 {
		opts.Limit = 20
	}

	// Fetch one extra to determine if more pages exist
	fetchLimit := opts.Limit + 1
	opts.Limit = fetchLimit

	items, err := s.wallpaperRepo.List(ctx, opts)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list wallpapers", "error", err)
		return nil, errcode.ErrInternal
	}

	hasMore := len(items) == fetchLimit
	if hasMore {
		items = items[:len(items)-1]
	}

	var nextCursor int64
	if hasMore && len(items) > 0 {
		nextCursor = items[len(items)-1].ID
	}

	return &ListResponse{
		Items:      items,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, nil
}

func (s *WallpaperService) Delete(ctx context.Context, id int64, userID int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", id)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}
	if w.UserID != userID {
		return errcode.ErrForbidden
	}

	if err := s.wallpaperRepo.Delete(ctx, id); err != nil {
		slog.ErrorContext(ctx, "failed to delete wallpaper",
			"error", err, "wallpaper_id", id)
		return errcode.ErrInternal
	}
	return nil
}

func (s *WallpaperService) Like(ctx context.Context, userID, wallpaperID int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}

	if err := s.interactionRepo.Like(ctx, userID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to like wallpaper", "error", err)
		return errcode.ErrInternal
	}
	if err := s.wallpaperRepo.IncrementCounter(ctx, wallpaperID, "like_count", 1); err != nil {
		slog.ErrorContext(ctx, "failed to increment like count", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *WallpaperService) Unlike(ctx context.Context, userID, wallpaperID int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}

	if err := s.interactionRepo.Unlike(ctx, userID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to unlike wallpaper", "error", err)
		return errcode.ErrInternal
	}
	if err := s.wallpaperRepo.IncrementCounter(ctx, wallpaperID, "like_count", -1); err != nil {
		slog.ErrorContext(ctx, "failed to decrement like count", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *WallpaperService) Favorite(ctx context.Context, userID, wallpaperID int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}

	if err := s.interactionRepo.Favorite(ctx, userID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to favorite wallpaper", "error", err)
		return errcode.ErrInternal
	}
	if err := s.wallpaperRepo.IncrementCounter(ctx, wallpaperID, "favorite_count", 1); err != nil {
		slog.ErrorContext(ctx, "failed to increment favorite count", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *WallpaperService) Unfavorite(ctx context.Context, userID, wallpaperID int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}

	if err := s.interactionRepo.Unfavorite(ctx, userID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to unfavorite wallpaper", "error", err)
		return errcode.ErrInternal
	}
	if err := s.wallpaperRepo.IncrementCounter(ctx, wallpaperID, "favorite_count", -1); err != nil {
		slog.ErrorContext(ctx, "failed to decrement favorite count", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *WallpaperService) Download(ctx context.Context, wallpaperID int64) (string, *errcode.ErrCode) {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return "", errcode.ErrInternal
	}
	if w == nil {
		return "", errcode.ErrNotFound
	}

	s.publishStatsEvent(ctx, wallpaperID, "download", 0)

	return w.OriginalURL, nil
}

func (s *WallpaperService) publishUploadedEvent(ctx context.Context, w *model.Wallpaper, userID int64, originalURL string) {
	event := WallpaperUploadedEvent{
		WallpaperID: w.ID,
		UserID:      userID,
		OriginalURL: originalURL,
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
	}
	data, err := json.Marshal(event)
	if err != nil {
		slog.ErrorContext(ctx, "failed to marshal wallpaper uploaded event", "error", err)
		return
	}
	if err := s.kafkaWriter.WriteMessages(ctx, kafka.Message{
		Topic: "wallpaper.uploaded",
		Key:   []byte(strconv.FormatInt(w.ID, 10)),
		Value: data,
	}); err != nil {
		slog.ErrorContext(ctx, "failed to publish wallpaper uploaded event", "error", err)
	}
}

func (s *WallpaperService) publishStatsEvent(ctx context.Context, wallpaperID int64, eventType string, userID int64) {
	event := WallpaperStatsEvent{
		WallpaperID: wallpaperID,
		EventType:   eventType,
		UserID:      userID,
		Timestamp:   time.Now().UTC().Format(time.RFC3339),
	}
	data, err := json.Marshal(event)
	if err != nil {
		slog.ErrorContext(ctx, "failed to marshal stats event", "error", err)
		return
	}
	if err := s.kafkaWriter.WriteMessages(ctx, kafka.Message{
		Topic: "wallpaper.stats",
		Key:   []byte(strconv.FormatInt(wallpaperID, 10)),
		Value: data,
	}); err != nil {
		slog.ErrorContext(ctx, "failed to publish stats event", "error", err)
	}
}
