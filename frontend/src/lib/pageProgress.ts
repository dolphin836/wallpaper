import NProgress from 'nprogress';

// Top-edge page-load bar. Driven by two signals:
//  - route changes start the bar immediately (perceived responsiveness)
//  - an in-flight axios request counter keeps it alive until the page's
//    last data request settles, with a short linger so request waves
//    (categories → wallpapers → engagements) read as one load.
NProgress.configure({
  showSpinner: false,
  trickleSpeed: 130,
  minimum: 0.08,
});

// Background chatter that should never hold the bar open: analytics
// beacons fire on every navigation and would otherwise flash the bar on
// fully-cached pages.
const SILENT_PATHS = ['/events'];

function isSilent(url?: string): boolean {
  if (!url) return false;
  return SILENT_PATHS.some((p) => url.includes(p));
}

let active = 0;
let doneTimer: number | undefined;
// After a route change with no data requests (fully cached page), close
// the bar on this fallback instead of leaving it stuck mid-flight.
let idleTimer: number | undefined;

const LINGER_MS = 200;
const IDLE_MS = 400;

function scheduleDone() {
  window.clearTimeout(doneTimer);
  doneTimer = window.setTimeout(() => {
    if (active === 0) NProgress.done();
  }, LINGER_MS);
}

export function requestStarted(url?: string) {
  if (isSilent(url)) return;
  active++;
  window.clearTimeout(doneTimer);
  window.clearTimeout(idleTimer);
  NProgress.start();
}

export function requestSettled(url?: string) {
  if (isSilent(url)) return;
  active = Math.max(0, active - 1);
  if (active === 0) scheduleDone();
}

export function routeChanged() {
  NProgress.start();
  window.clearTimeout(idleTimer);
  idleTimer = window.setTimeout(() => {
    if (active === 0) NProgress.done();
  }, IDLE_MS);
}
