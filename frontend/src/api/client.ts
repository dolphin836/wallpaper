import axios from 'axios';

export function resolveBaseURL(): string {
  // Every prod surface — wallpaperexchange.com (CF Pages with _redirects),
  // wallpaper.haibing.site (Caddy with /api/* handle), and the dev Vite
  // server (proxy to :8080) — exposes the API on the same origin under
  // /api/v1. Relative paths just work everywhere; no per-host branching.
  if (import.meta.env.VITE_API_BASE_URL) {
    return import.meta.env.VITE_API_BASE_URL;
  }
  return '/api/v1';
}

const client = axios.create({
  baseURL: resolveBaseURL(),
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

client.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

client.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

export default client;
