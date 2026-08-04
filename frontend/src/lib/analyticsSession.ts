const SESSION_KEY = 'wpe_session_id';
const STAMP_KEY = 'wpe_session_stamp';
const SESSION_TTL_MS = 30 * 60 * 1000;

function newID(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return 'sid-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
}

export function getAnalyticsSessionID(): string {
  try {
    const now = Date.now();
    const last = parseInt(localStorage.getItem(STAMP_KEY) || '0', 10);
    const existing = localStorage.getItem(SESSION_KEY);
    if (existing && last && now - last < SESSION_TTL_MS) {
      localStorage.setItem(STAMP_KEY, String(now));
      return existing;
    }
    const fresh = newID();
    localStorage.setItem(SESSION_KEY, fresh);
    localStorage.setItem(STAMP_KEY, String(now));
    return fresh;
  } catch {
    return 'no-storage';
  }
}
