import { useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import {
  AiOutlineHeart,
  AiFillHeart,
  AiOutlineStar,
  AiFillStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
  AiOutlineWarning,
} from 'react-icons/ai';
import type { Wallpaper } from '../types';
import { useWallpaperActions } from '../hooks/useWallpaperActions';

const STATUS_PROCESSING = 0;
const STATUS_PUBLISHED = 1;
const STATUS_FAILED = 2;
const STATUS_PENDING_REVIEW = 5;
const STATUS_REJECTED = 6;

interface Props {
  wallpaper: Wallpaper;
  showStatus?: boolean;
  fixedAspect?: boolean;
  fillHeight?: boolean;
  style?: CSSProperties;
  animDelay?: number;
  disableModal?: boolean;
  /** Visual variant. 'salon' = editorial Discover tile (minimal chips +
   *  hover action rail); undefined = legacy purple card used everywhere
   *  else. Keep both around until other pages are migrated. */
  layout?: 'salon';
  /** Hide the hover action rail (like / favorite / download) entirely.
   *  Used in places where the card is too small for them to be useful or
   *  the surrounding layout already provides those actions — e.g. the
   *  "More like this" strip on the detail page. */
  hideActions?: boolean;
}

export default function WallpaperCard({ wallpaper, showStatus, fixedAspect, fillHeight, style, animDelay = 0, disableModal = false, layout, hideActions = false }: Props) {
  const { t } = useTranslation('browse');
  // Two-stage progressive load: thumb (~30 KB, displayed immediately with a
  // small blur) → preview_url (~250 KB watermarked 1600px, fades in once
  // loaded). Loading the 1600px preview on the home feed means the browser
  // HTTP cache already has it when the user opens a detail page, so detail
  // navigation feels instant — that's the trade-off vs a smaller dedicated
  // card-sized variant.
  const lowResSrc = wallpaper.thumb_url;
  const highResSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const [highLoaded, setHighLoaded] = useState(false);
  const location = useLocation();
  const acts = useWallpaperActions(wallpaper);

  const hasImage = lowResSrc.length > 0 || highResSrc.length > 0;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;
  // Video wallpapers carry file_type starting with "video/" after the
  // transcode worker normalizes to mp4. thumb_url / preview_url point
  // at the poster.webp the worker also generated; original_url is the
  // H.264 file we feed to <video>.
  const isVideo = (wallpaper.file_type || '').startsWith('video/');

  const aspectRatio = wallpaper.width > 0 && wallpaper.height > 0
    ? wallpaper.width / wallpaper.height
    : 4 / 3;

  const resLabel = (() => {
    const px = Math.max(wallpaper.width, wallpaper.height);
    if (px >= 7680) return '8K';
    if (px >= 3840) return '4K';
    if (px >= 2560) return '2K';
    if (px >= 1920) return '1080P';
    if (px >= 1280) return '720P';
    return '';
  })();

  const statusChip = (() => {
    if (!showStatus || wallpaper.status === STATUS_PUBLISHED) return null;
    if (isProcessing) return { label: t('chip.processing'), tone: 'is-processing' };
    if (isFailed) return { label: t('chip.failed'), tone: 'is-failed' };
    if (wallpaper.status === STATUS_PENDING_REVIEW) return { label: t('chip.review'), tone: 'is-review' };
    if (wallpaper.status === STATUS_REJECTED) return { label: t('chip.rejected'), tone: 'is-failed' };
    return { label: t('chip.statusN', { num: wallpaper.status }), tone: 'is-muted' };
  })();

  const handleAction = (e: React.MouseEvent, action: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    action();
  };

  const isPublished = wallpaper.status === STATUS_PUBLISHED;
  const Wrapper = isPublished ? Link : 'div';
  // disableModal omits `background` so the route resolves to the full page
  // instead of the overlay modal. initialWallpaper still hydrates the
  // detail view from this card's data even on a full-page nav.
  //
  // When the card itself sits inside a modal — i.e. the current route
  // already carries a `background` state — we *inherit* that ancestor
  // background and `replace` instead of `push`. Otherwise jumping from
  // one detail card to a similar one would push a new history entry,
  // so closing the modal would only step back one detail at a time
  // instead of returning to the original gallery.
  const existingBg = (location.state as { background?: Location } | null)?.background;
  const insideModal = !!existingBg;
  const wrapperProps = isPublished
    ? {
        to: `/wallpaper/${wallpaper.slug}`,
        state: disableModal
          ? { initialWallpaper: wallpaper }
          : { background: existingBg || location, initialWallpaper: wallpaper },
        ...(insideModal && !disableModal ? { replace: true } : {}),
      }
    : { style: { cursor: 'default' } };

  // ── Salon variant (editorial Discover tile) ─────────────────────────
  // Minimal chrome: top-left resolution + Mac chip only, hover reveals a
  // 3-button rail at bottom-right with persisted selected states for
  // liked/favorited/downloaded. Shares all action handlers + progressive
  // image loading with the legacy card below. Falls back gracefully for
  // unpublished items (skips the action rail).
  if (layout === 'salon') {
    return (
      <Wrapper
        {...(wrapperProps as any)}
        // `block` is essential: when isPublished, Wrapper is <Link> which renders
        // as <a> — that's inline by default, so w-full / h-full are no-ops and
        // the tile collapses to 0×0, hiding the (absolutely-positioned) image.
        className={`tile-cell block relative w-full h-full overflow-hidden animate-fade-in no-underline ${isPublished ? '' : 'cursor-default'}`}
        // data-palette lets parent surfaces (e.g. Discover's liquid mesh)
        // detect which card is hovered via event delegation and tint the
        // page background from this wallpaper's color palette. Harmless
        // on pages that don't read it.
        data-palette={wallpaper.color_palette || ''}
        style={{
          ...style,
          animationDelay: `${animDelay}ms`,
          backgroundColor: wallpaper.dominant_color || 'var(--color-paper-3)',
        }}
      >
        {hasImage ? (
          <>
            {lowResSrc && (
              <img
                src={lowResSrc}
                alt=""
                aria-hidden
                loading="lazy"
                decoding="async"
                onContextMenu={(e) => e.preventDefault()}
                draggable={false}
                className="absolute inset-0 w-full h-full object-cover select-none"
                style={{
                  filter: highLoaded ? 'none' : 'blur(12px)',
                  transform: highLoaded ? 'none' : 'scale(1.06)',
                  transition: 'filter 300ms ease, transform 300ms ease',
                  WebkitUserDrag: 'none',
                } as React.CSSProperties}
              />
            )}
            <img
              src={highResSrc}
              alt=""
              loading="lazy"
              decoding="async"
              onLoad={() => setHighLoaded(true)}
              onContextMenu={(e) => e.preventDefault()}
              draggable={false}
              className={`tile-img absolute inset-0 w-full h-full object-cover select-none ${highLoaded ? 'opacity-100' : 'opacity-0'}`}
              style={{ WebkitUserDrag: 'none', transition: highLoaded ? undefined : 'opacity 300ms ease' } as React.CSSProperties}
            />
            {!highLoaded && <span className="card-loading-beam" aria-hidden />}
            <div
              className="tile-gradient absolute inset-0 opacity-0 pointer-events-none"
              style={{
                background: 'linear-gradient(180deg, rgba(0,0,0,0.18) 0%, rgba(0,0,0,0) 30%, rgba(0,0,0,0) 60%, rgba(0,0,0,0.28) 100%)',
              }}
            />
            {isVideo && wallpaper.original_url && (
              <VideoHoverOverlay src={wallpaper.original_url} />
            )}
          </>
        ) : (
          <div className="absolute inset-0 flex items-center justify-center">
            {isProcessing ? (
              <AiOutlineLoading3Quarters size={28} className="text-white/70 animate-spin" />
            ) : (
              <AiOutlineWarning size={28} className="text-white/70" />
            )}
          </div>
        )}

        {/* Top-left chips. Editorial pill family — see .tile-chip in
            index.css; the AI variant keeps a violet wash so the
            "synthetic" label reads at a glance, everything else is the
            neutral light/dark pill shared with home-page tiles. */}
        <div className="absolute top-2.5 left-2.5 z-[2] flex gap-1 flex-wrap max-w-[calc(100%-20px)]">
          {resLabel && <span className="tile-chip">{resLabel}</span>}
          {(isVideo || wallpaper.is_dynamic) && (
            <span className="tile-chip">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
              {t('chip.live')}
            </span>
          )}
          {wallpaper.is_ai_generated && (
            <span className="tile-chip is-ai">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z"/></svg>
              {t('chip.ai')}
            </span>
          )}
          {statusChip && (
            <span
              className={`tile-chip ${statusChip.tone}`}
              title={wallpaper.status === STATUS_REJECTED && wallpaper.rejection_reason ? wallpaper.rejection_reason : undefined}
            >
              {statusChip.label}
            </span>
          )}
        </div>

        {/* Hover action rail. Order: favorite → like → download.
            CSS handles fade-in via .tile-cell:hover .tile-actions. */}
        {isPublished && !hideActions && (
          <div className="tile-actions">
            <button
              onClick={(e) => handleAction(e, acts.handleFavorite)}
              disabled={acts.favLoading}
              className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
              title={acts.favorited ? t('actions.unfavorite') : t('actions.favorite')}
            >
              {acts.favLoading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : acts.favorited ? <AiFillStar size={15} /> : <AiOutlineStar size={15} />}
            </button>
            <button
              onClick={(e) => handleAction(e, acts.handleLike)}
              disabled={acts.likeLoading}
              className={`t-act ${acts.liked ? 'is-liked' : ''}`}
              title={acts.liked ? t('actions.unlike') : t('actions.like')}
            >
              {acts.likeLoading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : acts.liked ? <AiFillHeart size={15} /> : <AiOutlineHeart size={15} />}
            </button>
            {acts.canDownload && (
              <button
                onClick={(e) => handleAction(e, acts.handleDownload)}
                disabled={acts.downloading}
                className={`t-act ${acts.downloaded ? 'is-downloaded' : ''} ${acts.downloading ? 'is-downloading' : ''}`}
                title={acts.downloadTitle}
                style={{ ['--download-progress' as string]: acts.downloadProgress ?? 0.08 } as CSSProperties}
              >
                {acts.downloading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : acts.downloaded ? <AiOutlineCheckCircle size={15} /> : <AiOutlineDownload size={15} />}
              </button>
            )}
          </div>
        )}
      </Wrapper>
    );
  }

  return (
    <Wrapper
      {...(wrapperProps as any)}
      className={`wp-card group block relative overflow-hidden transition-all duration-300 no-underline ${fillHeight ? 'h-full' : ''} animate-fade-in ${isPublished ? '' : 'cursor-default'}`}
      style={{
        ...style,
        animationDelay: `${animDelay}ms`,
        backgroundColor: wallpaper.dominant_color || 'var(--color-paper-3)',
        ...(isPublished ? {} : { cursor: 'default' }),
      }}
    >
      <div
        className={`relative overflow-hidden ${fillHeight ? 'h-full' : ''} ${fixedAspect ? 'aspect-[3/2]' : ''}`}
        style={{
          backgroundColor: wallpaper.dominant_color || '#e5e7eb',
          aspectRatio: !fixedAspect && !fillHeight ? aspectRatio : undefined,
        }}
      >
        {hasImage && !highLoaded && <span className="card-loading-beam" aria-hidden />}

        {hasImage ? (
          <>
            {/* Low-res thumb sits underneath; slightly blurred + scaled to hide
                JPEG artifacts from being upscaled past its native size. Visible
                until the high-res card image finishes loading. */}
            {lowResSrc && (
              <img
                src={lowResSrc}
                alt=""
                aria-hidden
                loading="lazy"
                decoding="async"
                onContextMenu={(e) => e.preventDefault()}
                draggable={false}
                className="absolute inset-0 w-full h-full object-cover select-none"
                style={{
                  filter: highLoaded ? 'none' : 'blur(12px)',
                  transform: highLoaded ? 'none' : 'scale(1.06)',
                  transition: 'filter 300ms ease, transform 300ms ease',
                  WebkitUserDrag: 'none',
                } as React.CSSProperties}
              />
            )}
            {/* High-res preview fades in once loaded, replacing the blurred thumb.
                Uses transition-all (not transition-opacity) so the group-hover:scale-105
                transform animates smoothly over 500ms — opacity-only transition was
                causing the scale to snap instantly on hover. */}
            <img
              src={highResSrc}
              alt=""
              loading="lazy"
              decoding="async"
              onLoad={() => setHighLoaded(true)}
              onContextMenu={(e) => e.preventDefault()}
              draggable={false}
              className={`absolute inset-0 w-full h-full object-cover transition-all duration-500 group-hover:scale-105 select-none ${highLoaded ? 'opacity-100' : 'opacity-0'}`}
              style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
            />
            <div className="absolute inset-0 z-[1] bg-black/0 group-hover:bg-black/10 transition-colors duration-300" onContextMenu={(e) => e.preventDefault()} />
          </>
        ) : (
          <div className={`w-full flex items-center justify-center ${fixedAspect || fillHeight ? 'h-full' : 'aspect-[4/3]'}`}>
            {isProcessing ? (
              <AiOutlineLoading3Quarters size={32} className="text-white/70 animate-spin" />
            ) : (
              <AiOutlineWarning size={32} className="text-white/70" />
            )}
          </div>
        )}

        {/* Tags: top-left */}
        <div className="absolute top-2.5 left-2.5 z-[3] flex items-center gap-1.5 flex-wrap max-w-[calc(100%-20px)]">
          {resLabel && (
            <span className="tile-chip">
              {resLabel}
            </span>
          )}
          {(isVideo || wallpaper.is_dynamic) && (
            <span className="tile-chip">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
              {t('chip.live')}
            </span>
          )}
          {wallpaper.is_ai_generated && (
            <span className="tile-chip is-ai">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z"/></svg>
              {t('chip.ai')}
            </span>
          )}
          {statusChip && (
            <span
              className={`tile-chip ${statusChip.tone}`}
              title={wallpaper.status === STATUS_REJECTED && wallpaper.rejection_reason ? wallpaper.rejection_reason : undefined}
            >
              {statusChip.label}
            </span>
          )}
        </div>

        {/* Action buttons — appear on hover, only for published wallpapers */}
        {isPublished && !hideActions && <div className="tile-actions">
            <button
              onClick={(e) => handleAction(e, acts.handleFavorite)}
              disabled={acts.favLoading}
              className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
              title={acts.favorited ? t('actions.unfavorite') : t('actions.favorite')}
            >
              {acts.favLoading ? <AiOutlineLoading3Quarters size={16} className="animate-spin" /> : acts.favorited ? <AiFillStar size={16} /> : <AiOutlineStar size={16} />}
            </button>
            <button
              onClick={(e) => handleAction(e, acts.handleLike)}
              disabled={acts.likeLoading}
              className={`t-act ${acts.liked ? 'is-liked' : ''}`}
              title={acts.liked ? t('actions.unlike') : t('actions.like')}
            >
              {acts.likeLoading ? <AiOutlineLoading3Quarters size={16} className="animate-spin" /> : acts.liked ? <AiFillHeart size={16} /> : <AiOutlineHeart size={16} />}
            </button>
            {acts.canDownload && (
              <button
                onClick={(e) => handleAction(e, acts.handleDownload)}
                disabled={acts.downloading}
                className={`t-act ${acts.downloaded ? 'is-downloaded' : ''} ${acts.downloading ? 'is-downloading' : ''}`}
                title={acts.downloadTitle}
                style={{ ['--download-progress' as string]: acts.downloadProgress ?? 0.08 } as CSSProperties}
              >
                {acts.downloading ? (
                  <AiOutlineLoading3Quarters size={16} className="animate-spin" />
                ) : acts.downloaded ? (
                  <AiOutlineCheckCircle size={16} />
                ) : (
                  <AiOutlineDownload size={16} />
                )}
              </button>
            )}
        </div>}
      </div>
    </Wrapper>
  );
}

// VideoHoverOverlay layers a muted, looping <video> on top of the
// poster image and only kicks off network I/O on hover (preload="none"
// + on-demand .load()). Browsers that pause autoplay outside the
// viewport are fine — we don't autoplay until the user is actually
// hovering the tile.
function VideoHoverOverlay({ src }: { src: string }) {
  const ref = useRef<HTMLVideoElement | null>(null);
  return (
    <video
      ref={ref}
      src={src}
      muted
      loop
      playsInline
      preload="none"
      className="tile-video absolute inset-0 w-full h-full object-cover opacity-0 transition-opacity duration-200 pointer-events-none"
      onMouseEnter={() => {
        const v = ref.current;
        if (!v) return;
        if (v.readyState < 2) v.load();
        v.play().catch(() => {});
      }}
    />
  );
}
