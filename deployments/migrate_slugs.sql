-- Migration: Generate slugs for existing wallpapers and collections
-- Run this once after deploying the new schema

-- Add slug column if not exists
ALTER TABLE wallpapers ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';
ALTER TABLE collections ADD COLUMN IF NOT EXISTS slug VARCHAR(160) NOT NULL DEFAULT '';

-- Generate slugs for wallpapers based on ID (fallback since original filenames are not stored)
UPDATE wallpapers
SET slug = 'wallpaper-' || id
WHERE slug = '';

-- Generate slugs for collections based on ID
UPDATE collections
SET slug = 'collection-' || id
WHERE slug = '';

-- Create unique indexes (partial to allow empty slugs during transition)
CREATE UNIQUE INDEX IF NOT EXISTS idx_wallpapers_slug ON wallpapers(slug) WHERE slug != '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_collections_slug ON collections(slug) WHERE slug != '';
