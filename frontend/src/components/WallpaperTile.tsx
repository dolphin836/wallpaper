import { useCallback, useState, useEffect, useRef } from 'react';
import type { CSSProperties } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import {
  AiOutlineHeart, AiFillHeart,
  AiOutlineStar, AiFillStar,
  AiOutlineDownload, AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import type { Wallpaper } from '../types';
import { useWallpaperActions } from '../hooks/useWallpaperActions';

/**
 * Resolution chip — small mono pill in the top-left of a tile.
 * Shared between hero + tile so the visual vocabulary stays consistent.
 */
export function ResChip({ wallpaper }: { wallpaper: Wallpaper }) {
  const px = Math.max(wallpaper.width || 0, wallpaper.height || 0);
  let label = '';
  if (px >= 7680) label = '8K';
  else if (px >= 3840) label = '4K';
  else if (px >= 2560) label = '2K';
  else if (px >= 1920) label = '1080P';
  else if (px >= 1280) label = '720P';
  if (!label) return null;
  return <span className="h3-res-chip">{label}</span>;
}

type Variant = 'weekly' | 'ai' | 'video';

interface Props {
  w: Wallpaper;
  variant: Variant;
  onHover?: (palette: string | undefined, dominant?: string) => void;
}

/**
 * Editorial home/weekly tile. 4:5 (weekly) / 1:1 (ai with holographic
 * foil) / 16:9 (video with hover-autoplay clip). Same chrome as the
 * home-page tiles, with the discover-style action rail (favorite /
 * like / download) revealed on hover. Click opens the wallpaper
 * detail as a modal overlay (preserving the page underneath) via
 * react-router's location.state.background pattern — same UX as the
 * discover salon tiles.
 */
export default function WallpaperTile({ w, variant, onHover }: Props) {
  const { t } = useTranslation('browse');
  const location = useLocation();
  const [loadedSrc, setLoadedSrc] = useState('');
  const [highLoadedSrc, setHighLoadedSrc] = useState('');
  const [highFailedSrc, setHighFailedSrc] = useState('');
  const [playing, setPlaying] = useState(false);
  const vidRef = useRef<HTMLVideoElement | null>(null);
  useEffect(() => {
    if (!playing) return;
    vidRef.current?.play().catch(() => { /* autoplay blocked */ });
  }, [playing]);

  const acts = useWallpaperActions(w);
  const lowResSrc = w.thumb_url || '';
  const highResSrc = w.preview_url || w.thumb_url || '';
  const hasHighResLayer = Boolean(lowResSrc && highResSrc && highResSrc !== lowResSrc);
  const baseSrc = lowResSrc || highResSrc;
  const loaded = Boolean(baseSrc && loadedSrc === baseSrc);
  const highLoaded = Boolean(highResSrc && highLoadedSrc === highResSrc);
  const highFailed = Boolean(highResSrc && highFailedSrc === highResSrc);
  const imageReady = hasHighResLayer ? highLoaded || (highFailed && loaded) : loaded;

  const syncBaseImageRef = useCallback((node: HTMLImageElement | null) => {
    // Cached images can finish before React wires the onLoad handler.
    // Record the current src from the ref so the opacity class is never
    // stranded off after a hard refresh or browser-cache hit.
    if (node?.complete) setLoadedSrc(baseSrc);
  }, [baseSrc]);

  const syncHighImageRef = useCallback((node: HTMLImageElement | null) => {
    if (!node?.complete) return;
    if (node.naturalWidth > 0) setHighLoadedSrc(highResSrc);
    else setHighFailedSrc(highResSrc);
  }, [highResSrc]);

  const handleEnter = () => {
    onHover?.(w.color_palette, w.dominant_color);
    if (variant === 'video' && w.preview_video_url) setPlaying(true);
  };
  const handleLeave = () => {
    onHover?.(undefined);
    if (variant === 'video' && w.preview_video_url) setPlaying(false);
  };

  // Wrap action handlers to stop the click from bubbling into the
  // outer Link (which would navigate to the detail modal).
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };

  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      className={`h3-tile h3-${variant}${playing ? ' h3-playing' : ''}`}
      onMouseEnter={handleEnter}
      onMouseLeave={handleLeave}
      style={{ backgroundColor: w.dominant_color || undefined }}
    >
      {baseSrc && (
        <img
          ref={syncBaseImageRef}
          src={baseSrc}
          alt={w.title || t('tile.wallpaperAlt', { id: w.id })}
          loading="lazy"
          decoding="async"
          className={`h3-progressive-img ${loaded ? 'h3-loaded' : ''}`}
          onLoad={() => setLoadedSrc(baseSrc)}
          onError={() => setLoadedSrc(baseSrc)}
          style={{
            backgroundColor: w.dominant_color || undefined,
            filter: hasHighResLayer && !highLoaded && !highFailed ? 'blur(12px)' : undefined,
            transform: hasHighResLayer && !highLoaded && !highFailed ? 'scale(1.06)' : undefined,
          }}
        />
      )}
      {hasHighResLayer && !highFailed && (
        <img
          ref={syncHighImageRef}
          src={highResSrc}
          alt=""
          aria-hidden
          loading="lazy"
          decoding="async"
          className={`h3-progressive-img ${highLoaded ? 'h3-loaded' : ''}`}
          onLoad={() => setHighLoadedSrc(highResSrc)}
          onError={() => setHighFailedSrc(highResSrc)}
        />
      )}
      {highResSrc && !imageReady && <span className="card-loading-beam" aria-hidden />}
      {variant === 'ai' && <span className="h3-foil" aria-hidden />}
      {variant === 'video' && w.preview_video_url && playing && (
        <video
          ref={vidRef}
          src={w.preview_video_url}
          muted
          loop
          playsInline
          preload="none"
        />
      )}
      {variant === 'video' && (
        <div className="h3-play">
          <svg viewBox="0 0 24 24" aria-hidden><polygon points="6,4 6,20 20,12" /></svg>
        </div>
      )}
      <ResChip wallpaper={w} />

      {/* Hover-revealed action rail — favorite / like / download.
          Same chrome as the salon variant; CSS rule (.h3-tile:hover
          .tile-actions) wakes it up on hover, so no JS visibility
          state needed here. */}
      <div className="tile-actions">
        <button
          type="button"
          onClick={(e) => stop(e, acts.handleFavorite)}
          disabled={acts.favLoading}
          className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
          title={acts.favorited ? t('actions.unfavorite') : t('actions.favorite')}
        >
          {acts.favLoading
            ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
            : acts.favorited
              ? <AiFillStar size={15} />
              : <AiOutlineStar size={15} />}
        </button>
        <button
          type="button"
          onClick={(e) => stop(e, acts.handleLike)}
          disabled={acts.likeLoading}
          className={`t-act ${acts.liked ? 'is-liked' : ''}`}
          title={acts.liked ? t('actions.unlike') : t('actions.like')}
        >
          {acts.likeLoading
            ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
            : acts.liked
              ? <AiFillHeart size={15} />
              : <AiOutlineHeart size={15} />}
        </button>
        {acts.canDownload && (
          <button
            type="button"
            onClick={(e) => stop(e, acts.handleDownload)}
            disabled={acts.downloading}
            className={`t-act ${acts.downloaded ? 'is-downloaded' : ''} ${acts.downloading ? 'is-downloading' : ''}`}
            title={acts.downloadTitle}
            style={{ ['--download-progress' as string]: acts.downloadProgress ?? 0.08 } as CSSProperties}
          >
            {acts.downloading
              ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
              : acts.downloaded
                ? <AiOutlineCheckCircle size={15} />
                : <AiOutlineDownload size={15} />}
          </button>
        )}
      </div>
    </Link>
  );
}
