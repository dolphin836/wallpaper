// Auth token storage. localStorage is fine here — Tauri's WebView2
// stores per-app, isolated from any user browser profile, and the
// app folder is %LOCALAPPDATA%\<bundle id> on Windows. JWT TTL is 30
// days server-side (we bumped it earlier), so the user signs in once
// and stays signed in for the lifetime of an install.

const KEY = 'wpe.token';

export async function getToken(): Promise<string | null> {
  return localStorage.getItem(KEY);
}

export async function setToken(token: string): Promise<void> {
  localStorage.setItem(KEY, token);
}

export async function clearToken(): Promise<void> {
  localStorage.removeItem(KEY);
}
