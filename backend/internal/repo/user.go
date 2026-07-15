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

// UsernamesByIDs resolves collection owners in one query for public list
// cards. It deliberately returns only the public username rather than full
// user records, keeping the collection response small and avoiding N+1
// lookups in the handler.
func (r *UserRepo) UsernamesByIDs(ctx context.Context, ids []int64) (map[int64]string, error) {
	usernames := make(map[int64]string, len(ids))
	if len(ids) == 0 {
		return usernames, nil
	}

	type row struct {
		ID       int64  `gorm:"column:id"`
		Username string `gorm:"column:username"`
	}
	var rows []row
	if err := r.db.WithContext(ctx).
		Model(&model.User{}).
		Select("id, username").
		Where("id IN ?", ids).
		Find(&rows).Error; err != nil {
		return nil, err
	}
	for _, item := range rows {
		usernames[item.ID] = item.Username
	}
	return usernames, nil
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
		// Privacy flags MUST be in the projection — listUserInteractions
		// reads target.LikesPublic / FavoritesPublic / DownloadsPublic
		// to decide whether to return a list to a stranger. Leaving them
		// off the SELECT meant they zero-initialised to false in the
		// struct and every /users/<username>/likes etc. came back with
		// {private: true} regardless of the row's actual flags.
		Select("id, username, email, password_hash, nickname, avatar_url, bio, status, likes_public, favorites_public, downloads_public, created_at").
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
	TotalDownloads int64    `gorm:"-" json:"total_downloads"`
	RecentThumbs   []string `gorm:"-" json:"recent_thumbs,omitempty"`
	// Parallel to RecentThumbs — the dominant_color of each recent
	// wallpaper. SPA uses these as the per-card colour-aura stops so
	// every contributor's card has a unique tint.
	RecentTints    []string `gorm:"-" json:"recent_tints,omitempty"`
}

// TotalDownloadsForUsers returns each user's aggregate download
// count across every published wallpaper they uploaded. Empty (0)
// for users with no published wallpapers. One round-trip via SUM
// + GROUP BY — same cost shape as RecentThumbsForUsers.
func (r *UserRepo) TotalDownloadsForUsers(ctx context.Context, ids []int64) (map[int64]int64, error) {
	out := make(map[int64]int64, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	type row struct {
		UserID int64 `gorm:"column:user_id"`
		Total  int64 `gorm:"column:total"`
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT user_id, COALESCE(SUM(download_count), 0) AS total
		  FROM wallpapers
		 WHERE user_id IN ? AND status = 1
		 GROUP BY user_id
	`, ids).Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	for _, r := range rows {
		out[r.UserID] = r.Total
	}
	return out, nil
}

// RecentThumbsForUsers returns up to 9 of each user's most recently
// published wallpaper thumb URLs, keyed by user id. Empty slice for
// users with no published wallpapers. Used by the SPA Uploaders
// page to build a 3×3 mosaic per contributor. One round-trip via
// a window function — at the handler's 50-user cap that's at most
// 450 small rows.
func (r *UserRepo) RecentThumbsForUsers(ctx context.Context, ids []int64) (thumbs map[int64][]string, tints map[int64][]string, _ error) {
	thumbs = make(map[int64][]string, len(ids))
	tints = make(map[int64][]string, len(ids))
	if len(ids) == 0 {
		return thumbs, tints, nil
	}
	type row struct {
		UserID        int64  `gorm:"column:user_id"`
		ThumbURL      string `gorm:"column:thumb_url"`
		DominantColor string `gorm:"column:dominant_color"`
	}
	var rows []row
	err := r.db.WithContext(ctx).Raw(`
		SELECT user_id, thumb_url, dominant_color FROM (
			SELECT user_id, thumb_url, dominant_color,
			       ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, id DESC) AS rn
			  FROM wallpapers
			 WHERE user_id IN ? AND status = 1 AND thumb_url <> ''
		) ranked
		WHERE rn <= 9
		ORDER BY user_id, rn
	`, ids).Scan(&rows).Error
	if err != nil {
		return nil, nil, err
	}
	for _, r := range rows {
		thumbs[r.UserID] = append(thumbs[r.UserID], r.ThumbURL)
		if r.DominantColor != "" {
			tints[r.UserID] = append(tints[r.UserID], r.DominantColor)
		}
	}
	return thumbs, tints, nil
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
                     users.coins, users.status, users.is_admin,
                     users.register_client, users.register_source, users.register_referrer,
                     users.register_path, users.register_ip, users.register_user_agent, users.register_country,
                     users.created_at,
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
