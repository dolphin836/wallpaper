import { useState } from 'react';
import type { CSSProperties } from 'react';
import { Link } from 'react-router-dom';
import {
  AiOutlineEye,
  AiOutlineHeart,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineLoading3Quarters,
  AiOutlineWarning,
} from 'react-icons/ai';
import type { Wallpaper } from '../types';

const STATUS_PROCESSING = 0;
const STATUS_PUBLISHED = 1;
const STATUS_FAILED = 2;

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)}KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
}

function formatCount(n: number): string {
  if (n >= 10000) return `${(n / 1000).toFixed(0)}K`;
  if (n >= 1000) return `${(n / 1000).toFixed(1)}K`;
  return String(n);
}

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
  const imgSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;

  const aspectRatio = wallpaper.width > 0 && wallpaper.height > 0
    ? wallpaper.width / wallpaper.height
    : 4 / 3;

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

        {/* Hover overlay with stats */}
        <div className="absolute inset-0 z-[2] bg-gradient-to-r from-black/60 via-black/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex flex-col justify-between p-3 pointer-events-none">
          <div className="flex flex-col gap-1 text-[11px] text-white/90">
            <span className="flex items-center gap-1">
              <AiOutlineEye size={13} />
              {formatCount(wallpaper.view_count)}
            </span>
            <span className="flex items-center gap-1">
              <AiOutlineHeart size={13} />
              {formatCount(wallpaper.like_count)}
            </span>
            <span className="flex items-center gap-1">
              <AiOutlineStar size={13} />
              {formatCount(wallpaper.favorite_count)}
            </span>
            <span className="flex items-center gap-1">
              <AiOutlineDownload size={13} />
              {formatCount(wallpaper.download_count)}
            </span>
          </div>
          <div className="flex flex-col gap-0.5 text-[10px] text-white/70">
            {wallpaper.width > 0 && wallpaper.height > 0 && (
              <span>{wallpaper.width}&times;{wallpaper.height}</span>
            )}
            {wallpaper.file_size > 0 && (
              <span>{formatSize(wallpaper.file_size)}</span>
            )}
          </div>
        </div>
      </div>
    </Link>
  );
}
