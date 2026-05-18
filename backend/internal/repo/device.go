package repo

import (
	"context"
	"errors"

	"gorm.io/gorm"

	"github.com/wallpaper/backend/internal/model"
)

type DeviceRepo struct {
	db *gorm.DB
}

func NewDeviceRepo(db *gorm.DB) *DeviceRepo {
	return &DeviceRepo{db: db}
}

func (r *DeviceRepo) ListActive(ctx context.Context) ([]model.DeviceProfile, error) {
	var devices []model.DeviceProfile
	err := r.db.WithContext(ctx).
		Select("id, platform, brand, name, slug, width, height, ppi, sort_order").
		Where("is_active = ?", true).
		Order("sort_order ASC, id ASC").
		Find(&devices).Error
	return devices, err
}

// DeviceWithCount mirrors DeviceProfile + a per-device tally of how many
// published wallpapers have a variant for that device. Used by the
// /devices listing so the hub page can show count badges without doing
// one extra query per row.
type DeviceWithCount struct {
	model.DeviceProfile
	WallpaperCount int64 `gorm:"column:wallpaper_count" json:"wallpaper_count"`
}

func (r *DeviceRepo) ListActiveWithCounts(ctx context.Context) ([]DeviceWithCount, error) {
	var out []DeviceWithCount
	err := r.db.WithContext(ctx).
		Table("device_profiles AS d").
		Select(`d.id, d.platform, d.brand, d.name, d.slug, d.width, d.height,
		        d.ppi, d.sort_order, d.is_active, d.created_at,
		        COALESCE(c.cnt, 0) AS wallpaper_count`).
		Joins(`LEFT JOIN (
		         SELECT wv.device_id, COUNT(DISTINCT wv.wallpaper_id) AS cnt
		         FROM wallpaper_variants wv
		         JOIN wallpapers w ON w.id = wv.wallpaper_id AND w.status = 1
		         GROUP BY wv.device_id
		       ) c ON c.device_id = d.id`).
		Where("d.is_active = ?", true).
		Order("d.platform ASC, d.sort_order ASC, d.id ASC").
		Scan(&out).Error
	return out, err
}

func (r *DeviceRepo) ListAll(ctx context.Context) ([]model.DeviceProfile, error) {
	var devices []model.DeviceProfile
	err := r.db.WithContext(ctx).
		Select("id, platform, brand, name, slug, width, height, ppi, sort_order, is_active, created_at").
		Order("platform ASC, sort_order ASC").
		Find(&devices).Error
	return devices, err
}

func (r *DeviceRepo) CreateVariant(ctx context.Context, v *model.WallpaperVariant) error {
	return r.db.WithContext(ctx).Create(v).Error
}

func (r *DeviceRepo) CreateVariants(ctx context.Context, variants []model.WallpaperVariant) error {
	if len(variants) == 0 {
		return nil
	}
	return r.db.WithContext(ctx).Create(&variants).Error
}

func (r *DeviceRepo) ListVariantsByWallpaper(ctx context.Context, wallpaperID int64) ([]model.VariantWithDevice, error) {
	var results []model.VariantWithDevice
	err := r.db.WithContext(ctx).
		Table("wallpaper_variants AS wv").
		Select("wv.id, wv.wallpaper_id, wv.device_id, wv.url, wv.width, wv.height, wv.file_size, wv.created_at, dp.platform, dp.brand, dp.name AS dev_name, dp.slug AS device_slug").
		Joins("JOIN device_profiles dp ON dp.id = wv.device_id").
		Where("wv.wallpaper_id = ?", wallpaperID).
		Order("dp.sort_order ASC").
		Find(&results).Error
	return results, err
}

func (r *DeviceRepo) DeleteVariantsByWallpaper(ctx context.Context, wallpaperID int64) error {
	return r.db.WithContext(ctx).
		Where("wallpaper_id = ?", wallpaperID).
		Delete(&model.WallpaperVariant{}).Error
}

func (r *DeviceRepo) GetVariant(ctx context.Context, id int64) (*model.WallpaperVariant, error) {
	var v model.WallpaperVariant
	err := r.db.WithContext(ctx).
		Select("id, wallpaper_id, device_id, url, width, height, file_size, download_count, created_at").
		Where("id = ?", id).
		First(&v).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &v, nil
}

func (r *DeviceRepo) IncrementVariantDownload(ctx context.Context, variantID int64) error {
	return r.db.WithContext(ctx).
		Model(&model.WallpaperVariant{}).
		Where("id = ?", variantID).
		Update("download_count", gorm.Expr("download_count + 1")).Error
}

// GetBySlug returns the active device profile with the given slug, or nil
// when there's no match. Used by the /wallpapers-for/:slug landing pages.
func (r *DeviceRepo) GetBySlug(ctx context.Context, slug string) (*model.DeviceProfile, error) {
	var d model.DeviceProfile
	err := r.db.WithContext(ctx).
		Select("id, platform, brand, name, slug, width, height, ppi, sort_order, is_active, created_at").
		Where("slug = ? AND is_active = ?", slug, true).
		First(&d).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

// CountWallpapersForDevice returns the total number of published wallpapers
// that have at least one variant for the given device id.
func (r *DeviceRepo) CountWallpapersForDevice(ctx context.Context, deviceID int64) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).
		Table("wallpapers w").
		Joins("JOIN wallpaper_variants wv ON wv.wallpaper_id = w.id").
		Where("wv.device_id = ? AND w.status = ?", deviceID, 1). // 1 = published
		Distinct("w.id").
		Count(&n).Error
	return n, err
}

// ListWallpapersForDevice returns a page of published wallpapers that have
// at least one variant for the given device, ordered by newest first. The
// cursor is the wallpaper id of the last row from the previous page.
func (r *DeviceRepo) ListWallpapersForDevice(
	ctx context.Context, deviceID int64, cursor int64, limit int,
) ([]model.Wallpaper, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	q := r.db.WithContext(ctx).
		Table("wallpapers w").
		Select("DISTINCT w.*").
		Joins("JOIN wallpaper_variants wv ON wv.wallpaper_id = w.id").
		Where("wv.device_id = ? AND w.status = ?", deviceID, 1)
	if cursor > 0 {
		q = q.Where("w.id < ?", cursor)
	}
	var out []model.Wallpaper
	err := q.Order("w.id DESC").Limit(limit).Find(&out).Error
	return out, err
}
