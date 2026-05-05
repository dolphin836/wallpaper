import client from './client';
import type { ApiResponse, AuthResponse, Wallpaper, WallpaperDetail, PaginatedData, Category, Tag, User, DeviceProfile, WallpaperVariant } from '../types';

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

export const getDevices = () =>
  client.get<ApiResponse<DeviceProfile[]>>('/devices');

export const getWallpaperVariants = (wallpaperId: number) =>
  client.get<ApiResponse<WallpaperVariant[]>>(`/wallpapers/${wallpaperId}/variants`);
