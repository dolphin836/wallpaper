import client from '../api/client';

const SESSION_KEY = 'wpe_session_id';
const STAMP_KEY = 'wpe_session_stamp';
const LANDING_KEY = 'wpe_landing_path';
const REFERRER_KEY = 'wpe_initial_referrer';
const SOURCE_KEY = 'wpe_initial_source';
const SESSION_TTL_MS = 30 * 60 * 1000; // refresh window — 30 min idle ends the session

function newID(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID();
  }
  return 'sid-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
}

function getSessionID(): string {
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

export function track(type: string, props?: Record<string, unknown>) {
  try {
    if (!sessionStorage.getItem(LANDING_KEY)) {
      sessionStorage.setItem(LANDING_KEY, window.location.pathname + window.location.search);
    }
    if (!sessionStorage.getItem(REFERRER_KEY)) {
      sessionStorage.setItem(REFERRER_KEY, document.referrer || '');
    }
    const params = new URLSearchParams(window.location.search);
    const source = params.get('utm_source') || params.get('source') || params.get('ref') || '';
    if (source && !sessionStorage.getItem(SOURCE_KEY)) {
      sessionStorage.setItem(SOURCE_KEY, source);
    }
  } catch {
    // Attribution is best-effort; analytics itself can still proceed.
  }

  client
    .post('/events', {
      session_id: getSessionID(),
      type,
      path: window.location.pathname + window.location.search,
      referrer: document.referrer,
      props: { client: 'web', ...(props ?? {}) },
    })
    .catch(() => {
      // telemetry must never break user flows
    });
}
