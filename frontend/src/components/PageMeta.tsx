import { useLocation } from 'react-router-dom';

const SITE_NAME = 'Wallpaper Exchange';
const DEFAULT_DESCRIPTION =
  'Wallpaper Exchange is a community-driven platform to discover, share and download high-quality wallpapers for desktop and mobile, including macOS dynamic wallpapers.';

// 1200×630 paper-bg shareable image at /og-default.png. Used whenever a
// page didn't pass its own `image` prop. Without it, shares to Slack /
// Twitter / WeChat would render with no thumbnail at all, which kills
// click-through rates.
const DEFAULT_OG_IMAGE = '/og-default.png';
const DEFAULT_OG_IMAGE_WIDTH = 1200;
const DEFAULT_OG_IMAGE_HEIGHT = 630;

// Compute the absolute origin once. Used to normalize image URLs that
// were passed as site-relative ("/foo.png") into the full https:// form
// — Facebook / Twitter / WeChat OG scrapers all require absolute URLs.
function getOrigin(): string {
  if (typeof window === 'undefined') return '';
  return window.location.origin;
}

// Make sure the value we hand to the OG tag is a full absolute URL.
//   - "https://..." or "http://..."     → unchanged
//   - "//example.com/..."               → prepend the protocol
//   - "/foo.png" or "foo.png"           → prepend origin
function absoluteUrl(input: string | undefined, origin: string): string | undefined {
  if (!input) return undefined;
  if (input.startsWith('http://') || input.startsWith('https://')) return input;
  if (input.startsWith('//')) return 'https:' + input;
  if (input.startsWith('/'))  return origin + input;
  return origin + '/' + input;
}

interface PageMetaProps {
  title?: string;
  description?: string;
  /** Absolute or site-relative URL. Falls back to the default OG image. */
  image?: string;
  /** Defaults to a "Wallpaper Exchange — open graph banner" if not set. */
  imageAlt?: string;
  type?: 'website' | 'article' | 'profile';
  noindex?: boolean;
  jsonLd?: Record<string, unknown> | Record<string, unknown>[];
}

export default function PageMeta({
  title,
  description = DEFAULT_DESCRIPTION,
  image,
  imageAlt,
  type = 'website',
  noindex = false,
  jsonLd,
}: PageMetaProps) {
  const location = useLocation();
  const origin = getOrigin();
  const canonical = origin + location.pathname;

  const fullTitle = title
    ? `${title} — ${SITE_NAME}`
    : `${SITE_NAME} — Discover, Share & Download HD Wallpapers`;

  const usingFallback = !image;
  const resolvedImage = absoluteUrl(image, origin) ?? (origin + DEFAULT_OG_IMAGE);
  const resolvedAlt =
    imageAlt
    ?? (usingFallback ? `${SITE_NAME} — open graph banner` : (title ? `${title} — ${SITE_NAME}` : SITE_NAME));

  return (
    <>
      <title>{fullTitle}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={canonical} />
      {noindex && <meta name="robots" content="noindex, nofollow" />}

      {/* Open Graph */}
      <meta property="og:type" content={type} />
      <meta property="og:site_name" content={SITE_NAME} />
      <meta property="og:title" content={fullTitle} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={canonical} />
      <meta property="og:locale" content="en_US" />
      <meta property="og:image" content={resolvedImage} />
      <meta property="og:image:alt" content={resolvedAlt} />
      {/* Image dimensions only when we know them — the fallback PNG is
          1200×630; user-supplied images don't carry size metadata at
          this layer, so we omit those tags rather than lie about them.
          Facebook/Twitter handle missing-size gracefully. */}
      {usingFallback && <meta property="og:image:width" content={String(DEFAULT_OG_IMAGE_WIDTH)} />}
      {usingFallback && <meta property="og:image:height" content={String(DEFAULT_OG_IMAGE_HEIGHT)} />}

      {/* Twitter Card */}
      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={fullTitle} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content={resolvedImage} />
      <meta name="twitter:image:alt" content={resolvedAlt} />

      {jsonLd && (
        <script type="application/ld+json">{JSON.stringify(jsonLd)}</script>
      )}
    </>
  );
}
