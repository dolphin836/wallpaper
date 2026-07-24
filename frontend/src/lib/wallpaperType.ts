import type { Wallpaper } from '../types';

type WallpaperPlatformFields = Pick<Wallpaper, 'is_dynamic' | 'file_type'>;

export function isMacDynamicWallpaper(
  wallpaper: WallpaperPlatformFields | null | undefined,
): boolean {
  return Boolean(wallpaper?.is_dynamic)
    && !(wallpaper?.file_type || '').startsWith('video/');
}
