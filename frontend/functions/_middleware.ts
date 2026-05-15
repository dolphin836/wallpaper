// Cloudflare Pages Function: proxy three classes of requests from the apex
// domain to the backend so the SPA, SEO endpoints, and API all live behind
// the same origin (wallpaperexchange.com).
//
// Why a Function instead of _redirects?
//   `_redirects` with status 200 (rewrite) is only reliable for same-origin
//   destinations on CF Pages. Cross-origin rewrites are documented to work
//   but in practice fall through to the SPA fallback for many setups,
//   which is exactly what we observed for /api/*, /sitemap.xml, /robots.txt.
//   A Functions middleware runs deterministically on every request and lets
//   us forward headers cleanly.
//
// What we proxy
//   /api/*         → https://api.wallpaperexchange.com/api/*
//   /sitemap.xml   → https://api.wallpaperexchange.com/sitemap.xml
//   /robots.txt    → https://api.wallpaperexchange.com/robots.txt
//
// Everything else (assets, SPA routes) passes through to the static build
// via context.next().

const API_ORIGIN = 'https://api.wallpaperexchange.com';

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
