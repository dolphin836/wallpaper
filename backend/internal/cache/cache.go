package cache

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Cache wraps a Redis client with JSON serialization helpers.
type Cache struct {
	client *redis.Client
}

// New creates a Cache backed by the given Redis instance.
func New(addr, password string, db int) *Cache {
	client := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: password,
		DB:       db,
	})
	return &Cache{client: client}
}

// Ping verifies the Redis connection is alive.
func (c *Cache) Ping(ctx context.Context) error {
	return c.client.Ping(ctx).Err()
}

// Set serializes value as JSON and stores it with the given TTL.
func (c *Cache) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal cache value: %w", err)
	}
	return c.client.Set(ctx, key, data, ttl).Err()
}

// Get fetches the key from Redis and JSON-unmarshals into dest.
func (c *Cache) Get(ctx context.Context, key string, dest interface{}) error {
	data, err := c.client.Get(ctx, key).Bytes()
	if err != nil {
		return err
	}
	return json.Unmarshal(data, dest)
}

// Delete removes one or more keys from Redis.
func (c *Cache) Delete(ctx context.Context, keys ...string) error {
	return c.client.Del(ctx, keys...).Err()
}

// Close releases the underlying Redis connection.
func (c *Cache) Close() error {
	return c.client.Close()
}

// WallpaperDetailKey returns the cache key for a single wallpaper.
func WallpaperDetailKey(id int64) string {
	return fmt.Sprintf("wallpaper:detail:%d", id)
}

// CategoriesKey returns the cache key for the full category list. Keyed
// per response language because the cached rows are stored post-
// localization (the i18n maps themselves don't survive JSON caching).
func CategoriesKey(lang string) string {
	return "categories:all:" + lang
}

// PopularTagsKey returns the cache key for the popular tags list, keyed
// per response language like CategoriesKey.
func PopularTagsKey(lang string) string {
	return "tags:popular:" + lang
}
