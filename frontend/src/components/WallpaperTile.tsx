import { useState, useEffect, useRef } from 'react';
import type { CSSProperties } from 'react';
import { Link, useLocation } from 'react-router-dom';
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
  const location = useLocation();
  const [loaded, setLoaded] = useState(false);
  const [playing, setPlaying] = useState(false);
  const vidRef = useRef<HTMLVideoElement | null>(null);
  useEffect(() => {
    if (!playing) return;
    vidRef.current?.play().catch(() => { /* autoplay blocked */ });
  }, [playing]);

  const acts = useWallpaperActions(w);

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
    >
      <img
        src={w.preview_url || w.thumb_url}
        alt={w.title || `Wallpaper ${w.id}`}
        loading="lazy"
        className={loaded ? 'h3-loaded' : ''}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
        style={{ backgroundColor: w.dominant_color || undefined }}
      />
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
          title={acts.favorited ? 'Unfavorite' : 'Favorite'}
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
          title={acts.liked ? 'Unlike' : 'Like'}
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
