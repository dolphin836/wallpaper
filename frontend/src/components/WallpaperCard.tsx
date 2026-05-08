import { useState } from 'react';
import type { CSSProperties } from 'react';
import { Link, useNavigate } from 'react-router-dom';
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

interface Props {
  wallpaper: Wallpaper;
  showStatus?: boolean;
  fixedAspect?: boolean;
  fillHeight?: boolean;
  style?: CSSProperties;
  animDelay?: number;
}

export default function WallpaperCard({ wallpaper, showStatus, fixedAspect, fillHeight, style, animDelay = 0 }: Props) {
  const [loaded, setLoaded] = useState(false);
  const [liked, setLiked] = useState(wallpaper.is_liked ?? false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favorited, setFavorited] = useState(wallpaper.is_favorited ?? false);
  const [favLoading, setFavLoading] = useState(false);
  const [downloaded, setDownloaded] = useState(wallpaper.is_downloaded ?? false);
  const [downloading, setDownloading] = useState(false);
  const { isAuthenticated, user, updateCoins } = useAuthStore();
  const navigate = useNavigate();

  const imgSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;
  const canDownload = !wallpaper.is_dynamic || /Macintosh|Mac OS X/i.test(navigator.userAgent);

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
  const wrapperProps = isPublished
    ? { to: `/wallpaper/${wallpaper.slug}` }
    : { style: { cursor: 'default' } };

  return (
    <Wrapper
      {...(wrapperProps as any)}
      className={`group block rounded-lg overflow-hidden bg-slate-100 dark:bg-ws-dark-card transition-all duration-300 ${fillHeight ? 'h-full' : ''} animate-fade-in`}
      style={{ ...style, animationDelay: `${animDelay}ms`, ...(isPublished ? {} : { cursor: 'default' }) }}
    >
      <div
        className={`relative overflow-hidden ${fillHeight ? 'h-full' : ''} ${fixedAspect ? 'aspect-[3/2]' : ''}`}
        style={{
          backgroundColor: wallpaper.dominant_color || '#e5e7eb',
          aspectRatio: !fixedAspect && !fillHeight ? aspectRatio : undefined,
        }}
      >
        {imgSrc && !loaded && (
          <div className="absolute inset-0 z-[1] shimmer-overlay" />
        )}

        {imgSrc ? (
          <>
            <img
              src={imgSrc}
              alt=""
              loading="lazy"
              onLoad={() => setLoaded(true)}
              onContextMenu={(e) => e.preventDefault()}
              draggable={false}
              className={`w-full h-full object-cover transition-all duration-500 group-hover:scale-105 select-none ${loaded ? 'opacity-100' : 'opacity-0'}`}
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
          {wallpaper.is_dynamic && (
            <span className="flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-black/50 text-white backdrop-blur-sm">
              <svg width="10" height="10" viewBox="0 0 384 512" fill="currentColor"><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
              macOS
            </span>
          )}
          {resLabel && (
            <span className="px-1.5 py-0.5 text-[10px] font-medium rounded bg-black/50 text-white/80 backdrop-blur-sm">
              {resLabel}
            </span>
          )}
        </div>

        {showStatus && wallpaper.status !== STATUS_PUBLISHED && (
          <span
            className={`absolute ${wallpaper.is_dynamic || resLabel ? 'top-8' : 'top-2.5'} left-2.5 z-[3] px-2 py-0.5 text-[10px] font-semibold rounded-full backdrop-blur-sm ${
              isProcessing
                ? 'bg-amber-500/80 text-white'
                : isFailed
                  ? 'bg-red-500/80 text-white'
                  : 'bg-slate-500/80 text-white'
            }`}
          >
            {isProcessing ? 'Processing' : isFailed ? 'Failed' : `Status ${wallpaper.status}`}
          </span>
        )}

        {/* Action buttons — appear on hover, only for published wallpapers */}
        {isPublished && <div className="absolute right-0 top-0 bottom-0 z-[2] p-2.5 opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-end">
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
