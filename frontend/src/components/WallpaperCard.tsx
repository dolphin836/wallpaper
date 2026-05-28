import { useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
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
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { useAuthStore } from '../store/auth';
import { likeWallpaper, unlikeWallpaper, favoriteWallpaper, unfavoriteWallpaper, downloadWallpaper } from '../api';

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
  // Two-stage progressive load: thumb (~30 KB, displayed immediately with a
  // small blur) → preview_url (~250 KB watermarked 1600px, fades in once
  // loaded). Loading the 1600px preview on the home feed means the browser
  // HTTP cache already has it when the user opens a detail page, so detail
  // navigation feels instant — that's the trade-off vs a smaller dedicated
  // card-sized variant.
  const lowResSrc = wallpaper.thumb_url;
  const highResSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const [highLoaded, setHighLoaded] = useState(false);
  const [liked, setLiked] = useState(wallpaper.is_liked ?? false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favorited, setFavorited] = useState(wallpaper.is_favorited ?? false);
  const [favLoading, setFavLoading] = useState(false);
  const [downloaded, setDownloaded] = useState(wallpaper.is_downloaded ?? false);
  const [downloading, setDownloading] = useState(false);
  const { isAuthenticated, user, updateCoins } = useAuthStore();
  const navigate = useNavigate();
  const location = useLocation();

  const hasImage = lowResSrc.length > 0 || highResSrc.length > 0;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;
  const canDownload = !wallpaper.is_dynamic || /Macintosh|Mac OS X/i.test(navigator.userAgent);
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

  const handleAction = (e: React.MouseEvent, action: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    action();
  };

  const requireAuth = (action: () => void) => {
    if (!isAuthenticated) {
      navigate('/login');
      return;
    }
    action();
  };

  const isOwnWallpaper = user && wallpaper.user_id === user.id;

  const handleDownload = async () => {
    if (!isOwnWallpaper && user && user.coins <= 0) {
      toast.error('Insufficient coins. Upload wallpapers to earn more!');
      return;
    }
    setDownloading(true);
    try {
      const resp = await fetch(downloadWallpaper(wallpaper.id), {
        headers: { Authorization: `Bearer ${useAuthStore.getState().token}` },
      });
      if (resp.status === 402) {
        toast.error('Insufficient coins. Upload wallpapers to earn more!');
        return;
      }
      if (!resp.ok) {
        toast.error('Download failed');
        return;
      }
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      const ext = wallpaper.original_url.split('.').pop()?.split('?')[0] || 'jpg';
      a.download = `wallpaper_${wallpaper.id}.${ext}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setDownloaded(true);
      if (!isOwnWallpaper && user) {
        const remaining = user.coins - 1;
        updateCoins(remaining);
        if (remaining <= 3 && remaining > 0) {
          toast(`${remaining} coin${remaining === 1 ? '' : 's'} left. Upload wallpapers to earn more!`, { icon: '💡' });
        }
      }
    } catch {
      toast.error('Download failed');
    } finally {
      setDownloading(false);
    }
  };

  const handleLike = async () => {
    if (likeLoading) return;
    setLikeLoading(true);
    try {
      if (liked) {
        await unlikeWallpaper(wallpaper.id);
      } else {
        await likeWallpaper(wallpaper.id);
      }
      setLiked(!liked);
    } catch {
      toast.error('Action failed');
    } finally {
      setLikeLoading(false);
    }
  };

  const handleFavorite = async () => {
    if (favLoading) return;
    setFavLoading(true);
    try {
      if (favorited) {
        await unfavoriteWallpaper(wallpaper.id);
      } else {
        await favoriteWallpaper(wallpaper.id);
      }
      setFavorited(!favorited);
    } catch {
      toast.error('Action failed');
    } finally {
      setFavLoading(false);
    }
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
              onLoad={() => setHighLoaded(true)}
              onContextMenu={(e) => e.preventDefault()}
              draggable={false}
              className={`tile-img absolute inset-0 w-full h-full object-cover select-none ${highLoaded ? 'opacity-100' : 'opacity-0'}`}
              style={{ WebkitUserDrag: 'none', transition: highLoaded ? undefined : 'opacity 300ms ease' } as React.CSSProperties}
            />
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
          {isVideo && (
            <span className="tile-chip">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
              Video
            </span>
          )}
          {wallpaper.is_dynamic && (
            <span className="tile-chip">
              <svg viewBox="0 0 384 512" fill="currentColor" aria-hidden><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
              Mac
            </span>
          )}
          {wallpaper.is_ai_generated && (
            <span className="tile-chip is-ai">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z"/></svg>
              AI
            </span>
          )}
        </div>

        {/* Hover action rail. Order: favorite → like → download.
            CSS handles fade-in via .tile-cell:hover .tile-actions. */}
        {isPublished && !hideActions && (
          <div className="tile-actions">
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleFavorite))}
              disabled={favLoading}
              className={`t-act ${favorited ? 'is-favorited' : ''}`}
              title={favorited ? 'Unfavorite' : 'Favorite'}
            >
              {favLoading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : favorited ? <AiFillStar size={15} /> : <AiOutlineStar size={15} />}
            </button>
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleLike))}
              disabled={likeLoading}
              className={`t-act ${liked ? 'is-liked' : ''}`}
              title={liked ? 'Unlike' : 'Like'}
            >
              {likeLoading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : liked ? <AiFillHeart size={15} /> : <AiOutlineHeart size={15} />}
            </button>
            {canDownload && (
              <button
                onClick={(e) => handleAction(e, () => requireAuth(handleDownload))}
                disabled={downloading}
                className={`t-act ${downloaded ? 'is-downloaded' : ''}`}
                title={downloaded ? 'Downloaded' : 'Download (1 coin)'}
              >
                {downloading ? <AiOutlineLoading3Quarters size={15} className="animate-spin" /> : downloaded ? <AiOutlineCheckCircle size={15} /> : <AiOutlineDownload size={15} />}
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
      className={`wp-card group block rounded-lg overflow-hidden bg-slate-100 dark:bg-ws-dark-card transition-all duration-300 ${fillHeight ? 'h-full' : ''} animate-fade-in`}
      style={{ ...style, animationDelay: `${animDelay}ms`, ...(isPublished ? {} : { cursor: 'default' }) }}
    >
      <div
        className={`relative overflow-hidden ${fillHeight ? 'h-full' : ''} ${fixedAspect ? 'aspect-[3/2]' : ''}`}
        style={{
          backgroundColor: wallpaper.dominant_color || '#e5e7eb',
          aspectRatio: !fixedAspect && !fillHeight ? aspectRatio : undefined,
        }}
      >
        {hasImage && !highLoaded && (
          <div className="absolute inset-0 z-[1] shimmer-overlay" />
        )}

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
              <AiOutlineLoading3Quarters size={32} className="text-slate-400 animate-spin" />
            ) : (
              <AiOutlineWarning size={32} className="text-slate-400" />
            )}
          </div>
        )}

        {/* Tags: top-left */}
        <div className="absolute top-2.5 left-2.5 z-[3] flex items-center gap-1.5">
          {isVideo && (
            <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-black/50 text-white backdrop-blur-sm">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
              Video
            </span>
          )}
          {wallpaper.is_dynamic && (
            <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-black/50 text-white backdrop-blur-sm">
              <svg width="10" height="10" viewBox="0 0 384 512" fill="currentColor"><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
              macOS
            </span>
          )}
          {wallpaper.is_ai_generated && (
            <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-violet-600/85 text-white backdrop-blur-sm">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z"/></svg>
              AI
            </span>
          )}
          {resLabel && (
            <span className="px-1.5 py-0.5 text-[10px] font-medium rounded bg-black/50 text-white/80 backdrop-blur-sm">
              {resLabel}
            </span>
          )}
        </div>

        {showStatus && wallpaper.status !== STATUS_PUBLISHED && (() => {
          // Tone + label table indexed by status. Pending review +
          // Rejected are owner-only states that appear on the "my
          // uploads" view; they never reach strangers because the
          // public list filter restricts to Published.
          const tone =
            isProcessing ? 'bg-amber-500/80 text-white' :
            isFailed ? 'bg-red-500/80 text-white' :
            wallpaper.status === STATUS_PENDING_REVIEW ? 'bg-violet-500/85 text-white' :
            wallpaper.status === STATUS_REJECTED ? 'bg-red-500/85 text-white' :
            'bg-slate-500/80 text-white';
          const label =
            isProcessing ? 'Processing' :
            isFailed ? 'Failed' :
            wallpaper.status === STATUS_PENDING_REVIEW ? 'Pending review' :
            wallpaper.status === STATUS_REJECTED ? 'Rejected' :
            `Status ${wallpaper.status}`;
          return (
            <span
              className={`absolute ${wallpaper.is_dynamic || resLabel || wallpaper.is_ai_generated ? 'top-8' : 'top-2.5'} left-2.5 z-[3] px-2 py-0.5 text-[10px] font-semibold rounded-full backdrop-blur-sm ${tone}`}
              title={wallpaper.status === STATUS_REJECTED && wallpaper.rejection_reason ? wallpaper.rejection_reason : undefined}
            >
              {label}
            </span>
          );
        })()}

        {/* Action buttons — appear on hover, only for published wallpapers */}
        {isPublished && !hideActions && <div className="absolute right-0 top-0 bottom-0 z-[2] p-2.5 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-end">
          <div className="flex flex-col gap-1.5">
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleLike))}
              disabled={likeLoading}
              className={`p-2.5 rounded-full backdrop-blur-md transition-all duration-200 disabled:opacity-50 ${
                liked
                  ? 'bg-red-500/90 text-white'
                  : 'bg-white/20 text-white hover:bg-white/30'
              }`}
              title={liked ? 'Unlike' : 'Like'}
            >
              {likeLoading ? <AiOutlineLoading3Quarters size={16} className="animate-spin" /> : liked ? <AiFillHeart size={16} /> : <AiOutlineHeart size={16} />}
            </button>
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleFavorite))}
              disabled={favLoading}
              className={`p-2.5 rounded-full backdrop-blur-md transition-all duration-200 disabled:opacity-50 ${
                favorited
                  ? 'bg-amber-500/90 text-white'
                  : 'bg-white/20 text-white hover:bg-white/30'
              }`}
              title={favorited ? 'Unfavorite' : 'Favorite'}
            >
              {favLoading ? <AiOutlineLoading3Quarters size={16} className="animate-spin" /> : favorited ? <AiFillStar size={16} /> : <AiOutlineStar size={16} />}
            </button>
            {canDownload && (
              <button
                onClick={(e) => handleAction(e, () => requireAuth(handleDownload))}
                disabled={downloading}
                className={`p-2.5 rounded-full backdrop-blur-md transition-all duration-200 disabled:opacity-50 ${
                  downloaded
                    ? 'bg-green-500/90 text-white'
                    : 'bg-white/20 text-white hover:bg-white/30'
                }`}
                title={downloaded ? 'Downloaded' : 'Download (1 coin)'}
              >
                {downloading ? (
                  <AiOutlineLoading3Quarters size={16} className="animate-spin" />
                ) : downloaded ? (
                  <AiOutlineCheckCircle size={16} />
                ) : (
                  <AiOutlineDownload size={16} />
                )}
              </button>
            )}
          </div>
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
