package config

import (
	"fmt"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	Server    ServerConfig
	DB        DBConfig
	Redis     RedisConfig
	MinIO     MinIOConfig
	Kafka     KafkaConfig
	JWT       JWTConfig
	Anthropic AnthropicConfig
	IndexNow  IndexNowConfig
	Pinterest PinterestConfig
	Tus       TusConfig
	Transcode TranscodeConfig
}

// TusConfig controls the local-disk staging area used by the
// /api/v1/uploads/tus/* resumable upload endpoint. The directory
// holds in-flight chunks and the assembled file for each upload
// until completion fires and we push to MinIO. Sized to handle
// max-upload-size × concurrent-uploads — at 200 MB per video, a
// modest 4 GB tmp dir holds ~20 concurrent uploads.
type TusConfig struct {
	TmpDir string `env:"TUS_TMP_DIR" envDefault:"/var/lib/wpe/tus"`
}

// TranscodeConfig: scratch dir the ffmpeg worker writes intermediates
// into. Sized for max-input × concurrent transcodes.
type TranscodeConfig struct {
	WorkDir string `env:"TRANSCODE_WORK_DIR" envDefault:"/var/lib/wpe/transcode"`
}

type AnthropicConfig struct {
	APIKey      string `env:"ANTHROPIC_API_KEY" envDefault:""`
	AdminAPIKey string `env:"ANTHROPIC_ADMIN_API_KEY" envDefault:""` // separate key, console → Settings → Admin Keys
}

// IndexNowConfig drives the IndexNow notifier (Bing/Yandex instant
// indexing). Key is a random hex string we share with the search
// engines; SiteURL is the canonical browseable origin (no trailing
// slash, no "api." prefix) — submitted URLs and keyLocation are
// computed off of it.
type IndexNowConfig struct {
	Key     string `env:"INDEXNOW_KEY" envDefault:""`
	SiteURL string `env:"INDEXNOW_SITE_URL" envDefault:"https://wallpaperexchange.com"`
}

// PinterestConfig is used by the admin-only marketing integration. RedirectURL
// must be registered in the Pinterest app dashboard exactly as configured here.
type PinterestConfig struct {
	AppID       string `env:"PINTEREST_APP_ID" envDefault:""`
	AppSecret   string `env:"PINTEREST_APP_SECRET" envDefault:""`
	RedirectURL string `env:"PINTEREST_REDIRECT_URL" envDefault:"https://wallpaperexchange.com/api/v1/admin/integrations/pinterest/callback"`
	SiteURL     string `env:"PINTEREST_SITE_URL" envDefault:"https://wallpaperexchange.com"`
}

type ServerConfig struct {
	Port int `env:"SERVER_PORT" envDefault:"8080"`
}

type DBConfig struct {
	Host     string `env:"DB_HOST" envDefault:"localhost"`
	Port     int    `env:"DB_PORT" envDefault:"5432"`
	User     string `env:"DB_USER" envDefault:"wallpaper"`
	Password string `env:"DB_PASSWORD" envDefault:"wallpaper"`
	Name     string `env:"DB_NAME" envDefault:"wallpaper"`
	SSLMode  string `env:"DB_SSLMODE" envDefault:"disable"`
}

func (c DBConfig) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode,
	)
}

type RedisConfig struct {
	Addr     string `env:"REDIS_ADDR" envDefault:"localhost:6379"`
	Password string `env:"REDIS_PASSWORD" envDefault:""`
	DB       int    `env:"REDIS_DB" envDefault:"0"`
}

type MinIOConfig struct {
	Endpoint  string `env:"MINIO_ENDPOINT" envDefault:"localhost:9000"`
	AccessKey string `env:"MINIO_ACCESS_KEY" envDefault:"minioadmin"`
	SecretKey string `env:"MINIO_SECRET_KEY" envDefault:"minioadmin"`
	Bucket    string `env:"MINIO_BUCKET" envDefault:"wallpapers"`
	UseSSL    bool   `env:"MINIO_USE_SSL" envDefault:"false"`
	PublicURL string `env:"MINIO_PUBLIC_URL" envDefault:""`
}

type KafkaConfig struct {
	Brokers []string `env:"KAFKA_BROKERS" envSeparator:"," envDefault:"localhost:9092"`
}

type JWTConfig struct {
	Secret     string `env:"JWT_SECRET" envDefault:"change-me-in-production"`
	ExpireHour int    `env:"JWT_EXPIRE_HOUR" envDefault:"24"`
}

func Load() (*Config, error) {
	cfg := &Config{}
	if err := env.Parse(cfg); err != nil {
		return nil, fmt.Errorf("parse config: %w", err)
	}
	return cfg, nil
}
