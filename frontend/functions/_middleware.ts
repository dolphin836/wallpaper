// Cloudflare Pages Function: proxy a handful of paths from the apex domain
// to the backend so the SPA, SEO endpoints, and API all live behind the
// same origin (wallpaperexchange.com).
//
// What we proxy
//   /api/*               → ${API_ORIGIN}/api/*
//   /storage/*           → ${STORAGE_ORIGIN}/*
//   /__pinterest/v5/*    → https://api.pinterest.com/v5/* (API egress proxy)
//   /__reddit/oauth/*     → https://oauth.reddit.com/* (API egress proxy)
//   /__reddit/token       → https://www.reddit.com/api/v1/access_token
//   /sitemap.xml         → ${API_ORIGIN}/sitemap.xml
//   /robots.txt          → ${API_ORIGIN}/robots.txt
//   /feed.xml            → ${API_ORIGIN}/feed.xml          (RSS)
//   /{indexnowKey}.txt   → ${API_ORIGIN}/{indexnowKey}.txt (Bing/Yandex verification)
//
// Both origins are Cloudflare Tunnel routes in the wallpaperexchange.com
// zone. The tunnel connects outbound from the production Docker network, so
// Pages never needs to reach the server IP or share another product's domain.
//
// Everything else (assets, SPA routes) passes through to the static build
// via context.next().

const API_ORIGIN = 'https://api.wallpaperexchange.com';
const STORAGE_ORIGIN = 'https://storage.wallpaperexchange.com';

// User agents that benefit from a server-rendered HTML response instead
// of the SPA. Two reasons one might be on this list:
//   - Doesn't run JS at all (Facebook/Twitter/WhatsApp scrapers)
//   - Runs JS but slower than first-paint HTML (Googlebot, Bingbot)
// Either way we serve the same prerendered detail page the origin nginx
// would serve in identical conditions, so there's no cloaking divergence.
const BOT_UA_RE =
  /(facebookexternalhit|Facebot|Twitterbot|WhatsApp|TelegramBot|LinkedInBot|Discordbot|Slackbot|Pinterest|Applebot|WeChat|MicroMessenger|Weibo|Bytespider|Bingbot|Googlebot|Google-InspectionTool|AdsBot-Google|DuckDuckBot|YandexBot|Baiduspider)/i;

const WALLPAPER_DETAIL_RE = /^\/wallpaper\/([^/]+)\/?$/;
const PINTEREST_PROXY_RE = /^\/__pinterest\/v5(\/.*)?$/;
const REDDIT_OAUTH_PROXY_RE = /^\/__reddit\/oauth(\/.*)?$/;
const REDDIT_TOKEN_PROXY_RE = /^\/__reddit\/token$/;

async function proxyPinterestAPI(context: EventContext<unknown, string, unknown>, url: URL) {
  const upstreamPath = url.pathname.replace(/^\/__pinterest/, '');
  const allowed =
    upstreamPath === '/v5/oauth/token' ||
    upstreamPath === '/v5/user_account' ||
    upstreamPath === '/v5/boards' ||
    upstreamPath === '/v5/pins';

  if (!allowed || !['GET', 'POST'].includes(context.request.method)) {
    return new Response('Not found', { status: 404 });
  }

  const headers = new Headers(context.request.headers);
  headers.delete('host');

  const upstream = await fetch('https://api.pinterest.com' + upstreamPath + url.search, {
    method: context.request.method,
    headers,
    body: context.request.method === 'GET' ? undefined : context.request.body,
    redirect: 'manual',
  });

  const respHeaders = new Headers(upstream.headers);
  respHeaders.set('x-proxied-by', 'pages-pinterest-proxy');
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
}

async function proxyRedditAPI(context: EventContext<unknown, string, unknown>, url: URL) {
  let upstreamURL = '';
  let allowed = false;

  if (REDDIT_TOKEN_PROXY_RE.test(url.pathname)) {
    allowed = context.request.method === 'POST';
    upstreamURL = 'https://www.reddit.com/api/v1/access_token';
  } else {
    const upstreamPath = url.pathname.replace(/^\/__reddit\/oauth/, '');
    allowed =
      (upstreamPath === '/api/v1/me' && context.request.method === 'GET') ||
      (upstreamPath === '/api/submit' && context.request.method === 'POST');
    upstreamURL = 'https://oauth.reddit.com' + upstreamPath + url.search;
  }

  if (!allowed) {
    return new Response('Not found', { status: 404 });
  }

  const headers = new Headers(context.request.headers);
  headers.delete('host');

  const upstream = await fetch(upstreamURL, {
    method: context.request.method,
    headers,
    body: context.request.method === 'GET' ? undefined : context.request.body,
    redirect: 'manual',
  });

  const respHeaders = new Headers(upstream.headers);
  respHeaders.set('x-proxied-by', 'pages-reddit-proxy');
  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
}

export const onRequest: PagesFunction = async (context) => {
  const url = new URL(context.request.url);
  const path = url.pathname;

  if (PINTEREST_PROXY_RE.test(path)) {
    return proxyPinterestAPI(context, url);
  }
  if (REDDIT_OAUTH_PROXY_RE.test(path) || REDDIT_TOKEN_PROXY_RE.test(path)) {
    return proxyRedditAPI(context, url);
  }

  // IndexNow key file: 16+ hex chars then ".txt" at the root. We pattern-
  // match instead of hardcoding the key so we don't have to redeploy the
  // worker every time the key rotates.
  const isIndexNowKeyFile = /^\/[a-f0-9]{16,128}\.txt$/i.test(path);

  // Bot prerender path: a recognised crawler asking for /wallpaper/{slug}
  // gets served the backend's __og prerender (rich title/desc/JSON-LD)
  // instead of the empty SPA index.html.
  const ua = context.request.headers.get('user-agent') || '';
  const wpMatch = path.match(WALLPAPER_DETAIL_RE);
  const isBotDetail = wpMatch && BOT_UA_RE.test(ua);

  const shouldProxy =
    path.startsWith('/api/') ||
    path.startsWith('/storage/') ||
    path === '/sitemap.xml' ||
    path === '/robots.txt' ||
    path === '/feed.xml' ||
    isIndexNowKeyFile ||
    isBotDetail;

  if (!shouldProxy) {
    return context.next();
  }

  const isStorage = path.startsWith('/storage/');
  const proxyPath = isBotDetail
    ? `/__og/wallpaper/${wpMatch[1]}`
    : path;
  const target = isStorage
    ? STORAGE_ORIGIN + path.slice('/storage'.length) + url.search
    : API_ORIGIN + proxyPath + url.search;

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
  respHeaders.set('x-proxied-by', isStorage ? 'pages-storage-proxy' : 'pages-fn');
  if (isStorage && upstream.ok) {
    // Object keys are immutable UUID/versioned paths. Let both browsers and
    // Cloudflare keep them so a gallery refresh does not fan out dozens of
    // requests to the single MinIO origin again.
    respHeaders.set('cache-control', 'public, max-age=31536000, immutable');
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: respHeaders,
  });
};
