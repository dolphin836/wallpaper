// Cloudflare Pages Function: proxy three classes of requests from the apex
// domain to the backend so the SPA, SEO endpoints, and API all live behind
// the same origin (wallpaperexchange.com).
//
// What we proxy
//   /api/*         → ${API_ORIGIN}/api/*
//   /sitemap.xml   → ${API_ORIGIN}/sitemap.xml
//   /robots.txt    → ${API_ORIGIN}/robots.txt
//
// Why API_ORIGIN = wallpaper.haibing.site, not api.wallpaperexchange.com?
//   api.wallpaperexchange.com is in the same Cloudflare zone as the apex.
//   When a Pages Function fetches a hostname inside its own zone, CF routes
//   the request through its internal proxy fabric and applies the zone's
//   SSL/TLS settings end-to-end — which broke with a 525 "SSL handshake
//   failed" against our origin. wallpaper.haibing.site points at the same
//   server but is hosted on Aliyun DNS, so CF can't recognize it as
//   in-zone and the fetch goes straight out over the public internet,
//   bypassing all that. Same bytes, different routing path.
//
// Everything else (assets, SPA routes) passes through to the static build
// via context.next().

const API_ORIGIN = 'https://wallpaper.haibing.site';

export const onRequest: PagesFunction = async (context) => {
  const url = new URL(context.request.url);
  const path = url.pathname;

  const shouldProxy =
    path.startsWith('/api/') ||
    path === '/sitemap.xml' ||
    path === '/robots.txt';

  if (!shouldProxy) {
    return context.next();
  }

  const target = API_ORIGIN + path + url.search;

  // Preserve method, body, and most headers. We intentionally do NOT forward
  // Host (the backend reads r.Host to build sitemap URLs and seeing the api
  // subdomain there is fine — backend's baseURL() strips the api. prefix).
  // CF auto-adds CF-Connecting-IP downstream so the backend rate limiter
  // still sees real client IPs.
  const headers = new Headers(context.request.headers);
  headers.delete('host');

  const init: RequestInit = {
    method: context.request.method,
    headers,
    body: ['GET', 'HEAD'].includes(context.request.method)
      ? undefined
      : context.request.body,
    redirect: 'manual',
  };

  const upstream = await fetch(target, init);

  // Surface a small debug breadcrumb so it's obvious in DevTools which
  // requests went through the proxy vs straight to the static SPA.
  const respHeaders = new Headers(upstream.headers);
  respHeaders.set('x-proxied-by', 'pages-fn');

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
};
