import type { Wallpaper } from '../types';
import WallpaperCard from './WallpaperCard';
import EmptyState from './EmptyState';

interface Props {
  wallpapers: Wallpaper[];
  showStatus?: boolean;
}

export default function WallpaperGrid({ wallpapers, showStatus }: Props) {
  if (wallpapers.length === 0) {
    return <EmptyState message="No wallpapers found." />;
  }

  return (
    <div className="columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-5 space-y-5">
      {wallpapers.map((w) => (
        <div key={w.id} className="break-inside-avoid">
          <WallpaperCard wallpaper={w} showStatus={showStatus} />
        </div>
      ))}
    </div>
  );
}
