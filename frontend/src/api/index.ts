import client, { resolveBaseURL } from './client';
import type { ApiResponse, AuthResponse, Wallpaper, WallpaperDetail, PaginatedData, Category, Tag, User, UserListItem, DeviceProfile, WallpaperVariant, Collection, CollectionDetail, CollectionBrief, CoinTransaction, Engagements, MacRelease, AndroidRelease, ChromeRelease } from '../types';

const LANDING_KEY = 'wpe_landing_path';
const REFERRER_KEY = 'wpe_initial_referrer';
const SOURCE_KEY = 'wpe_initial_source';

function authAttribution() {
  if (typeof window === 'undefined') {
    return { client: 'web' };
  }
  let landing = '';
  try {
    landing = sessionStorage.getItem(LANDING_KEY) || '';
    if (!landing) {
      landing = window.location.pathname + window.location.search;
      sessionStorage.setItem(LANDING_KEY, landing);
    }
  } catch {
    landing = window.location.pathname + window.location.search;
  }

  const params = new URLSearchParams(window.location.search);
  let storedSource = '';
  let storedReferrer = '';
  try {
    storedSource = sessionStorage.getItem(SOURCE_KEY) || '';
    storedReferrer = sessionStorage.getItem(REFERRER_KEY) || '';
  } catch {
    storedSource = '';
    storedReferrer = '';
  }
  return {
    client: 'web',
    source: storedSource || params.get('utm_source') || params.get('source') || params.get('ref') || '',
    referrer: storedReferrer || document.referrer || '',
    landing_path: landing,
  };
}

export const register = (data: { username: string; email: string; password: string }) =>
  client.post<ApiResponse<AuthResponse>>('/auth/register', { ...authAttribution(), ...data });

export const login = (data: { email: string; password: string }) =>
  client.post<ApiResponse<AuthResponse>>('/auth/login', { client: 'web', ...data });

// Verify the current token + return the latest user payload. Called on app
// boot so we can detect a server-expired session (the client otherwise
// trusts localStorage and shows "logged in" until the user triggers a
// real authenticated call).
export const getMe = () => client.get<ApiResponse<User>>('/users/me');

export const getWallpapers = (params: {
  cursor?: number;
  limit?: number;
  category_id?: number;
  sort?: string;
  search?: string;
  device_width?: number;
  device_height?: number;
  include_dynamic?: boolean;
  dynamic_only?: boolean;
  ai_only?: boolean;
  video_only?: boolean;
}) => client.get<ApiResponse<PaginatedData<Wallpaper>>>('/wallpapers', { params });

export const getWallpaper = (slug: string) =>
  client.get<ApiResponse<WallpaperDetail>>(`/wallpapers/${slug}`);

export const uploadWallpaper = (formData: FormData) =>
  client.post<ApiResponse<Wallpaper>>('/wallpapers', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
    timeout: 60000,
  });

export const deleteWallpaper = (id: number) =>
  client.delete<ApiResponse<null>>(`/wallpapers/${id}`);

export const likeWallpaper = (id: number) =>
  client.post<ApiResponse<null>>(`/wallpapers/${id}/like`);

export const unlikeWallpaper = (id: number) =>
  client.delete<ApiResponse<null>>(`/wallpapers/${id}/like`);

export const favoriteWallpaper = (id: number) =>
  client.post<ApiResponse<null>>(`/wallpapers/${id}/favorite`);

export const unfavoriteWallpaper = (id: number) =>
  client.delete<ApiResponse<null>>(`/wallpapers/${id}/favorite`);

export const reportWallpaper = (id: number, reason: string, note: string) =>
  client.post<ApiResponse<null>>(`/wallpapers/${id}/report`, { reason, note });

export const getSimilarWallpapers = (id: number, limit = 12) =>
  client.get<ApiResponse<Wallpaper[]>>(`/wallpapers/${id}/similar`, { params: { limit } });

export const getForYouWallpapers = (limit = 30) =>
  client.get<ApiResponse<Wallpaper[]>>('/wallpapers/for-you', { params: { limit } });

export const downloadWallpaper = (id: number) =>
  `${resolveBaseURL()}/wallpapers/${id}/download`;

export const getCategories = () =>
  client.get<ApiResponse<Category[]>>('/categories');

// ── Weekly Picks ────────────────────────────────────────────────────
// The Home page reads `current` to render both the picks rail and the
// theme-collection cards in one shot. `archive` powers the "past weeks"
// listing page, and `byWeek` is the detail view for a specific slate.
export interface WeeklyPicked extends Wallpaper {
  sort_order: number;
  // Marks the hero pick — only it gets a non-empty original_url. Backend
  // ensures at most one per (year, week) and falls back to sort_order=0
  // for legacy slates predating the column.
  is_hero: boolean;
}
export interface WeeklyArchiveEntry {
  year: number;
  week: number;
  count: number;
  cover_url: string;
  original_url?: string;
  accent_color?: string;
  // Cover wallpaper's extracted palette + dominant colour, used by
  // the archive page to tint its mesh when the user selects an
  // issue from the timeline.
  dominant_color?: string;
  color_palette?: string;
}
export interface WeeklyCurrent {
  year: number;
  week: number;
  picks: WeeklyPicked[];
  themes: Collection[];
}
export const getWeeklyCurrent = () =>
  client.get<ApiResponse<WeeklyCurrent>>('/weekly-picks/current');
export const getWeeklyArchive = (limit = 50) =>
  client.get<ApiResponse<WeeklyArchiveEntry[]>>('/weekly-picks/archive', { params: { limit } });
export const getWeeklyByWeek = (year: number, week: number) =>
  client.get<ApiResponse<{ year: number; week: number; picks: WeeklyPicked[] }>>(`/weekly-picks/${year}/${week}`);

export const getTags = () =>
  client.get<ApiResponse<Tag[]>>('/tags');

export const getUsers = (params: { page?: number; limit?: number; sort?: string }) =>
  client.get<ApiResponse<{ items: UserListItem[]; total: number; page: number; limit: number }>>('/users', { params });

export const getUserProfile = (username: string) =>
  client.get<ApiResponse<User>>(`/users/${username}`);

// `status` accepts a single int (e.g. 1 = published) or a comma-separated
// list (e.g. "0,5" for Processing + PendingReview) — the backend handles both.
export const getUserWallpapers = (
  username: string,
  params: { cursor?: number; limit?: number; status?: number | string },
) => client.get<ApiResponse<PaginatedData<Wallpaper>>>(`/users/${username}/wallpapers`, { params });

// Public companions to /users/me/{likes,favorites,downloads}. Each returns
// either the standard PaginatedData<Wallpaper> shape, or an empty payload
// with `private: true` when the viewer isn't the owner and the list is set
// to private — frontend keys off that flag to render the "Hidden" state.
export interface PaginatedOrHidden<T> {
  items: T[];
  next_cursor: number;
  has_more: boolean;
  total?: number;
  private?: boolean;
}
export const getUserLikes = (idOrUsername: string | number, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedOrHidden<Wallpaper>>>(`/users/${idOrUsername}/likes`, { params });
export const getUserFavorites = (idOrUsername: string | number, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedOrHidden<Wallpaper>>>(`/users/${idOrUsername}/favorites`, { params });
export const getUserDownloads = (idOrUsername: string | number, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedOrHidden<Wallpaper>>>(`/users/${idOrUsername}/downloads`, { params });

export const updatePrivacy = (
  data: { likes_public?: boolean; favorites_public?: boolean; downloads_public?: boolean }
) => client.put<ApiResponse<User>>('/users/me/privacy', data);

export const getMyFavorites = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>('/users/me/favorites', { params });

export const getMyLikes = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>('/users/me/likes', { params });

export const getMyDownloads = (params: {
  cursor?: number;
  limit?: number;
  device_width?: number;
  device_height?: number;
  dynamic_only?: boolean;
  include_dynamic?: boolean;
}) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>('/users/me/downloads', { params });

export const getDevices = () =>
  client.get<ApiResponse<DeviceProfile[]>>('/devices');

export const getDeviceBySlug = (slug: string) =>
  client.get<ApiResponse<{ device: DeviceProfile; wallpaper_count: number }>>(`/devices/${slug}`);

export const getWallpapersForDevice = (
  slug: string,
  params: { cursor?: number; limit?: number } = {}
) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>(`/devices/${slug}/wallpapers`, { params });

export const getWallpaperVariants = (wallpaperId: number) =>
  client.get<ApiResponse<WallpaperVariant[]>>(`/wallpapers/${wallpaperId}/variants`);

export const getWallpaperEngagements = (wallpaperId: number) =>
  client.get<ApiResponse<Engagements>>(`/wallpapers/${wallpaperId}/engagements`);

export const getCollections = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Collection>>>('/collections', { params });

export const getCollection = (slug: string) =>
  client.get<ApiResponse<CollectionDetail>>(`/collections/${slug}`);

export const createCollection = (data: { title: string; description?: string; is_public?: boolean }) =>
  client.post<ApiResponse<Collection>>('/collections', data);

export const updateCollection = (id: number, data: { title: string; description?: string; is_public?: boolean }) =>
  client.put<ApiResponse<null>>(`/collections/${id}`, data);

export const deleteCollection = (id: number) =>
  client.delete<ApiResponse<null>>(`/collections/${id}`);

export const getCollectionWallpapers = (slug: string, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>(`/collections/${slug}/wallpapers`, { params });

export const addToCollection = (collectionId: number, wallpaperId: number) =>
  client.post<ApiResponse<null>>(`/collections/${collectionId}/wallpapers`, { wallpaper_id: wallpaperId });

export const removeFromCollection = (collectionId: number, wallpaperId: number) =>
  client.delete<ApiResponse<null>>(`/collections/${collectionId}/wallpapers/${wallpaperId}`);

export const likeCollection = (id: number) =>
  client.post<ApiResponse<null>>(`/collections/${id}/like`);

export const unlikeCollection = (id: number) =>
  client.delete<ApiResponse<null>>(`/collections/${id}/like`);

export const getMyCollections = (params?: { q?: string; wallpaper_id?: number; limit?: number }) =>
  client.get<ApiResponse<CollectionBrief[]>>('/users/me/collections', { params });

export const getUserCollections = (username: string, params?: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Collection>>>(`/users/${username}/collections`, { params });

export const updateProfile = (data: { nickname: string; bio: string }) =>
  client.put<ApiResponse<User>>('/users/me/profile', data);

export const uploadAvatar = (formData: FormData) =>
  client.post<ApiResponse<{ avatar_url: string }>>('/users/me/avatar', formData, {
    headers: { 'Content-Type': 'multipart/form-data' },
  });

export const changePassword = (data: { old_password: string; new_password: string }) =>
  client.put<ApiResponse<null>>('/users/me/password', data);

export const getMyCoins = () =>
  client.get<ApiResponse<{ coins: number }>>('/users/me/coins');

export const getCoinTransactions = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<CoinTransaction>>>('/users/me/coin-transactions', { params });

export const getMacRelease = () =>
  client.get<ApiResponse<MacRelease>>('/mac/release');

export const getAndroidRelease = () =>
  client.get<ApiResponse<AndroidRelease>>('/android/release');

export const getChromeRelease = async () => {
  const response = await fetch('/downloads/chrome/chrome_release.json', {
    cache: 'no-store',
  });

  if (!response.ok) {
    throw new Error(`Failed to load Chrome release manifest: ${response.status}`);
  }

  return response.json() as Promise<ChromeRelease>;
};

export interface PublicStats { wallpapers: number; collections: number }
export const getPublicStats = () => client.get<ApiResponse<PublicStats>>('/stats');
