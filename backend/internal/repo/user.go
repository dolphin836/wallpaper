package repo

import (
	"context"
	"errors"

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
		Select("id, username, email, nickname, avatar_url, bio, coins, status, created_at").
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
		Select("id, username, email, password_hash, nickname, avatar_url, bio, status, created_at").
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

type UserListItem struct {
	model.User
	WallpaperCount int64 `json:"wallpaper_count"`
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
