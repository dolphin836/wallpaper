package service

import (
	"context"
	"log/slog"
	"strconv"

	"github.com/wallpaper/backend/internal/model"
	"github.com/wallpaper/backend/internal/pkg/errcode"
	"github.com/wallpaper/backend/internal/pkg/slug"
	"github.com/wallpaper/backend/internal/repo"
)

type CollectionService struct {
	collectionRepo  *repo.CollectionRepo
	interactionRepo *repo.InteractionRepo
}

func NewCollectionService(cr *repo.CollectionRepo, ir *repo.InteractionRepo) *CollectionService {
	return &CollectionService{collectionRepo: cr, interactionRepo: ir}
}

type CollectionDetail struct {
	model.Collection
	IsLiked bool `json:"is_liked"`
}

type CollectionListResponse struct {
	Items      []model.Collection `json:"items"`
	NextCursor int64              `json:"next_cursor"`
	HasMore    bool               `json:"has_more"`
	Total      int64              `json:"total"`
}

type WallpaperCollectionResponse struct {
	Items      []model.Wallpaper `json:"items"`
	NextCursor int64             `json:"next_cursor"`
	HasMore    bool              `json:"has_more"`
}

func (s *CollectionService) Create(ctx context.Context, userID int64, title, description string, isPublic bool) (*model.Collection, *errcode.ErrCode) {
	if title == "" {
		return nil, errcode.ErrInvalidParam
	}
	c := &model.Collection{
		Slug:        slug.Generate(title),
		UserID:      userID,
		Title:       title,
		Description: description,
		IsPublic:    isPublic,
	}
	if err := s.collectionRepo.Create(ctx, c); err != nil {
		slog.ErrorContext(ctx, "failed to create collection", "error", err)
		return nil, errcode.ErrInternal
	}
	return c, nil
}

func (s *CollectionService) Get(ctx context.Context, idOrSlug string, currentUserID int64) (*CollectionDetail, *errcode.ErrCode) {
	var c *model.Collection
	var err error
	if id, parseErr := strconv.ParseInt(idOrSlug, 10, 64); parseErr == nil {
		c, err = s.collectionRepo.GetByID(ctx, id)
	} else {
		c, err = s.collectionRepo.GetBySlug(ctx, idOrSlug)
	}
	if err != nil {
		slog.ErrorContext(ctx, "failed to get collection", "error", err)
		return nil, errcode.ErrInternal
	}
	if c == nil {
		return nil, errcode.ErrNotFound
	}
	if !c.IsPublic && c.UserID != currentUserID {
		return nil, errcode.ErrNotFound
	}

	if err := s.collectionRepo.IncrementCounter(ctx, c.ID, "view_count", 1); err != nil {
		slog.ErrorContext(ctx, "failed to increment collection view count", "error", err)
	}
	c.ViewCount++

	detail := &CollectionDetail{Collection: *c}
	if currentUserID > 0 {
		liked, err := s.collectionRepo.IsLiked(ctx, currentUserID, c.ID)
		if err != nil {
			slog.ErrorContext(ctx, "failed to check collection like", "error", err)
		}
		detail.IsLiked = liked
	}
	return detail, nil
}

// RecentTiles is a thin wrapper so the handler can attach mini-preview
// tiles (thumb + preview + dominant color) without reaching past the
// service into the repo layer directly.
func (s *CollectionService) RecentTiles(ctx context.Context, ids []int64) (map[int64][]model.CollectionTile, error) {
	return s.collectionRepo.RecentTilesForCollections(ctx, ids)
}

func (s *CollectionService) List(ctx context.Context, cursor int64, limit int, userID int64, kind int) (*CollectionListResponse, *errcode.ErrCode) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	fetchLimit := limit + 1
	// The public library only ever shows public collections — pass 0 as
	// the visibility user so a signed-in viewer's own private collections
	// don't leak into the shared list (they live on their profile).
	items, err := s.collectionRepo.List(ctx, cursor, fetchLimit, 0, kind)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list collections", "error", err)
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
	total, err := s.collectionRepo.Count(ctx, 0, kind)
	if err != nil {
		slog.ErrorContext(ctx, "failed to count collections", "error", err)
		total = 0 // non-fatal; SPA will degrade to cursor-only pagination
	}
	return &CollectionListResponse{Items: items, NextCursor: nextCursor, HasMore: hasMore, Total: total}, nil
}

func (s *CollectionService) Update(ctx context.Context, id, userID int64, title, description string, isPublic bool) *errcode.ErrCode {
	c, err := s.collectionRepo.GetByID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get collection", "error", err)
		return errcode.ErrInternal
	}
	if c == nil {
		return errcode.ErrNotFound
	}
	if c.UserID != userID {
		return errcode.ErrForbidden
	}
	// Editor-curated / weekly-generated collections (kind != 0) are not
	// user-editable from the detail page — admins manage them in the
	// back office.
	if c.Kind != 0 {
		return errcode.ErrForbidden
	}
	c.Title = title
	c.Description = description
	c.IsPublic = isPublic
	if err := s.collectionRepo.Update(ctx, c); err != nil {
		slog.ErrorContext(ctx, "failed to update collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) Delete(ctx context.Context, id, userID int64) *errcode.ErrCode {
	c, err := s.collectionRepo.GetByID(ctx, id)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get collection", "error", err)
		return errcode.ErrInternal
	}
	if c == nil {
		return errcode.ErrNotFound
	}
	if c.UserID != userID {
		return errcode.ErrForbidden
	}
	if err := s.collectionRepo.Delete(ctx, id); err != nil {
		slog.ErrorContext(ctx, "failed to delete collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) AddWallpaper(ctx context.Context, collectionID, wallpaperID, userID int64) *errcode.ErrCode {
	c, err := s.collectionRepo.GetByID(ctx, collectionID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get collection", "error", err)
		return errcode.ErrInternal
	}
	if c == nil {
		return errcode.ErrNotFound
	}
	if c.UserID != userID {
		return errcode.ErrForbidden
	}
	if err := s.collectionRepo.AddWallpaper(ctx, collectionID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to add wallpaper to collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) RemoveWallpaper(ctx context.Context, collectionID, wallpaperID, userID int64) *errcode.ErrCode {
	c, err := s.collectionRepo.GetByID(ctx, collectionID)
	if err != nil {
		slog.ErrorContext(ctx, "failed to get collection", "error", err)
		return errcode.ErrInternal
	}
	if c == nil {
		return errcode.ErrNotFound
	}
	if c.UserID != userID {
		return errcode.ErrForbidden
	}
	if err := s.collectionRepo.RemoveWallpaper(ctx, collectionID, wallpaperID); err != nil {
		slog.ErrorContext(ctx, "failed to remove wallpaper from collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) Like(ctx context.Context, userID, collectionID int64) *errcode.ErrCode {
	c, err := s.collectionRepo.GetByID(ctx, collectionID)
	if err != nil || c == nil {
		return errcode.ErrNotFound
	}
	if err := s.collectionRepo.LikeCollection(ctx, userID, collectionID); err != nil {
		slog.ErrorContext(ctx, "failed to like collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) Unlike(ctx context.Context, userID, collectionID int64) *errcode.ErrCode {
	if err := s.collectionRepo.UnlikeCollection(ctx, userID, collectionID); err != nil {
		slog.ErrorContext(ctx, "failed to unlike collection", "error", err)
		return errcode.ErrInternal
	}
	return nil
}

func (s *CollectionService) ListWallpapers(ctx context.Context, collectionID int64, cursor int64, limit int) (*WallpaperCollectionResponse, *errcode.ErrCode) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	fetchLimit := limit + 1
	items, err := s.collectionRepo.ListWallpapers(ctx, collectionID, int(cursor), fetchLimit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list collection wallpapers", "error", err)
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
	return &WallpaperCollectionResponse{Items: items, NextCursor: nextCursor, HasMore: hasMore}, nil
}

func (s *CollectionService) ListByUser(ctx context.Context, ownerID int64, cursor int64, limit int) (*CollectionListResponse, *errcode.ErrCode) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	fetchLimit := limit + 1
	items, err := s.collectionRepo.ListByUser(ctx, ownerID, cursor, fetchLimit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list user collections", "error", err)
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
	// Total of the owner's own (kind = 0) collections so the profile
	// pagination can show the real page count from the first render.
	total, _ := s.collectionRepo.CountByOwner(ctx, ownerID, 0)
	return &CollectionListResponse{Items: items, NextCursor: nextCursor, HasMore: hasMore, Total: total}, nil
}

func (s *CollectionService) ListUserCollections(ctx context.Context, userID int64, q string, wallpaperID int64, limit int) ([]repo.CollectionBrief, *errcode.ErrCode) {
	items, err := s.collectionRepo.ListUserCollections(ctx, userID, q, wallpaperID, limit)
	if err != nil {
		slog.ErrorContext(ctx, "failed to list user collections", "error", err)
		return nil, errcode.ErrInternal
	}
	return items, nil
}

func (s *CollectionService) ResolveSlug(ctx context.Context, slug string) (*model.Collection, error) {
	return s.collectionRepo.GetBySlug(ctx, slug)
}
