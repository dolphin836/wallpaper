export interface User {
  id: number;
  username: string;
  email: string;
  nickname: string;
  avatar_url: string;
  bio: string;
  coins: number;
  status: number;
  created_at: string;
}

export interface UserListItem extends User {
  wallpaper_count: number;
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
  user_id: number;
  category_id: number;
  title: string;
  description: string;
  original_url: string;
  thumb_url: string;
  preview_url: string;
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
}

export interface Collection {
  id: number;
  user_id: number;
  title: string;
  description: string;
  cover_url: string;
  is_public: boolean;
  wallpaper_count: number;
  view_count: number;
  like_count: number;
  is_liked?: boolean;
  created_at: string;
  updated_at: string;
}

export interface CollectionDetail extends Collection {
  is_liked: boolean;
}

export interface CollectionBrief {
  id: number;
  title: string;
  wallpaper_count: number;
}
