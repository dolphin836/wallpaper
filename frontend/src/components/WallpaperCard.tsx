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
  const [liked, setLiked] = useState(false);
  const [favorited, setFavorited] = useState(false);
  const { isAuthenticated } = useAuthStore();
  const navigate = useNavigate();

  const imgSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;

  const aspectRatio = wallpaper.width > 0 && wallpaper.height > 0
    ? wallpaper.width / wallpaper.height
    : 4 / 3;

  const handleAction = (e: React.MouseEvent, action: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    action();
  };

  const handleDownload = async () => {
    try {
      const resp = await fetch(downloadWallpaper(wallpaper.id));
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
    } catch {
      toast.error('Download failed');
    }
  };

  const handleLike = async () => {
    if (!isAuthenticated) { navigate('/login'); return; }
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
    if (!isAuthenticated) { navigate('/login'); return; }
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
          <img
            src={imgSrc}
            alt=""
            loading="lazy"
            onLoad={() => setLoaded(true)}
            className={`w-full h-full object-cover transition-opacity duration-500 group-hover:scale-105 transition-transform ${loaded ? 'opacity-100' : 'opacity-0'}`}
          />
        ) : (
          <div className={`w-full flex items-center justify-center ${fixedAspect || fillHeight ? 'h-full' : 'aspect-[4/3]'}`}>
            {isProcessing ? (
              <AiOutlineLoading3Quarters size={32} className="text-gray-400 animate-spin" />
            ) : (
              <AiOutlineWarning size={32} className="text-gray-400" />
            )}
          </div>
        )}

        {showStatus && wallpaper.status !== STATUS_PUBLISHED && (
          <span
            className={`absolute top-2 left-2 z-[3] px-2 py-0.5 text-[10px] font-semibold rounded-full backdrop-blur-sm ${
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

        {/* Hover action buttons */}
        <div className="absolute right-0 top-0 bottom-0 z-[2] opacity-0 group-hover:opacity-100 transition-opacity duration-300 bg-gradient-to-l from-black/50 to-transparent pl-8 pr-3 flex items-center">
          <div className="flex flex-col gap-2">
            {isAuthenticated && (
              <>
                <button
                  onClick={(e) => handleAction(e, handleLike)}
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
                  onClick={(e) => handleAction(e, handleFavorite)}
                  className={`p-2 rounded-full backdrop-blur-sm transition-colors ${
                    favorited
                      ? 'bg-amber-500/80 text-white'
                      : 'bg-white/20 text-white hover:bg-white/30'
                  }`}
                  title={favorited ? 'Unfavorite' : 'Favorite'}
                >
                  {favorited ? <AiFillStar size={18} /> : <AiOutlineStar size={18} />}
                </button>
              </>
            )}
            <button
              onClick={(e) => handleAction(e, handleDownload)}
              className="p-2 rounded-full bg-white/20 text-white hover:bg-white/30 backdrop-blur-sm transition-colors"
              title="Download"
            >
              <AiOutlineDownload size={18} />
            </button>
          </div>
        </div>
      </div>
    </Link>
  );
}
