import axios from 'axios';
import i18n from '../i18n';
import { requestStarted, requestSettled } from '../lib/pageProgress';

export function resolveBaseURL(): string {
  // Cloudflare Pages and the dev Vite server both expose the API on the
  // same origin under /api/v1. Relative paths keep browser traffic on the
  // canonical wallpaperexchange.com domain in production.
  if (import.meta.env.VITE_API_BASE_URL) {
    return import.meta.env.VITE_API_BASE_URL;
  }
  return '/api/v1';
}

// Large request bodies should not pass through the apex-domain Pages
// Function. That extra streaming proxy can finish receiving the browser
// upload before the origin has the full body, which makes XHR report 100%
// while the request is still crossing the origin tunnel. In production we
// post straight to the public Tunnel hostname; local development keeps using
// the Vite /api proxy. A dedicated env override remains available for preview
// deployments or a future upload origin.
export function resolveUploadBaseURL(): string {
  if (import.meta.env.VITE_UPLOAD_API_BASE_URL) {
    return import.meta.env.VITE_UPLOAD_API_BASE_URL.replace(/\/$/, '');
  }
  if (typeof window !== 'undefined') {
    const hostname = window.location.hostname;
    if (hostname === 'wallpaperexchange.com' || hostname === 'www.wallpaperexchange.com') {
      return 'https://api.wallpaperexchange.com/api/v1';
    }
  }
  return resolveBaseURL();
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
  // The backend localizes content fields (category/tag names, collection
  // titles) from this header; react-query caches are invalidated on
  // language change (see main.tsx) so responses refetch in the new language.
  config.headers['Accept-Language'] = i18n.language;
  config.headers['X-Wallpaper-Client'] = 'web';
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
    // Localize known business error codes in place so every existing
    // `err.response.data.message` / toast call site shows the user's
    // language without per-page wiring. Unknown codes keep the server text.
    const biz = error.response?.data;
    if (biz && typeof biz.code === 'number') {
      const localized = i18n.t(`apiErrors.${biz.code}`, { defaultValue: '' });
      if (localized) {
        biz.message = localized;
        error.message = localized;
      }
    }
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
