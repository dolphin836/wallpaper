import { useState } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineHeart, AiOutlineDownload } from 'react-icons/ai';
import type { Wallpaper } from '../types';

interface Props {
  wallpaper: Wallpaper;
}

export default function WallpaperCard({ wallpaper }: Props) {
  const [loaded, setLoaded] = useState(false);
  const imgSrc = wallpaper.preview_url || wallpaper.thumb_url;

  return (
    <Link
      to={`/wallpaper/${wallpaper.id}`}
      className="group block rounded-xl overflow-hidden bg-white dark:bg-gray-800 shadow-sm hover:shadow-md transition-all duration-200"
    >
      <div
        className="relative overflow-hidden"
        style={{ backgroundColor: wallpaper.dominant_color || '#e5e7eb' }}
      >
        <img
          src={imgSrc}
          alt={wallpaper.title}
          loading="lazy"
          onLoad={() => setLoaded(true)}
          className={`w-full h-auto object-cover transition-all duration-500 group-hover:scale-105 ${loaded ? 'opacity-100' : 'opacity-0'}`}
        />
        {wallpaper.width > 0 && wallpaper.height > 0 && (
          <span className="absolute bottom-2 right-2 px-1.5 py-0.5 text-[10px] font-medium text-white/90 bg-black/50 rounded backdrop-blur-sm">
            {wallpaper.width}&times;{wallpaper.height}
          </span>
        )}
      </div>
      <div className="p-3">
        <h3 className="text-sm font-medium text-gray-800 dark:text-gray-200 truncate">{wallpaper.title}</h3>
        <div className="flex items-center gap-4 mt-1.5 text-xs text-gray-500 dark:text-gray-400">
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
    </Link>
  );
}
