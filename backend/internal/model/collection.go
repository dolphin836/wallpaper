package model

import "time"

type Collection struct {
	ID             int64     `gorm:"primaryKey" json:"id"`
	Slug           string    `gorm:"size:160;not null;default:'';uniqueIndex" json:"slug"`
	UserID         int64     `gorm:"not null;index" json:"user_id"`
	Title          string    `gorm:"size:100;not null" json:"title"`
	Description    string    `gorm:"type:text;not null;default:''" json:"description"`
	CoverURL       string    `gorm:"size:512;not null;default:''" json:"cover_url"`
	IsPublic       bool      `gorm:"not null;default:true" json:"is_public"`
	WallpaperCount int       `gorm:"not null;default:0" json:"wallpaper_count"`
	ViewCount      int64     `gorm:"not null;default:0" json:"view_count"`
	LikeCount      int64     `gorm:"not null;default:0" json:"like_count"`
	// Kind discriminates user collections (0) from editor-curated weekly
	// theme collections (1). Year + Week tag the latter with their ISO
	// week so the Home page can pull "latest 3 weekly themes" cheaply.
	Kind int16 `gorm:"not null;default:0" json:"kind"`
	Year int16 `gorm:"not null;default:0" json:"year,omitempty"`
	Week int16 `gorm:"not null;default:0" json:"week,omitempty"`
	CreatedAt      time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
	UpdatedAt      time.Time `gorm:"not null;autoUpdateTime" json:"updated_at"`
	// RecentTiles is populated by handlers that need a mini-preview strip for
	// the collection (currently the public /collections list). Each tile
	// carries enough data for the frontend to do the same dominant-color +
	// thumb-then-preview progressive load the main wallpaper grid does.
	// gorm:"-" keeps it out of every read query that doesn't ask for it.
	RecentTiles []CollectionTile `gorm:"-" json:"recent_tiles,omitempty"`
}

// CollectionTile is one slot in a collection card's preview composition.
type CollectionTile struct {
	ThumbURL      string `json:"thumb_url"`
	PreviewURL    string `json:"preview_url"`
	DominantColor string `json:"dominant_color"`
}

type CollectionWallpaper struct {
	ID           int64     `gorm:"primaryKey" json:"id"`
	CollectionID int64     `gorm:"not null;uniqueIndex:idx_cw_unique" json:"collection_id"`
	WallpaperID  int64     `gorm:"not null;uniqueIndex:idx_cw_unique" json:"wallpaper_id"`
	SortOrder    int       `gorm:"not null;default:0" json:"sort_order"`
	CreatedAt    time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (CollectionWallpaper) TableName() string {
	return "collection_wallpapers"
}

type CollectionLike struct {
	UserID       int64     `gorm:"primaryKey" json:"user_id"`
	CollectionID int64     `gorm:"primaryKey" json:"collection_id"`
	CreatedAt    time.Time `gorm:"not null;autoCreateTime" json:"created_at"`
}

func (CollectionLike) TableName() string {
	return "collection_likes"
}
