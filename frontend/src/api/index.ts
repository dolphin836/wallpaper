import client from './client';
import type { ApiResponse, AuthResponse, Wallpaper, WallpaperDetail, PaginatedData, Category, Tag, User, DeviceProfile, WallpaperVariant, Collection, CollectionDetail, CollectionBrief, CoinTransaction } from '../types';

export const register = (data: { username: string; email: string; password: string }) =>
  client.post<ApiResponse<AuthResponse>>('/auth/register', data);

export const login = (data: { email: string; password: string }) =>
  client.post<ApiResponse<AuthResponse>>('/auth/login', data);

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
}) => client.get<ApiResponse<PaginatedData<Wallpaper>>>('/wallpapers', { params });

export const getWallpaper = (id: number) =>
  client.get<ApiResponse<WallpaperDetail>>(`/wallpapers/${id}`);

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

export const downloadWallpaper = (id: number) =>
  `/api/v1/wallpapers/${id}/download`;

export const getCategories = () =>
  client.get<ApiResponse<Category[]>>('/categories');

export const getTags = () =>
  client.get<ApiResponse<Tag[]>>('/tags');

export const getUserProfile = (id: number) =>
  client.get<ApiResponse<User>>(`/users/${id}`);

export const getUserWallpapers = (id: number, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>(`/users/${id}/wallpapers`, { params });

export const getMyFavorites = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>('/users/me/favorites', { params });

export const getMyLikes = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>('/users/me/likes', { params });

export const getDevices = () =>
  client.get<ApiResponse<DeviceProfile[]>>('/devices');

export const getWallpaperVariants = (wallpaperId: number) =>
  client.get<ApiResponse<WallpaperVariant[]>>(`/wallpapers/${wallpaperId}/variants`);

export const getCollections = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Collection>>>('/collections', { params });

export const getCollection = (id: number) =>
  client.get<ApiResponse<CollectionDetail>>(`/collections/${id}`);

export const createCollection = (data: { title: string; description?: string; is_public?: boolean }) =>
  client.post<ApiResponse<Collection>>('/collections', data);

export const updateCollection = (id: number, data: { title: string; description?: string; is_public?: boolean }) =>
  client.put<ApiResponse<null>>(`/collections/${id}`, data);

export const deleteCollection = (id: number) =>
  client.delete<ApiResponse<null>>(`/collections/${id}`);

export const getCollectionWallpapers = (id: number, params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Wallpaper>>>(`/collections/${id}/wallpapers`, { params });

export const addToCollection = (collectionId: number, wallpaperId: number) =>
  client.post<ApiResponse<null>>(`/collections/${collectionId}/wallpapers`, { wallpaper_id: wallpaperId });

export const removeFromCollection = (collectionId: number, wallpaperId: number) =>
  client.delete<ApiResponse<null>>(`/collections/${collectionId}/wallpapers/${wallpaperId}`);

export const likeCollection = (id: number) =>
  client.post<ApiResponse<null>>(`/collections/${id}/like`);

export const unlikeCollection = (id: number) =>
  client.delete<ApiResponse<null>>(`/collections/${id}/like`);

export const getMyCollections = () =>
  client.get<ApiResponse<CollectionBrief[]>>('/users/me/collections');

export const getUserCollections = (userId: number, params?: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<Collection>>>(`/users/${userId}/collections`, { params });

export const downloadVariant = (wallpaperId: number, variantId: number) =>
  client.post<ApiResponse<{ url: string }>>(`/wallpapers/${wallpaperId}/variants/${variantId}/download`);

export const getMyCoins = () =>
  client.get<ApiResponse<{ coins: number }>>('/users/me/coins');

export const getCoinTransactions = (params: { cursor?: number; limit?: number }) =>
  client.get<ApiResponse<PaginatedData<CoinTransaction>>>('/users/me/coin-transactions', { params });
