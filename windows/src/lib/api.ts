// API client. Uses the Tauri HTTP plugin so we can talk to
// wallpaperexchange.com directly without browser CORS rules in our
// way. The base URL is the same prod endpoint the web + macOS
// clients use.
//
// One difference from the web client: the JWT lives in Tauri's local
// app data (via the auth module), not in localStorage — same
// reasoning as the macOS app, since browser localStorage clears with
// WebView2 user-data resets.

import { fetch as tauriFetch } from '@tauri-apps/plugin-http';
import { getToken } from './auth';
import type { ApiResponse, AuthResponse, ListResponse, User, Wallpaper } from './types';

// Apex domain serves /api/v1 via Caddy → Go api container. The
// api.wallpaperexchange.com subdomain isn't routed in prod (returns
// connection-reset), so the macOS client's hardcoded subdomain is
// actually wrong — we point at the apex directly here.
const API_BASE = 'https://wallpaperexchange.com/api/v1';

async function request<T>(
  path: string,
  init: {
    method?: string;
    body?: unknown;
    auth?: boolean;
    query?: Record<string, string | number | boolean | undefined>;
  } = {},
): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (init.body !== undefined) headers['Content-Type'] = 'application/json';

  if (init.auth !== false) {
    const tok = await getToken();
    if (tok) headers['Authorization'] = `Bearer ${tok}`;
  }

  const qs = init.query
    ? '?' +
      Object.entries(init.query)
        .filter(([, v]) => v !== undefined && v !== null && v !== '')
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
        .join('&')
    : '';

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
    } catch { /* keep default */ }
    throw new Error(msg);
  }
  const body = (await res.json()) as ApiResponse<T>;
  if (body.code !== 0 && body.code !== 200) {
    throw new Error(body.message || `API code ${body.code}`);
  }
  return body.data;
}

export const api = {
  login(email: string, password: string) {
    return request<AuthResponse>('/auth/login', {
      method: 'POST',
      body: { email, password },
      auth: false,
    });
  },

  me() {
    return request<User>('/users/me');
  },

  listWallpapers(params: { limit?: number; cursor?: number; sort?: string } = {}) {
    return request<ListResponse<Wallpaper>>('/wallpapers', { query: params });
  },
};
