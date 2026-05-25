// Wire types — kept in sync with backend/internal/model/wallpaper.go
// and backend/internal/service/wallpaper.go. We intentionally only
// declare the fields the client actually reads; the server is free
// to send more.

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
  width: number;
  height: number;
  file_size: number;
  file_type: string;
  dominant_color: string;
  status: number;
  is_dynamic: boolean;
  is_ai_generated?: boolean;
  created_at: string;
}

export interface User {
  id: number;
  username: string;
  email: string;
  coins: number;
  is_admin?: boolean;
}

export interface AuthResponse {
  user: User;
  token: string;
}

export interface ApiResponse<T> {
  code: number;
  message: string;
  data: T;
}

export interface ListResponse<T> {
  items: T[];
  next_cursor: number;
  has_more: boolean;
}
