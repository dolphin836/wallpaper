import client from '../api/client';
import { getAnalyticsSessionID } from './analyticsSession';

const LANDING_KEY = 'wpe_landing_path';
const REFERRER_KEY = 'wpe_initial_referrer';
const SOURCE_KEY = 'wpe_initial_source';

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
      session_id: getAnalyticsSessionID(),
      type,
      path: window.location.pathname + window.location.search,
      referrer: document.referrer,
      props: { client: 'web', ...(props ?? {}) },
    })
    .catch(() => {
      // telemetry must never break user flows
    });
}
