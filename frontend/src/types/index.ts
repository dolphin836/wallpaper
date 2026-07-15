export interface User {
  id: number;
  username: string;
  email: string;
  nickname: string;
  avatar_url: string;
  bio: string;
  coins: number;
  status: number;
  is_admin?: boolean;
  likes_public?: boolean;
  favorites_public?: boolean;
  downloads_public?: boolean;
  register_client?: string;
  register_source?: string;
  register_referrer?: string;
  register_path?: string;
  register_ip?: string;
  register_country?: string;
  created_at: string;
}

export interface UserListItem extends User {
  wallpaper_count: number;
  total_downloads?: number;
  recent_thumbs?: string[];
  recent_tints?: string[];
}

export interface CoinTransaction {
  id: number;
  user_id: number;
  amount: number;
  balance: number;
  tx_type: string;
  ref_id: number;
  description: string;
  created_at: string;
}

export interface Wallpaper {
  id: number;
  slug: string;
  user_id: number;
  category_id: number;
  title: string;
  description: string;
  original_url: string;
  thumb_url: string;
  preview_url: string;
  preview_video_url?: string;
  width: number;
  height: number;
  file_size: number;
  file_type: string;
  dominant_color: string;
  color_palette: string;
  status: number;
  view_count: number;
  like_count: number;
  download_count: number;
  favorite_count: number;
  is_liked: boolean;
  is_favorited: boolean;
  is_downloaded: boolean;
  is_dynamic: boolean;
  dynamic_type: string;
  frame_urls: string;
  is_ai_generated?: boolean;
  rejection_reason?: string;
  quality_flag?: string;
  quality_notes?: string;
  created_at: string;
  updated_at: string;
}

export interface WallpaperDetail extends Wallpaper {
  tags: Tag[];
  is_liked: boolean;
  is_favorited: boolean;
  uploader: User;
}

export interface Category {
  id: number;
  name: string;
  slug: string;
  sort_order: number;
}

export interface Tag {
  id: number;
  name: string;
}

export interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

export interface PaginatedData<T> {
  items: T[];
  next_cursor: number;
  has_more: boolean;
  total?: number;
}

export interface AuthResponse {
  token: string;
  user: User;
}

export interface DeviceProfile {
  id: number;
  platform: string;
  brand: string;
  name: string;
  slug: string;
  width: number;
  height: number;
  ppi: number;
  sort_order: number;
  is_active: boolean;
}

export interface WallpaperVariant {
  id: number;
  wallpaper_id: number;
  device_id: number;
  url: string;
  width: number;
  height: number;
  file_size: number;
  created_at: string;
  platform: string;
  brand: string;
  device_name: string;
  device_slug: string;
}

export interface Collection {
  id: number;
  slug: string;
  user_id: number;
  title: string;
  description: string;
  cover_url: string;
  is_public: boolean;
  wallpaper_count: number;
  view_count: number;
  like_count: number;
  is_liked?: boolean;
  recent_tiles?: CollectionTile[];
  author_username?: string;
  kind?: number;
  year?: number;
  week?: number;
  accent_color?: string;
  created_at: string;
  updated_at: string;
}

export interface CollectionTile {
  thumb_url: string;
  preview_url: string;
  dominant_color: string;
}

export interface CollectionDetail extends Collection {
  is_liked: boolean;
}

export interface CollectionBrief {
  id: number;
  title: string;
  wallpaper_count: number;
  // Set by the Add-to-list endpoint when called with wallpaper_id —
  // tells the picker which rows the current wallpaper is already in
  // so they can be marked + disabled.
  contains_wallpaper?: boolean;
}

export interface EngagementUser {
  id: number;
  username: string;
  nickname: string;
  avatar_url: string;
}

export interface Engagements {
  likers: EngagementUser[];
  favoriters: EngagementUser[];
  downloaders: EngagementUser[];
}

export interface MacReleaseEntry {
  version: string;
  released_at: string;
  notes: string[];
  // Translated notes keyed by UI language ("zh-CN" / "zh-TW" / "ja");
  // English lives in `notes` (old Mac clients hard-decode that shape).
  notes_i18n?: Record<string, string[]>;
}

export interface MacRelease {
  current_version: string;
  current_dmg_url: string;
  min_macos_version: string;
  releases: MacReleaseEntry[];
}

export interface AndroidRelease {
  current_version: string;
  current_version_code: number;
  minimum_version_code: number;
  current_apk_url: string;
  apk_sha256: string;
  released_at: string;
  notes: string[];
  notes_i18n?: Record<string, string[]>;
}

export interface ChromeRelease {
  current_version: string;
  current_zip_url: string;
  zip_sha256: string;
  released_at: string;
}
