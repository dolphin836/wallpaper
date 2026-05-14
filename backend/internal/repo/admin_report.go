package repo

import (
	"context"

	"github.com/wallpaper/backend/internal/model"
)

type AdminReportRow struct {
	model.Report
	ReporterUsername string `json:"reporter_username"`
	WallpaperSlug    string `json:"wallpaper_slug"`
	WallpaperTitle   string `json:"wallpaper_title"`
	WallpaperThumb   string `json:"wallpaper_thumb"`
	WallpaperStatus  int16  `json:"wallpaper_status"`
}

type AdminReportListOpts struct {
	Status int16 // -1 = any
	Offset int
	Limit  int
}

func (r *ReportRepo) AdminList(ctx context.Context, opts AdminReportListOpts) ([]AdminReportRow, int64, error) {
	q := r.db.WithContext(ctx).Table("reports").
		Joins("LEFT JOIN users u ON u.id = reports.reporter_user_id").
		Joins("LEFT JOIN wallpapers w ON w.id = reports.wallpaper_id")

	cq := r.db.WithContext(ctx).Model(&model.Report{})
	if opts.Status >= 0 {
		q = q.Where("reports.status = ?", opts.Status)
		cq = cq.Where("status = ?", opts.Status)
	}

	limit := opts.Limit
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	var total int64
	if err := cq.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []AdminReportRow
	err := q.Select(`reports.id, reports.wallpaper_id, reports.reporter_user_id, reports.reason, reports.note,
                     reports.status, reports.created_at,
                     COALESCE(u.username, '') AS reporter_username,
                     COALESCE(w.slug, '')     AS wallpaper_slug,
                     COALESCE(w.title, '')    AS wallpaper_title,
                     COALESCE(w.thumb_url, '') AS wallpaper_thumb,
                     COALESCE(w.status, 0)    AS wallpaper_status`).
		Order("reports.status ASC, reports.created_at DESC").
		Offset(opts.Offset).Limit(limit).Find(&rows).Error
	return rows, total, err
}

func (r *ReportRepo) AdminSetStatus(ctx context.Context, id int64, status int16) error {
	return r.db.WithContext(ctx).Model(&model.Report{}).Where("id = ?", id).
		Update("status", status).Error
}

func (r *ReportRepo) AdminGetByID(ctx context.Context, id int64) (*model.Report, error) {
	var rep model.Report
	err := r.db.WithContext(ctx).Where("id = ?", id).First(&rep).Error
	if err != nil {
		return nil, err
	}
	return &rep, nil
}

func (r *ReportRepo) AdminResolveAllForWallpaper(ctx context.Context, wallpaperID int64, status int16) error {
	return r.db.WithContext(ctx).Model(&model.Report{}).
		Where("wallpaper_id = ? AND status = ?", wallpaperID, model.ReportStatusOpen).
		Update("status", status).Error
}
