package repo

import (
	"context"

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
		Select("id, platform, brand, name, width, height, ppi, sort_order").
		Where("is_active = ?", true).
		Order("sort_order ASC, id ASC").
		Find(&devices).Error
	return devices, err
}

func (r *DeviceRepo) ListAll(ctx context.Context) ([]model.DeviceProfile, error) {
	var devices []model.DeviceProfile
	err := r.db.WithContext(ctx).
		Select("id, platform, brand, name, width, height, ppi, sort_order, is_active, created_at").
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
		Select("wv.id, wv.wallpaper_id, wv.device_id, wv.url, wv.width, wv.height, wv.file_size, wv.created_at, dp.platform, dp.brand, dp.name AS dev_name").
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
