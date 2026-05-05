package config

import (
	"fmt"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	Server ServerConfig
	DB     DBConfig
	Redis  RedisConfig
	MinIO  MinIOConfig
	Kafka  KafkaConfig
	JWT    JWTConfig
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
