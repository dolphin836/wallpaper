// Wire types used by the Windows desktop client. Field names mirror the
// backend JSON payloads so the React layer can pass API objects around without
// lossy mapping. Most optional fields are intentionally tolerated because list
// endpoints return lighter shapes than detail endpoints.

export interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

export interface ListResponse<T> {
  items: T[];
  next_cursor?: number | null;
  has_more: boolean;
  total?: number | null;
}

export interface User {
  id: number;
  username: string;
  email?: string | null;
  nickname?: string | null;
  avatar_url?: string | null;
  bio?: string | null;
  coins: number;
  status?: number;
  likes_public?: boolean | null;
  favorites_public?: boolean | null;
  downloads_public?: boolean | null;
  created_at?: string;
  is_admin?: boolean;
}

export interface AuthResponse {
  user: User;
  token: string;
}

export interface Tag {
  id: number;
  name: string;
  slug?: string | null;
}

export interface Category {
  id: number;
  name: string;
  slug: string;
  sort_order?: number | null;
}

export interface WallpaperUploader {
  id: number;
  username: string;
  nickname?: string | null;
  avatar_url?: string | null;
  bio?: string | null;
}

export interface Wallpaper {
  id: number;
  slug: string;
  user_id: number;
  category_id?: number | null;
  title: string;
  description?: string | null;
  original_url?: string | null;
  thumb_url?: string | null;
  preview_url?: string | null;
  preview_video_url?: string | null;
  width: number;
  height: number;
  file_size: number;
  file_type: string;
  dominant_color?: string | null;
  color_palette?: string | null;
  frame_urls?: string | null;
  status?: number;
  view_count?: number;
  like_count?: number;
  download_count?: number;
  favorite_count?: number;
  is_dynamic: boolean;
  is_ai_generated?: boolean | null;
  is_liked?: boolean | null;
  is_favorited?: boolean | null;
  is_downloaded?: boolean | null;
  created_at: string;
  tags?: Tag[] | null;
  uploader?: WallpaperUploader | null;
}

export type WallpaperDetail = Wallpaper;

export interface CollectionTile {
  thumb_url?: string | null;
  preview_url?: string | null;
  dominant_color?: string | null;
}

export interface CollectionBrief {
  id: number;
  title: string;
  wallpaper_count: number;
  contains_wallpaper?: boolean | null;
}

export interface CollectionItem {
  id: number;
  slug: string;
  title: string;
  description?: string | null;
  cover_url?: string | null;
  wallpaper_count: number;
  is_public?: boolean | null;
  user_id?: number | null;
  created_at?: string | null;
  updated_at?: string | null;
  recent_tiles?: CollectionTile[] | null;
  kind?: number | null;
  accent_color?: string | null;
  like_count?: number | null;
  is_liked?: boolean | null;
}

export interface WeeklyPicked extends Wallpaper {
  sort_order: number;
  is_hero: boolean;
}

export interface WeeklyCurrent {
  year: number;
  week: number;
  picks: WeeklyPicked[];
  themes?: CollectionItem[] | null;
}

export interface WeeklyByWeek {
  year: number;
  week: number;
  picks: WeeklyPicked[];
}

export interface WeeklyArchiveEntry {
  year: number;
  week: number;
  count: number;
  cover_url: string;
  accent_color?: string | null;
  dominant_color?: string | null;
  color_palette?: string | null;
}

export interface CoinTransaction {
  id: number;
  amount: number;
  balance_after?: number;
  type?: string;
  reason?: string;
  created_at?: string;
}

export interface EmptyData {
  ok?: boolean;
}
