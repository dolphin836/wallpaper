// Thin wrappers around the Rust Tauri commands defined in
// src-tauri/src/*.rs. Centralizing them here means the screens can
// import a typed surface instead of sprinkling `invoke()` calls
// everywhere.

import { invoke } from '@tauri-apps/api/core';

export interface DownloadedItem {
  id: number;
  path: string;
}

export const cmd = {
  downloadWallpaper(id: number, url: string): Promise<string> {
    return invoke('download_wallpaper', { id, url });
  },
  setWallpaperById(id: number, url: string): Promise<string> {
    return invoke('set_wallpaper_by_id', { id, url });
  },
  setStaticWallpaper(path: string): Promise<void> {
    return invoke('set_static_wallpaper', { path });
  },
  listDownloaded(): Promise<DownloadedItem[]> {
    return invoke('list_downloaded');
  },
  removeDownloaded(id: number): Promise<void> {
    return invoke('remove_downloaded', { id });
  },
  downloadsTotalBytes(): Promise<number> {
    return invoke('downloads_total_bytes');
  },
};
