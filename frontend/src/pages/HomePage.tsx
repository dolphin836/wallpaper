import { useState, useEffect, useCallback, useMemo } from 'react';
import { BsGrid, BsColumnsGap, BsImage } from 'react-icons/bs';
import { MdDevices } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers } from '../api';
import WallpaperGrid from '../components/WallpaperGrid';
import type { ViewMode } from '../components/WallpaperGrid';

const VIEW_MODES: { key: ViewMode; icon: typeof BsGrid; label: string }[] = [
  { key: 'waterfall', icon: BsColumnsGap, label: 'Waterfall' },
  { key: 'grid', icon: BsGrid, label: 'Grid' },
  { key: 'justified', icon: BsImage, label: 'Album' },
];

const SKELETON_RATIOS = [4/3, 3/4, 16/9, 1, 3/4, 4/3, 16/9, 3/2, 3/4, 4/3, 1, 16/9];

function getScreenResolution() {
  const dpr = window.devicePixelRatio || 1;
  return {
    width: Math.round(window.screen.width * dpr),
    height: Math.round(window.screen.height * dpr),
  };
}

function SkeletonGrid() {
  return (
    <div className="columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-5 space-y-5">
      {SKELETON_RATIOS.map((ratio, i) => (
        <div key={i} className="break-inside-avoid">
          <div
            className="rounded-xl bg-gray-200 dark:bg-gray-700 skeleton-card"
            style={{ aspectRatio: ratio, animationDelay: `${i * 100}ms` }}
          />
        </div>
      ))}
    </div>
  );
}

export default function HomePage() {
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [deviceFilter, setDeviceFilter] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    return (localStorage.getItem('wallpaper_view_mode') as ViewMode) || 'waterfall';
  });

  const screen = useMemo(() => getScreenResolution(), []);

  const handleViewChange = (mode: ViewMode) => {
    setViewMode(mode);
    localStorage.setItem('wallpaper_view_mode', mode);
  };

  const fetchWallpapers = useCallback(async (reset: boolean, forDevice: boolean) => {
    const setter = reset ? setLoading : setLoadingMore;
    setter(true);
    try {
      const params: Parameters<typeof getWallpapers>[0] = {
        cursor: reset ? undefined : cursor,
        limit: 20,
      };
      if (forDevice) {
        params.device_width = screen.width;
        params.device_height = screen.height;
      }
      const res = await getWallpapers(params);
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => (reset ? items : [...prev, ...items]));
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load wallpapers');
    } finally {
      setter(false);
    }
  }, [cursor, screen]);

  useEffect(() => {
    fetchWallpapers(true, deviceFilter);
  }, [deviceFilter]);

  const toggleDeviceFilter = () => {
    setDeviceFilter((prev) => !prev);
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex items-center justify-between gap-2 mb-6">
        <button
          onClick={toggleDeviceFilter}
          title={deviceFilter ? `Showing wallpapers for ${screen.width}×${screen.height} — click to show all` : 'Show only wallpapers matching your device'}
          className={`flex items-center gap-2 px-3.5 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
            deviceFilter
              ? 'bg-indigo-600 text-white'
              : 'bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-700'
          }`}
        >
          <MdDevices size={18} />
          <span className="hidden sm:inline">
            {deviceFilter ? `${screen.width}×${screen.height}` : 'My Device'}
          </span>
        </button>

        <div className="flex items-center gap-1">
          {VIEW_MODES.map(({ key, icon: Icon, label }) => (
            <button
              key={key}
              onClick={() => handleViewChange(key)}
              title={label}
              className={`p-2 rounded-lg transition-colors duration-200 ${
                viewMode === key
                  ? 'bg-indigo-100 text-indigo-600'
                  : 'text-gray-400 hover:text-gray-600 hover:bg-gray-100'
              }`}
            >
              <Icon size={18} />
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <SkeletonGrid />
      ) : (
        <>
          <WallpaperGrid wallpapers={wallpapers} viewMode={viewMode} />
          {hasMore && (
            <div className="flex justify-center mt-8">
              <button
                onClick={() => fetchWallpapers(false, deviceFilter)}
                disabled={loadingMore}
                className="px-6 py-2.5 text-sm font-medium text-indigo-600 border border-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors duration-200 disabled:opacity-50"
              >
                {loadingMore ? (
                  <span className="flex items-center gap-2">
                    <div className="w-4 h-4 border-2 border-indigo-200 border-t-indigo-600 rounded-full animate-spin" />
                    Loading...
                  </span>
                ) : (
                  'Load More'
                )}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
