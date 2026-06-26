package repo

import (
	"context"
	"time"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type LoginLogRepo struct {
	db *gorm.DB
}

func NewLoginLogRepo(db *gorm.DB) *LoginLogRepo {
	return &LoginLogRepo{db: db}
}

func (r *LoginLogRepo) Create(ctx context.Context, log *model.LoginLog) error {
	return r.db.WithContext(ctx).Create(log).Error
}

type LoginLogRow struct {
	ID        int64     `gorm:"column:id" json:"id"`
	UserID    int64     `gorm:"column:user_id" json:"user_id"`
	Client    string    `gorm:"column:client" json:"client"`
	IP        string    `gorm:"column:ip" json:"ip"`
	UserAgent string    `gorm:"column:user_agent" json:"user_agent"`
	Country   string    `gorm:"column:country" json:"country"`
	CreatedAt time.Time `gorm:"column:created_at" json:"created_at"`
	Username  string    `gorm:"column:username" json:"username"`
	Nickname  string    `gorm:"column:nickname" json:"nickname"`
	AvatarURL string    `gorm:"column:avatar_url" json:"avatar_url"`
	Email     string    `gorm:"column:email" json:"email"`
}

func (r *LoginLogRepo) AdminList(ctx context.Context, client string, offset, limit int) ([]LoginLogRow, int64, error) {
	q := r.db.WithContext(ctx).
		Table("login_logs ll").
		Joins("JOIN users u ON u.id = ll.user_id")
	cq := r.db.WithContext(ctx).Model(&model.LoginLog{})
	if client != "" {
		q = q.Where("ll.client = ?", client)
		cq = cq.Where("client = ?", client)
	}

	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []LoginLogRow
	err := q.Select(`
			ll.id, ll.user_id, ll.client, ll.ip, ll.user_agent, ll.country, ll.created_at,
			u.username, u.nickname, u.avatar_url, u.email
		`).
		Order("ll.created_at DESC, ll.id DESC").
		Offset(offset).
		Limit(limit).
		Scan(&rows).Error
	return rows, total, err
}
