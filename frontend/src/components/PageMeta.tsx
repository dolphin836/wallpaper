import { useLocation } from 'react-router-dom';

const SITE_NAME = 'Wallpaper Exchange';
const DEFAULT_DESCRIPTION =
  'Wallpaper Exchange is a community-driven platform to discover, share and download high-quality wallpapers for desktop and mobile, including macOS dynamic wallpapers.';

interface PageMetaProps {
  title?: string;
  description?: string;
  image?: string;
  type?: 'website' | 'article' | 'profile';
  noindex?: boolean;
  jsonLd?: Record<string, unknown> | Record<string, unknown>[];
}

export default function PageMeta({
  title,
  description = DEFAULT_DESCRIPTION,
  image,
  type = 'website',
  noindex = false,
  jsonLd,
}: PageMetaProps) {
  const location = useLocation();
  const fullTitle = title ? `${title} — ${SITE_NAME}` : `${SITE_NAME} — Discover, Share & Download HD Wallpapers`;
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  const canonical = origin + location.pathname;

  return (
    <>
      <title>{fullTitle}</title>
      <meta name="description" content={description} />
      <link rel="canonical" href={canonical} />
      {noindex && <meta name="robots" content="noindex, nofollow" />}

      <meta property="og:type" content={type} />
      <meta property="og:site_name" content={SITE_NAME} />
      <meta property="og:title" content={fullTitle} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={canonical} />
      {image && <meta property="og:image" content={image} />}

      <meta name="twitter:card" content={image ? 'summary_large_image' : 'summary'} />
      <meta name="twitter:title" content={fullTitle} />
      <meta name="twitter:description" content={description} />
      {image && <meta name="twitter:image" content={image} />}

      {jsonLd && (
        <script type="application/ld+json">{JSON.stringify(jsonLd)}</script>
      )}
    </>
  );
}
