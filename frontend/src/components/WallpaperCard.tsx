import { useState } from 'react';
import type { CSSProperties } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  AiOutlineHeart,
  AiFillHeart,
  AiOutlineStar,
  AiFillStar,
  AiOutlineDownload,
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
  const [favorited, setFavorited] = useState(wallpaper.is_favorited ?? false);
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
      if (!isOwnWallpaper && user) {
        updateCoins(user.coins - 1);
      }
    } catch {
      toast.error('Download failed');
    } finally {
      setDownloading(false);
    }
  };

  const handleLike = async () => {
    try {
      if (liked) {
        await unlikeWallpaper(wallpaper.id);
      } else {
        await likeWallpaper(wallpaper.id);
      }
      setLiked(!liked);
    } catch {
      toast.error('Action failed');
    }
  };

  const handleFavorite = async () => {
    try {
      if (favorited) {
        await unfavoriteWallpaper(wallpaper.id);
      } else {
        await favoriteWallpaper(wallpaper.id);
      }
      setFavorited(!favorited);
    } catch {
      toast.error('Action failed');
    }
  };

  return (
    <Link
      to={`/wallpaper/${wallpaper.id}`}
      className={`group block rounded-xl overflow-hidden bg-white dark:bg-gray-800 shadow-sm hover:shadow-md transition-all duration-300 ${fillHeight ? 'h-full' : ''} animate-fade-in`}
      style={{ ...style, animationDelay: `${animDelay}ms` }}
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
              className={`w-full h-full object-cover transition-opacity duration-500 group-hover:scale-105 transition-transform select-none ${loaded ? 'opacity-100' : 'opacity-0'}`}
              style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
            />
            <div className="absolute inset-0 z-[1]" onContextMenu={(e) => e.preventDefault()} />
          </>
        ) : (
          <div className={`w-full flex items-center justify-center ${fixedAspect || fillHeight ? 'h-full' : 'aspect-[4/3]'}`}>
            {isProcessing ? (
              <AiOutlineLoading3Quarters size={32} className="text-gray-400 animate-spin" />
            ) : (
              <AiOutlineWarning size={32} className="text-gray-400" />
            )}
          </div>
        )}

        {wallpaper.is_dynamic && (
          <span className="absolute top-2 left-2 z-[3] flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-black/60 text-white backdrop-blur-sm">
            <svg width="10" height="10" viewBox="0 0 384 512" fill="currentColor"><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
            macOS
          </span>
        )}

        {showStatus && wallpaper.status !== STATUS_PUBLISHED && (
          <span
            className={`absolute ${wallpaper.is_dynamic ? 'top-8' : 'top-2'} left-2 z-[3] px-2 py-0.5 text-[10px] font-semibold rounded-full backdrop-blur-sm ${
              isProcessing
                ? 'bg-amber-500/80 text-white'
                : isFailed
                  ? 'bg-red-500/80 text-white'
                  : 'bg-gray-500/80 text-white'
            }`}
          >
            {isProcessing ? 'Processing' : isFailed ? 'Failed' : `Status ${wallpaper.status}`}
          </span>
        )}

        {/* Action buttons — always visible */}
        <div className="absolute right-0 top-0 bottom-0 z-[2] bg-gradient-to-l from-black/40 to-transparent pl-8 pr-3 flex items-end pb-3 opacity-0 group-hover:opacity-100 sm:opacity-100 transition-opacity duration-300">
          <div className="flex flex-col gap-2">
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleLike))}
              className={`p-2 rounded-full backdrop-blur-sm transition-colors ${
                liked
                  ? 'bg-red-500/80 text-white'
                  : 'bg-white/20 text-white hover:bg-white/30'
              }`}
              title={liked ? 'Unlike' : 'Like'}
            >
              {liked ? <AiFillHeart size={18} /> : <AiOutlineHeart size={18} />}
            </button>
            <button
              onClick={(e) => handleAction(e, () => requireAuth(handleFavorite))}
              className={`p-2 rounded-full backdrop-blur-sm transition-colors ${
                favorited
                  ? 'bg-amber-500/80 text-white'
                  : 'bg-white/20 text-white hover:bg-white/30'
              }`}
              title={favorited ? 'Unfavorite' : 'Favorite'}
            >
              {favorited ? <AiFillStar size={18} /> : <AiOutlineStar size={18} />}
            </button>
            {canDownload && (
              <button
                onClick={(e) => handleAction(e, () => requireAuth(handleDownload))}
                disabled={downloading}
                className="p-2 rounded-full bg-white/20 text-white hover:bg-white/30 backdrop-blur-sm transition-colors disabled:opacity-50"
                title="Download (1 coin)"
              >
                {downloading ? (
                  <AiOutlineLoading3Quarters size={18} className="animate-spin" />
                ) : (
                  <AiOutlineDownload size={18} />
                )}
              </button>
            )}
          </div>
        </div>
      </div>
    </Link>
  );
}
