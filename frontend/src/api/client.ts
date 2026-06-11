import axios from 'axios';
import { requestStarted, requestSettled } from '../lib/pageProgress';

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
  requestStarted(config.url);
  return config;
});

// On any 401, clear local auth so the store doesn't keep a stale "logged
// in" view, then bounce to /login with a marker so the page can show a
// session-expired toast. The previous version only wiped localStorage and
// did a full reload; that worked but the Zustand store was still holding
// the old user in memory until the reload landed.
let onAuthExpired: (() => void) | null = null;
export function setAuthExpiredHandler(fn: () => void) {
  onAuthExpired = fn;
}

client.interceptors.response.use(
  (response) => {
    requestSettled(response.config.url);
    return response;
  },
  (error) => {
    requestSettled(error.config?.url);
    if (error.response?.status === 401) {
      const wasAuthed = !!localStorage.getItem('token');
      localStorage.removeItem('token');
      localStorage.removeItem('user');
      // Surface to the app (store reset + toast). Only fire when the user
      // actually was authenticated; otherwise a 401 on a public guarded
      // endpoint would falsely "kick them out" of nothing.
      if (wasAuthed && onAuthExpired) onAuthExpired();
      // Hard navigation kept as a last-resort fallback; in normal flow
      // the React layer will redirect via Router after auth state clears.
      if (wasAuthed && !window.location.pathname.startsWith('/login')) {
        window.location.href = '/login?expired=1';
      }
    }
    return Promise.reject(error);
  }
);

export default client;
