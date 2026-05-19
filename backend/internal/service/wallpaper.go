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
	"github.com/wallpaper/backend/internal/pkg/slug"
	"github.com/wallpaper/backend/internal/pkg/storage"
	"github.com/wallpaper/backend/internal/repo"
)

type WallpaperService struct {
	wallpaperRepo   *repo.WallpaperRepo
	tagRepo         *repo.TagRepo
	interactionRepo *repo.InteractionRepo
	userRepo        *repo.UserRepo
	eventRepo       *repo.EventRepo
	coinRepo        *repo.CoinRepo
	collectionRepo  *repo.CollectionRepo
	deviceRepo      *repo.DeviceRepo
	storage         *storage.Storage
	kafkaWriter     *kafka.Writer
}

func NewWallpaperService(
	wr *repo.WallpaperRepo,
	tr *repo.TagRepo,
	ir *repo.InteractionRepo,
	ur *repo.UserRepo,
	er *repo.EventRepo,
	cr *repo.CoinRepo,
	colr *repo.CollectionRepo,
	dr *repo.DeviceRepo,
	st *storage.Storage,
	kw *kafka.Writer,
) *WallpaperService {
	return &WallpaperService{
		wallpaperRepo:   wr,
		tagRepo:         tr,
		interactionRepo: ir,
		userRepo:        ur,
		eventRepo:       er,
		coinRepo:        cr,
		collectionRepo:  colr,
		deviceRepo:      dr,
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
	Tags         []model.Tag `json:"tags"`
	IsLiked      bool        `json:"is_liked"`
	IsFavorited  bool        `json:"is_favorited"`
	IsDownloaded bool        `json:"is_downloaded"`
	Uploader     *model.User `json:"uploader"`
}

type WallpaperListItem struct {
	model.Wallpaper
	IsLiked      bool `json:"is_liked"`
	IsFavorited  bool `json:"is_favorited"`
	IsDownloaded bool `json:"is_downloaded"`
}

type ListResponse struct {
	Items      []WallpaperListItem `json:"items"`
	NextCursor int64               `json:"next_cursor"`
	HasMore    bool                `json:"has_more"`
}

type WallpaperUploadedEvent struct {
	WallpaperID int64  `json:"wallpaper_id"`
	UserID      int64  `json:"user_id"`
	ObjectKey   string `json:"object_key"`
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

	slugSource := req.Title
	if slugSource == "" {
		slugSource = req.FileName
	}
	w := &model.Wallpaper{
		Slug:        slug.FromFileName(slugSource),
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

	s.publishUploadedEvent(ctx, w, userID, objectName)

	if _, err := s.coinRepo.Transfer(ctx, repo.SystemUserID, userID, 1,
		model.CoinTxUploadReward, model.CoinTxUploadReward, w.ID,
		"Upload reward issued", "Upload wallpaper reward"); err != nil {
		slog.ErrorContext(ctx, "failed to grant upload coin", "error", err, "user_id", userID, "wallpaper_id", w.ID)
	}

	return w, nil
}

func (s *WallpaperService) GetBySlug(ctx context.Context, idOrSlug string, currentUserID int64) (*WallpaperDetail, *errcode.ErrCode) {
	var w *model.Wallpaper
	var err error
	if id, parseErr := strconv.ParseInt(idOrSlug, 10, 64); parseErr == nil {
		w, err = s.wallpaperRepo.GetByID(ctx, id)
	} else {
		w, err = s.wallpaperRepo.GetBySlug(ctx, idOrSlug)
	}
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_ref", idOrSlug)
		return nil, errcode.ErrInternal
	}
	if w == nil {
		return nil, errcode.ErrNotFound
	}

	if err := s.wallpaperRepo.IncrementCounter(ctx, w.ID, "view_count", 1); err != nil {
		slog.ErrorContext(ctx, "failed to increment view count", "error", err)
	}
	w.ViewCount++

	if err := s.eventRepo.Record(ctx, w.ID, "view", currentUserID, nil); err != nil {
		slog.ErrorContext(ctx, "failed to record view event", "error", err, "wallpaper_id", w.ID)
	}

	tags, err := s.tagRepo.GetByWallpaperID(ctx, w.ID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper tags",
			"error", err, "wallpaper_id", w.ID)
		return nil, errcode.ErrInternal
	}

	uploader, err := s.userRepo.GetByID(ctx, w.UserID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get uploader",
			"error", err, "user_id", w.UserID)
		return nil, errcode.ErrInternal
	}

	if currentUserID <= 0 || currentUserID != w.UserID {
		w.OriginalURL = ""
	}

	detail := &WallpaperDetail{
		Wallpaper: *w,
		Tags:      tags,
		Uploader:  uploader,
	}

	if currentUserID > 0 {
		liked, err := s.interactionRepo.IsLiked(ctx, currentUserID, w.ID)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check like status", "error", err)
			return nil, errcode.ErrInternal
		}
		detail.IsLiked = liked

		favorited, err := s.interactionRepo.IsFavorited(ctx, currentUserID, w.ID)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check favorite status", "error", err)
			return nil, errcode.ErrInternal
		}
		detail.IsFavorited = favorited

		downloaded, err := s.interactionRepo.HasDownloaded(ctx, currentUserID, w.ID)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check download status", "error", err)
		}
		detail.IsDownloaded = downloaded
	}

	return detail, nil
}

func (s *WallpaperService) List(ctx context.Context, opts repo.ListOptions, currentUserID int64) (*ListResponse, *errcode.ErrCode) {
	if opts.Limit <= 0 || opts.Limit > 100 {
		opts.Limit = 20
	}

	if opts.Sort == "trending" {
		return s.listTrending(ctx, opts, currentUserID)
	}

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

	listItems := make([]WallpaperListItem, len(items))
	for i := range items {
		if currentUserID <= 0 || currentUserID != items[i].UserID {
			items[i].OriginalURL = ""
		}
		listItems[i] = WallpaperListItem{Wallpaper: items[i]}
	}

	if currentUserID > 0 && len(items) > 0 {
		ids := make([]int64, len(items))
		for i := range items {
			ids[i] = items[i].ID
		}
		likedMap, err := s.interactionRepo.BatchIsLiked(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check likes", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsLiked = likedMap[listItems[i].ID]
			}
		}
		favMap, err := s.interactionRepo.BatchIsFavorited(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check favorites", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsFavorited = favMap[listItems[i].ID]
			}
		}
		dlMap, err := s.interactionRepo.BatchHasDownloaded(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check downloads", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsDownloaded = dlMap[listItems[i].ID]
			}
		}
	}

	return &ListResponse{
		Items:      listItems,
		NextCursor: nextCursor,
		HasMore:    hasMore,
	}, nil
}

func (s *WallpaperService) listTrending(ctx context.Context, opts repo.ListOptions, currentUserID int64) (*ListResponse, *errcode.ErrCode) {
	since := time.Now().UTC().Add(-7 * 24 * time.Hour)
	trendingIDs, err := s.eventRepo.GetTrending(ctx, since, opts.Limit, opts.CategoryID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get trending wallpapers", "error", err)
		return nil, errcode.ErrInternal
	}
	if len(trendingIDs) == 0 {
		return &ListResponse{Items: []WallpaperListItem{}, HasMore: false}, nil
	}

	items, err := s.wallpaperRepo.GetByIDs(ctx, trendingIDs)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpapers by ids", "error", err)
		return nil, errcode.ErrInternal
	}

	idxMap := make(map[int64]int, len(trendingIDs))
	for i, id := range trendingIDs {
		idxMap[id] = i
	}
	ordered := make([]model.Wallpaper, 0, len(items))
	for range trendingIDs {
		ordered = append(ordered, model.Wallpaper{})
	}
	for _, w := range items {
		if idx, ok := idxMap[w.ID]; ok {
			ordered[idx] = w
		}
	}
	filtered := make([]model.Wallpaper, 0, len(ordered))
	for _, w := range ordered {
		if w.ID > 0 {
			filtered = append(filtered, w)
		}
	}

	listItems := make([]WallpaperListItem, len(filtered))
	for i := range filtered {
		if currentUserID <= 0 || currentUserID != filtered[i].UserID {
			filtered[i].OriginalURL = ""
		}
		listItems[i] = WallpaperListItem{Wallpaper: filtered[i]}
	}

	if currentUserID > 0 && len(filtered) > 0 {
		ids := make([]int64, len(filtered))
		for i := range filtered {
			ids[i] = filtered[i].ID
		}
		likedMap, err := s.interactionRepo.BatchIsLiked(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check likes", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsLiked = likedMap[listItems[i].ID]
			}
		}
		favMap, err := s.interactionRepo.BatchIsFavorited(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check favorites", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsFavorited = favMap[listItems[i].ID]
			}
		}
		dlMap, err := s.interactionRepo.BatchHasDownloaded(ctx, currentUserID, ids)
		if err != nil {
			slog.ErrorContext(ctx, "failed to batch check downloads", "error", err)
		} else {
			for i := range listItems {
				listItems[i].IsDownloaded = dlMap[listItems[i].ID]
			}
		}
	}

	return &ListResponse{Items: listItems, HasMore: false}, nil
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

	if err := s.collectionRepo.RemoveWallpaperFromAll(ctx, id); err != nil {
		slog.ErrorContext(ctx, "failed to remove wallpaper from collections",
			"error", err, "wallpaper_id", id)
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

	if err := s.eventRepo.Record(ctx, wallpaperID, "like", userID, nil); err != nil {
		slog.ErrorContext(ctx, "failed to record like event", "error", err, "wallpaper_id", wallpaperID)
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

// DownloadTarget describes the resolution the client actually needs to fill
// its display. When set, Download returns the smallest pre-rendered variant
// that covers W×H instead of the (often massively oversized) original. Zero
// values mean "no preference, give me the original" — that's the legacy
// behavior, kept for the web's "Download original" button and old clients.
type DownloadTarget struct {
	Width  int
	Height int
}

func (s *WallpaperService) Download(ctx context.Context, wallpaperID int64, userID int64, target DownloadTarget) (string, *errcode.ErrCode) {
	w, err := s.wallpaperRepo.GetByID(ctx, wallpaperID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get wallpaper",
			"error", err, "wallpaper_id", wallpaperID)
		return "", errcode.ErrInternal
	}
	if w == nil {
		return "", errcode.ErrNotFound
	}

	isOwner := w.UserID == userID

	if !isOwner {
		alreadyPaid, err := s.interactionRepo.HasDownloaded(ctx, userID, wallpaperID)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check download history", "error", err)
			return "", errcode.ErrInternal
		}
		if !alreadyPaid {
			if _, err := s.coinRepo.Transfer(ctx, userID, w.UserID, 1,
				model.CoinTxDownloadCost, model.CoinTxDownloadEarned, wallpaperID,
				"Download wallpaper", "Wallpaper downloaded by others"); err != nil {
				slog.WarnContext(ctx, "coin transfer failed", "error", err, "user_id", userID, "wallpaper_id", wallpaperID)
				return "", errcode.ErrInsufficientCoins
			}
		}
	}

	if err := s.interactionRepo.RecordDownload(ctx, userID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to record download", "error", err)
	}

	if err := s.wallpaperRepo.IncrementCounter(ctx, wallpaperID, "download_count", 1); err != nil {
		slog.ErrorContext(ctx, "failed to increment download count", "error", err)
	}

	if err := s.eventRepo.Record(ctx, wallpaperID, "download", userID, nil); err != nil {
		slog.ErrorContext(ctx, "failed to record download event", "error", err, "wallpaper_id", wallpaperID)
	}

	if target.Width > 0 && target.Height > 0 && !w.IsDynamic {
		if url := s.pickBestVariantURL(ctx, wallpaperID, target); url != "" {
			return url, nil
		}
		// fall through to OriginalURL when no variant covers the target —
		// e.g. wallpaper is smaller than every device profile.
	}
	return w.OriginalURL, nil
}

// pickBestVariantURL returns the smallest variant whose dimensions still
// cover target.W × target.H. Smaller-than-target variants would force the
// client to upscale (visible quality loss), so they're rejected. Dynamic
// wallpapers skip this path entirely — their value is the multi-frame
// HEIC, which can't be substituted by a static variant. Returns "" when
// no variant qualifies; caller falls back to the original.
func (s *WallpaperService) pickBestVariantURL(ctx context.Context, wallpaperID int64, target DownloadTarget) string {
	variants, err := s.deviceRepo.ListVariantsByWallpaper(ctx, wallpaperID)
	if err != nil {
		slog.WarnContext(ctx, "variant lookup failed (falling back to original)", "wallpaper_id", wallpaperID, "error", err)
		return ""
	}
	var best *model.VariantWithDevice
	bestPixels := 0
	for i := range variants {
		v := &variants[i]
		if v.Width < target.Width || v.Height < target.Height {
			continue
		}
		p := v.Width * v.Height
		if best == nil || p < bestPixels {
			best = v
			bestPixels = p
		}
	}
	if best == nil {
		return ""
	}
	return best.URL
}

// Reprocess re-runs variant generation for a wallpaper that's stuck in
// processing or got marked failed. Resets status to processing, then
// re-publishes the wallpaper.uploaded Kafka event so the image worker
// picks it back up. Returns ErrNotFound if the wallpaper is gone and
// ErrInvalidParam if we can't recover the original object key from the
// stored URL (legacy uploads where MINIO_PUBLIC_URL since changed).
func (s *WallpaperService) Reprocess(ctx context.Context, id int64) *errcode.ErrCode {
	w, err := s.wallpaperRepo.GetByID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "reprocess: get wallpaper failed", "id", id, "error", err)
		return errcode.ErrInternal
	}
	if w == nil {
		return errcode.ErrNotFound
	}
	objectKey := s.storage.ObjectKeyFromURL(w.OriginalURL)
	if objectKey == "" {
		slog.ErrorContext(ctx, "reprocess: cannot derive object key", "id", id, "original_url", w.OriginalURL)
		return errcode.ErrInvalidParam
	}
	if err := s.wallpaperRepo.UpdateStatus(ctx, id, model.WallpaperStatusProcessing); err != nil {
		slog.ErrorContext(ctx, "reprocess: status reset failed", "id", id, "error", err)
		return errcode.ErrInternal
	}
	s.publishUploadedEvent(ctx, w, w.UserID, objectKey)
	return nil
}

func (s *WallpaperService) publishUploadedEvent(ctx context.Context, w *model.Wallpaper, userID int64, objectKey string) {
	event := WallpaperUploadedEvent{
		WallpaperID: w.ID,
		UserID:      userID,
		ObjectKey:   objectKey,
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
		slog.ErrorContext(ctx, "failed to publish wallpaper uploaded event",
			"error", err, "wallpaper_id", w.ID)
	} else {
		slog.InfoContext(ctx, "wallpaper uploaded event published",
			"wallpaper_id", w.ID, "object_key", objectKey)
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

type EngagementsResponse struct {
	Likers      []repo.EngagementUser `json:"likers"`
	Favoriters  []repo.EngagementUser `json:"favoriters"`
	Downloaders []repo.EngagementUser `json:"downloaders"`
}

func (s *WallpaperService) GetEngagements(ctx context.Context, wallpaperID int64) (*EngagementsResponse, *errcode.ErrCode) {
	const limit = 5

	likers, err := s.interactionRepo.RecentLikers(ctx, wallpaperID, limit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get recent likers", "error", err, "wallpaper_id", wallpaperID)
		likers = []repo.EngagementUser{}
	}

	favoriters, err := s.interactionRepo.RecentFavoriters(ctx, wallpaperID, limit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get recent favoriters", "error", err, "wallpaper_id", wallpaperID)
		favoriters = []repo.EngagementUser{}
	}

	downloaders, err := s.interactionRepo.RecentDownloaders(ctx, wallpaperID, limit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get recent downloaders", "error", err, "wallpaper_id", wallpaperID)
		downloaders = []repo.EngagementUser{}
	}

	return &EngagementsResponse{
		Likers:      likers,
		Favoriters:  favoriters,
		Downloaders: downloaders,
	}, nil
}
