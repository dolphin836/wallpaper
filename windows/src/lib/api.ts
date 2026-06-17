// API client for the Windows Tauri app. It uses the Tauri HTTP plugin so the
// desktop WebView is not constrained by browser CORS, and it points at the same
// apex-domain API the macOS client now uses.

import { fetch as tauriFetch } from '@tauri-apps/plugin-http';
import { getToken } from './auth';
import type {
  ApiResponse,
  AuthResponse,
  Category,
  CoinTransaction,
  CollectionBrief,
  CollectionItem,
  EmptyData,
  ListResponse,
  User,
  Wallpaper,
  WallpaperDetail,
  WeeklyArchiveEntry,
  WeeklyByWeek,
  WeeklyCurrent,
} from './types';

const API_BASE = 'https://wallpaperexchange.com/api/v1';

type QueryValue = string | number | boolean | null | undefined;

async function request<T>(
  path: string,
  init: {
    method?: string;
    body?: unknown;
    auth?: boolean;
    query?: Record<string, QueryValue>;
  } = {},
): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
    'Accept-Language': 'zh-CN',
  };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';

  if (init.auth !== false) {
    const tok = await getToken();
    if (tok) headers.Authorization = `Bearer ${tok}`;
  }

  const qs = init.query ? buildQuery(init.query) : '';
  const res = await tauriFetch(API_BASE + path + qs, {
    method: init.method ?? 'GET',
    headers,
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });

  if (!res.ok) {
    let msg = `HTTP ${res.status}`;
    try {
      const j = (await res.json()) as { message?: string };
      if (j.message) msg = j.message;
    } catch {
      // Keep the HTTP status fallback.
    }
    throw new Error(msg);
  }

  const body = (await res.json()) as ApiResponse<T>;
  if (body.code !== 0 && body.code !== 200) {
    throw new Error(body.message || `API code ${body.code}`);
  }
  return body.data;
}

function buildQuery(query: Record<string, QueryValue>): string {
  const items = Object.entries(query)
    .filter(([, value]) => value !== undefined && value !== null && value !== '')
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
  return items.length ? `?${items.join('&')}` : '';
}

function enc(value: string | number): string {
  return encodeURIComponent(String(value));
}

export const api = {
  login(email: string, password: string) {
    return request<AuthResponse>('/auth/login', {
      method: 'POST',
      body: { email, password },
      auth: false,
    });
  },

  register(username: string, email: string, password: string) {
    return request<AuthResponse>('/auth/register', {
      method: 'POST',
      body: { username, email, password },
      auth: false,
    });
  },

  me() {
    return request<User>('/users/me');
  },

  updateProfile(nickname: string, bio: string) {
    return request<User>('/users/me/profile', {
      method: 'PUT',
      body: { nickname, bio },
    });
  },

  changePassword(oldPassword: string, newPassword: string) {
    return request<EmptyData>('/users/me/password', {
      method: 'PUT',
      body: { old_password: oldPassword, new_password: newPassword },
    });
  },

  listWallpapers(params: {
    limit?: number;
    cursor?: number | null;
    sort?: string;
    search?: string;
    category_id?: number | null;
    dynamic_only?: boolean;
    ai_only?: boolean;
    exclude_dynamic?: boolean;
    exclude_video?: boolean;
    include_dynamic?: boolean;
    device_width?: number;
    device_height?: number;
  } = {}) {
    return request<ListResponse<Wallpaper>>('/wallpapers', { query: params });
  },

  forYou(limit = 30) {
    return request<Wallpaper[]>('/wallpapers/for-you', { query: { limit } });
  },

  getWallpaper(idOrSlug: string | number) {
    return request<WallpaperDetail>(`/wallpapers/${enc(idOrSlug)}`);
  },

  similar(wallpaperID: number, limit = 12) {
    return request<Wallpaper[]>(`/wallpapers/${enc(wallpaperID)}/similar`, { query: { limit } });
  },

  categories() {
    return request<Category[]>('/categories', { auth: false });
  },

  weeklyCurrent() {
    return request<WeeklyCurrent>('/weekly-picks/current', { auth: false });
  },

  weeklyArchive(limit = 50) {
    return request<WeeklyArchiveEntry[]>('/weekly-picks/archive', {
      auth: false,
      query: { limit },
    });
  },

  weeklyByWeek(year: number, week: number) {
    return request<WeeklyByWeek>(`/weekly-picks/${enc(year)}/${enc(week)}`, { auth: false });
  },

  listCollections(params: { limit?: number; cursor?: number | null; kind?: number } = {}) {
    return request<ListResponse<CollectionItem>>('/collections', { query: params });
  },

  getCollection(idOrSlug: string | number) {
    return request<CollectionItem>(`/collections/${enc(idOrSlug)}`);
  },

  listCollectionWallpapers(collectionID: number, params: { limit?: number; cursor?: number | null } = {}) {
    return request<ListResponse<Wallpaper>>(`/collections/${enc(collectionID)}/wallpapers`, {
      query: params,
    });
  },

  listMyCollections(params: { q?: string; wallpaper_id?: number; limit?: number } = {}) {
    return request<CollectionBrief[]>('/users/me/collections', { query: params });
  },

  createCollection(title: string, isPublic = true) {
    return request<CollectionItem>('/collections', {
      method: 'POST',
      body: { title, is_public: isPublic },
    });
  },

  addToCollection(collectionID: number, wallpaperID: number) {
    return request<EmptyData>(`/collections/${enc(collectionID)}/wallpapers`, {
      method: 'POST',
      body: { wallpaper_id: wallpaperID },
    });
  },

  removeFromCollection(collectionID: number, wallpaperID: number) {
    return request<EmptyData>(`/collections/${enc(collectionID)}/wallpapers/${enc(wallpaperID)}`, {
      method: 'DELETE',
    });
  },

  listMyDownloads(params: { limit?: number; cursor?: number | null; dynamic_only?: boolean } = {}) {
    return request<ListResponse<Wallpaper>>('/users/me/downloads', { query: params });
  },

  listMyFavorites(params: { limit?: number; cursor?: number | null } = {}) {
    return request<ListResponse<Wallpaper>>('/users/me/favorites', { query: params });
  },

  listMyLikes(params: { limit?: number; cursor?: number | null } = {}) {
    return request<ListResponse<Wallpaper>>('/users/me/likes', { query: params });
  },

  coinTransactions(params: { limit?: number; cursor?: number | null } = {}) {
    return request<ListResponse<CoinTransaction>>('/users/me/coin-transactions', { query: params });
  },

  like(wallpaperID: number) {
    return request<EmptyData>(`/wallpapers/${enc(wallpaperID)}/like`, { method: 'POST' });
  },

  unlike(wallpaperID: number) {
    return request<EmptyData>(`/wallpapers/${enc(wallpaperID)}/like`, { method: 'DELETE' });
  },

  favorite(wallpaperID: number) {
    return request<EmptyData>(`/wallpapers/${enc(wallpaperID)}/favorite`, { method: 'POST' });
  },

  unfavorite(wallpaperID: number) {
    return request<EmptyData>(`/wallpapers/${enc(wallpaperID)}/favorite`, { method: 'DELETE' });
  },

  reportWallpaper(wallpaperID: number, reason = 'other', note = '') {
    return request<EmptyData>(`/wallpapers/${enc(wallpaperID)}/report`, {
      method: 'POST',
      body: { reason, note },
    });
  },

  async getDownloadURL(id: number): Promise<string> {
    const tok = await getToken();
    const headers: Record<string, string> = {
      Accept: 'application/json',
      'Accept-Language': 'zh-CN',
    };
    if (tok) headers.Authorization = `Bearer ${tok}`;
    const res = await tauriFetch(`${API_BASE}/wallpapers/${enc(id)}/download`, {
      method: 'GET',
      headers,
      maxRedirections: 0,
    });
    if (res.status === 401) throw new Error('请先登录');
    if (res.status === 402) throw new Error('金币不足');
    const location = res.headers.get('Location') || res.headers.get('location');
    if (!location) throw new Error(`没有拿到下载地址：${res.status}`);
    return location;
  },
};
