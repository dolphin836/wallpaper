-- Migration: Generate random slugs for existing wallpapers and collections
-- Run this once after deploying the new schema.
-- For better slugs based on title, use: go run ./backend/cmd/sluggen

ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
ALTER TABLE collections ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';

UPDATE wallpapers
SET slug = 'wp-' || encode(gen_random_bytes(6), 'hex')
WHERE slug = '';

UPDATE collections
SET slug = 'col-' || encode(gen_random_bytes(6), 'hex')
WHERE slug = '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_wallpapers_slug ON wallpapers(slug) WHERE slug != '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_collections_slug ON collections(slug) WHERE slug != '';
