import { useState, useEffect } from 'react';

interface Props {
  src?: string | null;
  alt?: string;
  className?: string;
}

/**
 * Image that holds a brand-tinted placeholder until the bytes arrive (and
 * keeps holding it if the URL errors). Pinned to its parent via absolute
 * positioning so the parent's aspect ratio is what controls the slot size —
 * the image itself uses object-cover, so different-aspect-ratio sources are
 * cropped instead of being stretched into deformed rectangles.
 *
 * Drop this anywhere a wallpaper card / collection card needs a thumb and
 * you want to avoid the "white square then suddenly an image" flash.
 */
export default function CoverImage({ src, alt = '', className = '' }: Props) {
  const [loaded, setLoaded] = useState(false);
  const [errored, setErrored] = useState(false);
  useEffect(() => {
    setLoaded(false);
    setErrored(false);
  }, [src]);

  return (
    // Archive-token placeholder. Soft enough to read as a paint swatch
    // instead of a broken image hint, while staying in the paper/ink system.
    <div className={`absolute inset-0 bg-paper-3 overflow-hidden ${className}`}>
      {src && !errored && (
        <img
          src={src}
          alt={alt}
          loading="lazy"
          decoding="async"
          onLoad={() => setLoaded(true)}
          onError={() => setErrored(true)}
          className="w-full h-full object-cover transition-opacity duration-300"
          style={{ opacity: loaded ? 1 : 0 }}
        />
      )}
    </div>
  );
}
