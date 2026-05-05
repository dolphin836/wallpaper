import { useState, CSSProperties } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineHeart, AiOutlineDownload, AiOutlineLoading3Quarters, AiOutlineWarning } from 'react-icons/ai';
import type { Wallpaper } from '../types';

const STATUS_PROCESSING = 0;
const STATUS_PUBLISHED = 1;
const STATUS_FAILED = 2;

interface Props {
  wallpaper: Wallpaper;
  showStatus?: boolean;
  fixedAspect?: boolean;
  fillHeight?: boolean;
  style?: CSSProperties;
}

export default function WallpaperCard({ wallpaper, showStatus, fixedAspect, fillHeight, style }: Props) {
  const [loaded, setLoaded] = useState(false);
  const imgSrc = wallpaper.preview_url || wallpaper.thumb_url;
  const isProcessing = wallpaper.status === STATUS_PROCESSING;
  const isFailed = wallpaper.status === STATUS_FAILED;

  return (
    <Link
      to={`/wallpaper/${wallpaper.id}`}
      className={`group block rounded-xl overflow-hidden bg-white dark:bg-gray-800 shadow-sm hover:shadow-md transition-all duration-200 ${fillHeight ? 'h-full' : ''}`}
      style={style}
    >
      <div
        className={`relative overflow-hidden ${fillHeight ? 'h-full' : ''} ${fixedAspect ? 'aspect-[3/2]' : ''}`}
        style={{ backgroundColor: wallpaper.dominant_color || '#e5e7eb' }}
      >
        {imgSrc ? (
          <img
            src={imgSrc}
            alt=""
            loading="lazy"
            onLoad={() => setLoaded(true)}
            className={`w-full h-full object-cover transition-all duration-500 group-hover:scale-105 ${loaded ? 'opacity-100' : 'opacity-0'}`}
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
            className={`absolute top-2 left-2 px-2 py-0.5 text-[10px] font-semibold rounded-full backdrop-blur-sm ${
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

        {wallpaper.width > 0 && wallpaper.height > 0 && (
          <span className="absolute bottom-2 right-2 px-1.5 py-0.5 text-[10px] font-medium text-white/90 bg-black/50 rounded backdrop-blur-sm">
            {wallpaper.width}&times;{wallpaper.height}
          </span>
        )}

        {!fillHeight && !fixedAspect && (
          <div className="absolute inset-0 bg-black/0 group-hover:bg-black/10 transition-colors duration-200" />
        )}
      </div>

      {!fillHeight && (
        <div className="p-3">
          <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
            <span className="flex items-center gap-1">
              <AiOutlineHeart size={14} />
              {wallpaper.like_count}
            </span>
            <span className="flex items-center gap-1">
              <AiOutlineDownload size={14} />
              {wallpaper.download_count}
            </span>
          </div>
        </div>
      )}
    </Link>
  );
}
