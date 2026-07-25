import type { Location } from 'react-router-dom';
import type { Wallpaper } from '../types';

export interface WallpaperDetailNavigation {
  items: Wallpaper[];
}

export interface WallpaperDetailLocationState {
  background?: Location;
  initialWallpaper?: Wallpaper;
  detailNavigation?: WallpaperDetailNavigation;
}

export function createWallpaperDetailNavigation(
  wallpapers: Wallpaper[],
): WallpaperDetailNavigation | undefined {
  const seen = new Set<number>();
  const items = wallpapers.filter((wallpaper) => {
    if (seen.has(wallpaper.id)) return false;
    seen.add(wallpaper.id);
    return true;
  });

  return items.length > 0 ? { items } : undefined;
}

export function wallpaperDetailPath(wallpaper: Wallpaper): string {
  return `/wallpaper/${wallpaper.slug || wallpaper.id}`;
}
