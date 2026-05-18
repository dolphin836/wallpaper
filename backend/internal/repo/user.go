package repo

import (
	"context"
	"errors"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type UserRepo struct {
	db *gorm.DB
}

func NewUserRepo(db *gorm.DB) *UserRepo {
	return &UserRepo{db: db}
}

func (r *UserRepo) Create(ctx context.Context, user *model.User) error {
	return r.db.WithContext(ctx).Create(user).Error
}

func (r *UserRepo) GetByID(ctx context.Context, id int64) (*model.User, error) {
	var user model.User
	err := r.db.WithContext(ctx).
		Select("id, username, email, nickname, avatar_url, bio, coins, status, is_admin, likes_public, favorites_public, downloads_public, created_at").
		Where("id = ?", id).
		First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (r *UserRepo) GetByEmail(ctx context.Context, email string) (*model.User, error) {
	var user model.User
	err := r.db.WithContext(ctx).
		Select("id, username, email, password_hash, nickname, avatar_url, bio, coins, status, is_admin, created_at").
		Where("email = ?", email).
		First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (r *UserRepo) GetByUsername(ctx context.Context, username string) (*model.User, error) {
	var user model.User
	err := r.db.WithContext(ctx).
		Select("id, username, email, password_hash, nickname, avatar_url, bio, status, created_at").
		Where("username = ?", username).
		First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (r *UserRepo) GetByIDWithHash(ctx context.Context, id int64) (*model.User, error) {
	var user model.User
	err := r.db.WithContext(ctx).
		Select("id, password_hash").
		Where("id = ?", id).
		First(&user).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &user, nil
}

func (r *UserRepo) UpdateProfile(ctx context.Context, id int64, nickname, bio string) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", id).
		Updates(map[string]any{"nickname": nickname, "bio": bio}).Error
}

func (r *UserRepo) UpdateAvatar(ctx context.Context, id int64, avatarURL string) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", id).
		Update("avatar_url", avatarURL).Error
}

func (r *UserRepo) UpdatePassword(ctx context.Context, id int64, hash string) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", id).
		Update("password_hash", hash).Error
}

// UpdatePrivacy sets the three per-list public flags for a user. Pass nil
// for any flag the caller doesn't want to touch — the row update only
// includes fields that are actually present in the map.
func (r *UserRepo) UpdatePrivacy(ctx context.Context, id int64, likes, favorites, downloads *bool) error {
	updates := map[string]any{}
	if likes != nil {
		updates["likes_public"] = *likes
	}
	if favorites != nil {
		updates["favorites_public"] = *favorites
	}
	if downloads != nil {
		updates["downloads_public"] = *downloads
	}
	if len(updates) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ?", id).
		Updates(updates).Error
}

type UserListItem struct {
	model.User
	WallpaperCount int64    `json:"wallpaper_count"`
	RecentThumbs   []string `gorm:"-" json:"recent_thumbs,omitempty"`
}

// RecentThumbsForUsers returns the 3 most recently published wallpaper thumb
// URLs per user, keyed by user id. Empty slice for users with no published
// wallpapers. One round-trip via window function — cheap up to ~50 users per
// page (the api caps `limit` at 50 in the handler).
func (r *UserRepo) RecentThumbsForUsers(ctx context.Context, ids []int64) (map[int64][]string, error) {
	out := make(map[int64][]string, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	type row struct {
		UserID   int64  `gorm:"column:user_id"`
		ThumbURL string `gorm:"column:thumb_url"`
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT user_id, thumb_url FROM (
			SELECT user_id, thumb_url,
			       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, id DESC) AS rn
			  FROM wallpapers
			 WHERE user_id IN ? AND status = 1 AND thumb_url <> ''
		) ranked
		WHERE rn <= 3
		ORDER BY user_id, rn
	`, ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.UserID] = append(out[r.UserID], r.ThumbURL)
	}
	return out, nil
}

func (r *UserRepo) IsAdmin(ctx context.Context, id int64) (bool, error) {
	if id <= 0 {
		return false, nil
	}
	var isAdmin bool
	err := r.db.WithContext(ctx).
		Model(&model.User{}).
		Select("is_admin").
		Where("id = ? AND status = 1", id).
		Scan(&isAdmin).Error
	if err != nil {
		return false, err
	}
	return isAdmin, nil
}

// AdminListUsers returns all users for the admin console regardless of status.
// Optional search filters across username/email/nickname.
func (r *UserRepo) AdminListUsers(ctx context.Context, search string, status int, offset, limit int) ([]UserListItem, int64, error) {
	q := r.db.WithContext(ctx).
		Table("users").
		Joins("LEFT JOIN wallpapers w ON w.user_id = users.id AND w.status = 1").
		Where("users.id > 0").
		Group("users.id")

	cq := r.db.WithContext(ctx).Model(&model.User{}).Where("id > 0")
	if status >= 0 {
		q = q.Where("users.status = ?", status)
		cq = cq.Where("status = ?", status)
	}
	if search != "" {
		s := "%" + search + "%"
		q = q.Where("users.username ILIKE ? OR users.email ILIKE ? OR users.nickname ILIKE ?", s, s, s)
		cq = cq.Where("username ILIKE ? OR email ILIKE ? OR nickname ILIKE ?", s, s, s)
	}

	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var items []UserListItem
	err := q.Select(`users.id, users.username, users.email, users.nickname, users.avatar_url, users.bio,
                     users.coins, users.status, users.is_admin, users.created_at,
                     COUNT(w.id) AS wallpaper_count`).
		Order("users.created_at DESC, users.id DESC").
		Offset(offset).Limit(limit).Find(&items).Error
	return items, total, err
}

func (r *UserRepo) AdminSetAdmin(ctx context.Context, id int64, isAdmin bool) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ? AND id > 0", id).
		Update("is_admin", isAdmin).Error
}

func (r *UserRepo) AdminSetStatus(ctx context.Context, id int64, status int16) error {
	return r.db.WithContext(ctx).Model(&model.User{}).Where("id = ? AND id > 0", id).
		Update("status", status).Error
}

func (r *UserRepo) CountAll(ctx context.Context) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.User{}).Where("id > 0").Count(&n).Error
	return n, err
}

func (r *UserRepo) CountSince(ctx context.Context, since time.Time) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).Model(&model.User{}).
		Where("id > 0 AND created_at >= ?", since).Count(&n).Error
	return n, err
}

func (r *UserRepo) ListUsers(ctx context.Context, sort string, offset, limit int) ([]UserListItem, int64, error) {
	var total int64
	r.db.WithContext(ctx).Model(&model.User{}).Where("id > 0 AND status = 1").Count(&total)

	var items []UserListItem
	q := r.db.WithContext(ctx).
		Table("users").
		Select("users.id, users.username, users.nickname, users.avatar_url, users.bio, users.coins, users.status, users.created_at, COUNT(w.id) AS wallpaper_count").
		Joins("LEFT JOIN wallpapers w ON w.user_id = users.id AND w.status = 1").
		Where("users.id > 0 AND users.status = 1").
		Group("users.id")

	switch sort {
	case "uploads":
		q = q.Order("wallpaper_count DESC, users.id DESC")
	case "coins":
		q = q.Order("users.coins DESC, users.id DESC")
	default:
		q = q.Order("users.created_at DESC, users.id DESC")
	}

	err := q.Offset(offset).Limit(limit).Find(&items).Error
	return items, total, err
}

// ListUploadersForSitemap returns usernames + most recent update time
// for users with at least one published wallpaper, used by SEO sitemap.
// Excludes the system user (id <= 0) and accounts without uploads.
type SitemapUploaderEntry struct {
	Username  string
	UpdatedAt time.Time
}

func (r *UserRepo) ListUploadersForSitemap(ctx context.Context) ([]SitemapUploaderEntry, error) {
	var entries []SitemapUploaderEntry
	err := r.db.WithContext(ctx).
		Raw(`
			SELECT u.username, MAX(w.updated_at) AS updated_at
			FROM users u
			JOIN wallpapers w ON w.user_id = u.id
			WHERE u.id > 0
			  AND u.status = 1
			  AND w.status = 1
			GROUP BY u.username
			ORDER BY MAX(w.updated_at) DESC
		`).
		Scan(&entries).Error
	return entries, err
}
