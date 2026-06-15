package repo

import (
	"context"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/wallpaper/backend/internal/model"
)

type InteractionRepo struct {
	db *gorm.DB
}

func NewInteractionRepo(db *gorm.DB) *InteractionRepo {
	return &InteractionRepo{db: db}
}

func (r *InteractionRepo) Like(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Clauses(clause.OnConflict{DoNothing: true}).
		Create(&model.UserLike{UserID: userID, WallpaperID: wallpaperID})
	return res.RowsAffected > 0, res.Error
}

func (r *InteractionRepo) Unlike(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Where("user_id = ? AND wallpaper_id = ?", userID, wallpaperID).
		Delete(&model.UserLike{})
	return res.RowsAffected > 0, res.Error
}

func (r *InteractionRepo) IsLiked(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.UserLike{}).
		Where("user_id = ? AND wallpaper_id = ?", userID, wallpaperID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (r *InteractionRepo) Favorite(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Clauses(clause.OnConflict{DoNothing: true}).
		Create(&model.UserFavorite{UserID: userID, WallpaperID: wallpaperID})
	return res.RowsAffected > 0, res.Error
}

func (r *InteractionRepo) Unfavorite(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Where("user_id = ? AND wallpaper_id = ?", userID, wallpaperID).
		Delete(&model.UserFavorite{})
	return res.RowsAffected > 0, res.Error
}

func (r *InteractionRepo) IsFavorited(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.UserFavorite{}).
		Where("user_id = ? AND wallpaper_id = ?", userID, wallpaperID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (r *InteractionRepo) BatchIsLiked(ctx context.Context, userID int64, wallpaperIDs []int64) (map[int64]bool, error) {
	if len(wallpaperIDs) == 0 {
		return map[int64]bool{}, nil
	}
	var ids []int64
	err := r.db.WithContext(ctx).
		Model(&model.UserLike{}).
		Where("user_id = ? AND wallpaper_id IN ?", userID, wallpaperIDs).
		Pluck("wallpaper_id", &ids).Error
	if err != nil {
		return nil, err
	}
	result := make(map[int64]bool, len(ids))
	for _, id := range ids {
		result[id] = true
	}
	return result, nil
}

func (r *InteractionRepo) BatchIsFavorited(ctx context.Context, userID int64, wallpaperIDs []int64) (map[int64]bool, error) {
	if len(wallpaperIDs) == 0 {
		return map[int64]bool{}, nil
	}
	var ids []int64
	err := r.db.WithContext(ctx).
		Model(&model.UserFavorite{}).
		Where("user_id = ? AND wallpaper_id IN ?", userID, wallpaperIDs).
		Pluck("wallpaper_id", &ids).Error
	if err != nil {
		return nil, err
	}
	result := make(map[int64]bool, len(ids))
	for _, id := range ids {
		result[id] = true
	}
	return result, nil
}

func (r *InteractionRepo) ListFavorites(ctx context.Context, userID int64, cursor int64, limit int, filters WallpaperExclusionFilters) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Table("wallpapers").
		Select("wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title, wallpapers.category_id, wallpapers.dominant_color, wallpapers.color_palette, wallpapers.is_ai_generated, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.status, wallpapers.view_count, wallpapers.like_count, wallpapers.download_count, wallpapers.favorite_count, wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type, wallpapers.is_dynamic, wallpapers.dynamic_type, wallpapers.created_at").
		Joins("JOIN user_favorites ON user_favorites.wallpaper_id = wallpapers.id").
		Where("user_favorites.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)

	if cursor > 0 {
		query = query.Where("wallpapers.id < ?", cursor)
	}
	query = filters.apply(query, "wallpapers")

	var wallpapers []model.Wallpaper
	err := query.Order("wallpapers.id DESC").Limit(limit).Find(&wallpapers).Error
	return wallpapers, err
}

func (r *InteractionRepo) BatchHasDownloaded(ctx context.Context, userID int64, wallpaperIDs []int64) (map[int64]bool, error) {
	if len(wallpaperIDs) == 0 {
		return map[int64]bool{}, nil
	}
	var ids []int64
	err := r.db.WithContext(ctx).
		Model(&model.UserDownload{}).
		Where("user_id = ? AND wallpaper_id IN ?", userID, wallpaperIDs).
		Pluck("wallpaper_id", &ids).Error
	if err != nil {
		return nil, err
	}
	result := make(map[int64]bool, len(ids))
	for _, id := range ids {
		result[id] = true
	}
	return result, nil
}

func (r *InteractionRepo) HasDownloaded(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	var count int64
	err := r.db.WithContext(ctx).
		Model(&model.UserDownload{}).
		Where("user_id = ? AND wallpaper_id = ?", userID, wallpaperID).
		Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}

func (r *InteractionRepo) RecordDownload(ctx context.Context, userID, wallpaperID int64) (bool, error) {
	res := r.db.WithContext(ctx).
		Clauses(clause.OnConflict{DoNothing: true}).
		Create(&model.UserDownload{UserID: userID, WallpaperID: wallpaperID})
	return res.RowsAffected > 0, res.Error
}

func (r *InteractionRepo) ListDownloads(ctx context.Context, userID int64, cursor int64, limit int, filters DownloadFilters) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Table("wallpapers").
		Select("wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title, wallpapers.category_id, wallpapers.dominant_color, wallpapers.color_palette, wallpapers.is_ai_generated, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.status, wallpapers.view_count, wallpapers.like_count, wallpapers.download_count, wallpapers.favorite_count, wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type, wallpapers.is_dynamic, wallpapers.dynamic_type, wallpapers.created_at").
		Joins("JOIN user_downloads ON user_downloads.wallpaper_id = wallpapers.id").
		Where("user_downloads.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)

	if cursor > 0 {
		query = query.Where("wallpapers.id < ?", cursor)
	}
	query = r.applyDownloadFilters(query, filters)

	var wallpapers []model.Wallpaper
	err := query.Order("wallpapers.id DESC").Limit(limit).Find(&wallpapers).Error
	return wallpapers, err
}

func (r *InteractionRepo) CountFavorites(ctx context.Context, userID int64, filters WallpaperExclusionFilters) (int64, error) {
	var count int64
	query := r.db.WithContext(ctx).
		Table("user_favorites").
		Joins("JOIN wallpapers ON wallpapers.id = user_favorites.wallpaper_id").
		Where("user_favorites.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)
	query = filters.apply(query, "wallpapers")
	err := query.Count(&count).Error
	return count, err
}

// DownloadFilters mirrors the resolution / dynamic-wallpaper filter knobs the
// home feed already supports. Applied identically to the listing and the
// total-count query so the pagination stays consistent under any filter.
type DownloadFilters struct {
	DeviceWidth    int
	DeviceHeight   int
	DynamicOnly    bool
	IncludeDynamic bool
	WallpaperExclusionFilters
}

// applyDownloadFilters narrows a wallpapers/user_downloads join by the
// resolution / dynamic-only knobs. Same WHERE clauses as WallpaperRepo.List
// so the two listings filter identically.
func (r *InteractionRepo) applyDownloadFilters(query *gorm.DB, f DownloadFilters) *gorm.DB {
	query = f.WallpaperExclusionFilters.apply(query, "wallpapers")
	if f.DynamicOnly {
		return query.Where("wallpapers.is_dynamic = true OR wallpapers.file_type LIKE 'video/%'")
	}
	if f.DeviceWidth > 0 && f.DeviceHeight > 0 {
		if f.IncludeDynamic {
			return query.Where(
				"((wallpapers.width >= ? AND wallpapers.height >= ?) OR wallpapers.is_dynamic = true)",
				f.DeviceWidth, f.DeviceHeight,
			)
		}
		return query.Where(
			"wallpapers.width >= ? AND wallpapers.height >= ?",
			f.DeviceWidth, f.DeviceHeight,
		)
	}
	return query
}

func (r *InteractionRepo) CountDownloads(ctx context.Context, userID int64, filters DownloadFilters) (int64, error) {
	query := r.db.WithContext(ctx).
		Table("user_downloads").
		Joins("JOIN wallpapers ON wallpapers.id = user_downloads.wallpaper_id").
		Where("user_downloads.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)
	query = r.applyDownloadFilters(query, filters)
	var count int64
	err := query.Count(&count).Error
	return count, err
}

func (r *InteractionRepo) CountLikes(ctx context.Context, userID int64, filters WallpaperExclusionFilters) (int64, error) {
	var count int64
	query := r.db.WithContext(ctx).
		Table("user_likes").
		Joins("JOIN wallpapers ON wallpapers.id = user_likes.wallpaper_id").
		Where("user_likes.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)
	query = filters.apply(query, "wallpapers")
	err := query.Count(&count).Error
	return count, err
}

func (r *InteractionRepo) ListLikes(ctx context.Context, userID int64, cursor int64, limit int, filters WallpaperExclusionFilters) ([]model.Wallpaper, error) {
	query := r.db.WithContext(ctx).
		Table("wallpapers").
		Select("wallpapers.id, wallpapers.slug, wallpapers.user_id, wallpapers.title, wallpapers.category_id, wallpapers.dominant_color, wallpapers.color_palette, wallpapers.is_ai_generated, wallpapers.thumb_url, wallpapers.preview_url, wallpapers.status, wallpapers.view_count, wallpapers.like_count, wallpapers.download_count, wallpapers.favorite_count, wallpapers.width, wallpapers.height, wallpapers.file_size, wallpapers.file_type, wallpapers.is_dynamic, wallpapers.dynamic_type, wallpapers.created_at").
		Joins("JOIN user_likes ON user_likes.wallpaper_id = wallpapers.id").
		Where("user_likes.user_id = ? AND wallpapers.status = ?", userID, model.WallpaperStatusPublished)

	if cursor > 0 {
		query = query.Where("wallpapers.id < ?", cursor)
	}
	query = filters.apply(query, "wallpapers")

	var wallpapers []model.Wallpaper
	err := query.Order("wallpapers.id DESC").Limit(limit).Find(&wallpapers).Error
	return wallpapers, err
}

type EngagementUser struct {
	ID        int64  `json:"id"`
	Username  string `json:"username"`
	Nickname  string `json:"nickname"`
	AvatarURL string `json:"avatar_url"`
}

func (r *InteractionRepo) RecentLikers(ctx context.Context, wallpaperID int64, limit int) ([]EngagementUser, error) {
	var users []EngagementUser
	err := r.db.WithContext(ctx).
		Table("users").
		Select("users.id, users.username, users.nickname, users.avatar_url").
		Joins("JOIN user_likes ON user_likes.user_id = users.id").
		Where("user_likes.wallpaper_id = ?", wallpaperID).
		Order("user_likes.created_at DESC").
		Limit(limit).
		Find(&users).Error
	return users, err
}

func (r *InteractionRepo) RecentFavoriters(ctx context.Context, wallpaperID int64, limit int) ([]EngagementUser, error) {
	var users []EngagementUser
	err := r.db.WithContext(ctx).
		Table("users").
		Select("users.id, users.username, users.nickname, users.avatar_url").
		Joins("JOIN user_favorites ON user_favorites.user_id = users.id").
		Where("user_favorites.wallpaper_id = ?", wallpaperID).
		Order("user_favorites.created_at DESC").
		Limit(limit).
		Find(&users).Error
	return users, err
}

func (r *InteractionRepo) RecentDownloaders(ctx context.Context, wallpaperID int64, limit int) ([]EngagementUser, error) {
	var users []EngagementUser
	err := r.db.WithContext(ctx).
		Table("users").
		Select("users.id, users.username, users.nickname, users.avatar_url").
		Joins("JOIN user_downloads ON user_downloads.user_id = users.id").
		Where("user_downloads.wallpaper_id = ?", wallpaperID).
		Order("user_downloads.created_at DESC").
		Limit(limit).
		Find(&users).Error
	return users, err
}
