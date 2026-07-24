package repo

import (
	"context"
	"errors"
	"time"

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
	// A device's count is every published static image the original can serve
	// (covers the device's resolution), not the legacy "has a pre-generated
	// variant row" — variants are now created lazily on download.
	err := r.db.WithContext(ctx).
		Table("device_profiles AS d").
		Select(`d.id, d.platform, d.brand, d.name, d.slug, d.width, d.height,
		        d.ppi, d.sort_order, d.is_active, d.created_at,
		        (SELECT COUNT(*) FROM wallpapers w
		         WHERE w.status = 1 AND w.is_dynamic = false
		           AND w.file_type NOT LIKE 'video/%'
		           AND w.width >= d.width AND w.height >= d.height) AS wallpaper_count`).
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

// GetByID returns the active device profile with the given id, or nil when
// there's no match. Used by the lazy download path to resolve a device's
// target resolution.
func (r *DeviceRepo) GetByID(ctx context.Context, id int64) (*model.DeviceProfile, error) {
	var d model.DeviceProfile
	err := r.db.WithContext(ctx).
		Select("id, platform, brand, name, slug, width, height, ppi, sort_order, is_active, created_at").
		Where("id = ? AND is_active = ?", id, true).
		First(&d).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &d, nil
}

// GetVariantForDevice returns the cached lazy variant for a (wallpaper, device)
// pair, or nil when it hasn't been materialized yet.
func (r *DeviceRepo) GetVariantForDevice(ctx context.Context, wallpaperID, deviceID int64) (*model.WallpaperVariant, error) {
	var v model.WallpaperVariant
	err := r.db.WithContext(ctx).
		Where("wallpaper_id = ? AND device_id = ?", wallpaperID, deviceID).
		First(&v).Error
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, nil
		}
		return nil, err
	}
	return &v, nil
}

// TouchVariant records a serve: bumps download_count and last_downloaded_at so
// the GC sweep treats the variant as warm.
func (r *DeviceRepo) TouchVariant(ctx context.Context, variantID int64) error {
	return r.db.WithContext(ctx).
		Model(&model.WallpaperVariant{}).
		Where("id = ?", variantID).
		Updates(map[string]any{
			"download_count":     gorm.Expr("download_count + 1"),
			"last_downloaded_at": time.Now().UTC(),
		}).Error
}

// ListColdVariants returns lazy variants last served before `before` (or never
// served and created before it), capped at limit. Drives cmd/variantgc.
func (r *DeviceRepo) ListColdVariants(ctx context.Context, before time.Time, limit int) ([]model.WallpaperVariant, error) {
	if limit <= 0 || limit > 1000 {
		limit = 500
	}
	var out []model.WallpaperVariant
	err := r.db.WithContext(ctx).
		Where("COALESCE(last_downloaded_at, created_at) < ?", before).
		Limit(limit).
		Find(&out).Error
	return out, err
}

// DeleteVariantByID removes a single variant row (the MinIO object is deleted
// separately by the caller).
func (r *DeviceRepo) DeleteVariantByID(ctx context.Context, id int64) error {
	return r.db.WithContext(ctx).Delete(&model.WallpaperVariant{}, id).Error
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

// CountWallpapersForDevice returns the number of published static wallpapers
// the device can be served (original resolution covers the device). Variants
// are lazy now, so this is a dimension test, not a variant-row join.
func (r *DeviceRepo) CountWallpapersForDevice(ctx context.Context, deviceID int64, filters WallpaperExclusionFilters) (int64, error) {
	var n int64
	query := r.db.WithContext(ctx).
		Table("wallpapers w").
		Joins("JOIN device_profiles d ON d.id = ?", deviceID).
		Where("w.status = ? AND w.is_dynamic = false AND w.file_type NOT LIKE 'video/%' AND w.width >= d.width AND w.height >= d.height", 1)
	query = filters.apply(query, "w")
	err := query.
		Count(&n).Error
	return n, err
}

// ListWallpapersForDevice returns a page of published static wallpapers the
// device can be served (original covers the device resolution), newest first.
// The cursor is the wallpaper id of the last row from the previous page.
func (r *DeviceRepo) ListWallpapersForDevice(
	ctx context.Context, deviceID int64, cursor int64, limit int, filters WallpaperExclusionFilters,
) ([]model.Wallpaper, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	q := r.db.WithContext(ctx).
		Table("wallpapers w").
		Select("w.*").
		Joins("JOIN device_profiles d ON d.id = ?", deviceID).
		Where("w.status = ? AND w.is_dynamic = false AND w.file_type NOT LIKE 'video/%' AND w.width >= d.width AND w.height >= d.height", 1)
	q = filters.apply(q, "w")
	if cursor > 0 {
		q = q.Where("w.id < ?", cursor)
	}
	var out []model.Wallpaper
	err := q.Order("w.id DESC").Limit(limit).Find(&out).Error
	return out, err
}
