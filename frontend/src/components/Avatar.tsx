import { useState, useEffect } from 'react';
import { AiOutlineUser } from 'react-icons/ai';

interface Props {
  src?: string | null;
  name?: string;            // optional — when set, used to render an initial in the fallback
  size?: number;            // pixels, square
  className?: string;       // extra classes for the outer wrapper
  alt?: string;
}

/**
 * Avatar with a graceful fallback path:
 *
 *   1. While the `src` is still loading (or after onError), we render a
 *      neutral placeholder — either the first letter of `name` if provided,
 *      or a generic user icon. This avoids the broken-image flash and the
 *      layout-shift you get from waiting for an HTTP round-trip on every
 *      list page.
 *   2. The actual <img> is layered on top and fades in via opacity once it
 *      decodes successfully, so the swap is smooth instead of janky.
 *   3. On error (404, CORS, malformed URL) we drop the <img> entirely and
 *      keep the placeholder visible.
 *
 * Use this for every list/grid of users instead of inlining the ternary
 * `avatar_url ? <img> : <fallback>`.
 */
export default function Avatar({ src, name, size = 48, className = '', alt = '' }: Props) {
  const [loaded, setLoaded] = useState(false);
  const [errored, setErrored] = useState(false);

  // Reset state when the src changes (e.g. user paginates, list reorders).
  useEffect(() => {
    setLoaded(false);
    setErrored(false);
  }, [src]);

  const initial = (name || '').trim().charAt(0).toUpperCase();
  const showImg = src && !errored;

  return (
    <div
      className={`relative inline-flex items-center justify-center overflow-hidden rounded-full bg-ws-purple-light dark:bg-ws-dark-active text-ws-purple dark:text-purple-400 ${className}`}
      style={{ width: size, height: size }}
    >
      {/* Placeholder always rendered behind the <img> so it shows during
          the network fetch and stays put if the image errors. */}
      {initial ? (
        <span className="font-semibold" style={{ fontSize: Math.max(12, size * 0.4) }}>{initial}</span>
      ) : (
        <AiOutlineUser size={Math.max(14, size * 0.55)} />
      )}
      {showImg && (
        <img
          src={src!}
          alt={alt}
          loading="lazy"
          decoding="async"
          onLoad={() => setLoaded(true)}
          onError={() => setErrored(true)}
          className="absolute inset-0 w-full h-full object-cover transition-opacity duration-200"
          style={{ opacity: loaded ? 1 : 0 }}
        />
      )}
    </div>
  );
}
