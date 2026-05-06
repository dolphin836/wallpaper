import { useState, useEffect, useCallback, useMemo } from 'react';
import { MdDevices, MdTrendingUp } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers } from '../api';
import WallpaperGrid from '../components/WallpaperGrid';
import type { ViewMode, SizeMode } from '../components/WallpaperGrid';

function IconJustified({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="currentColor">
      <rect x="1" y="2" width="8" height="7" rx="1.5" />
      <rect x="11" y="2" width="8" height="7" rx="1.5" />
      <rect x="1" y="11" width="12" height="7" rx="1.5" />
      <rect x="15" y="11" width="4" height="7" rx="1.5" />
    </svg>
  );
}

function IconGrid({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="currentColor">
      <rect x="1" y="1" width="8" height="8" rx="1.5" />
      <rect x="11" y="1" width="8" height="8" rx="1.5" />
      <rect x="1" y="11" width="8" height="8" rx="1.5" />
      <rect x="11" y="11" width="8" height="8" rx="1.5" />
    </svg>
  );
}

function IconSizeLg({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="currentColor">
      <rect x="1" y="1" width="8.5" height="8.5" rx="1.5" />
      <rect x="10.5" y="1" width="8.5" height="8.5" rx="1.5" />
      <rect x="1" y="10.5" width="8.5" height="8.5" rx="1.5" />
      <rect x="10.5" y="10.5" width="8.5" height="8.5" rx="1.5" />
    </svg>
  );
}

function IconGridMd({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="currentColor">
      <rect x="1" y="1" width="5" height="5" rx="1" />
      <rect x="7.5" y="1" width="5" height="5" rx="1" />
      <rect x="14" y="1" width="5" height="5" rx="1" />
      <rect x="1" y="7.5" width="5" height="5" rx="1" />
      <rect x="7.5" y="7.5" width="5" height="5" rx="1" />
      <rect x="14" y="7.5" width="5" height="5" rx="1" />
      <rect x="1" y="14" width="5" height="5" rx="1" />
      <rect x="7.5" y="14" width="5" height="5" rx="1" />
      <rect x="14" y="14" width="5" height="5" rx="1" />
    </svg>
  );
}

function IconGridSm({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="currentColor">
      {[0, 1, 2, 3, 4].map((r) =>
        [0, 1, 2, 3, 4].map((c) => (
          <rect key={`${r}-${c}`} x={1 + c * 3.8} y={1 + r * 3.8} width="2.8" height="2.8" rx="0.6" />
        ))
      )}
    </svg>
  );
}

type ToolbarItem =
  | { type: 'view'; key: ViewMode; icon: React.FC<{ size?: number }>; label: string }
  | { type: 'size'; key: SizeMode; icon: React.FC<{ size?: number }>; label: string };

const TOOLBAR_ITEMS: ToolbarItem[] = [
  { type: 'view', key: 'justified', icon: IconJustified, label: 'Justified' },
  { type: 'view', key: 'grid', icon: IconGrid, label: 'Grid' },
  { type: 'size', key: 'lg', icon: IconSizeLg, label: 'Large' },
  { type: 'size', key: 'md', icon: IconGridMd, label: 'Medium' },
  { type: 'size', key: 'sm', icon: IconGridSm, label: 'Small' },
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
    <div className="flex flex-wrap gap-1.5">
      {SKELETON_RATIOS.map((ratio, i) => (
        <div
          key={i}
          className="rounded-xl bg-gray-200 dark:bg-gray-700 skeleton-card"
          style={{ width: 260 * ratio, height: 260, animationDelay: `${i * 100}ms` }}
        />
      ))}
    </div>
  );
}

const isMac = /Macintosh|Mac OS X/i.test(navigator.userAgent);

function AppleIcon({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 384 512" fill="currentColor">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/>
    </svg>
  );
}

export default function HomePage() {
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [deviceFilter, setDeviceFilter] = useState(false);
  const [macFilter, setMacFilter] = useState(false);
  const [sortTrending, setSortTrending] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    return (localStorage.getItem('wallpaper_view_mode') as ViewMode) || 'justified';
  });
  const [sizeMode, setSizeMode] = useState<SizeMode>(() => {
    return (localStorage.getItem('wallpaper_size_mode') as SizeMode) || 'md';
  });

  const screen = useMemo(() => getScreenResolution(), []);

  const handleViewChange = (mode: ViewMode) => {
    setViewMode(mode);
    localStorage.setItem('wallpaper_view_mode', mode);
  };

  const handleSizeChange = (size: SizeMode) => {
    setSizeMode(size);
    localStorage.setItem('wallpaper_size_mode', size);
  };

  const toggleDeviceFilter = () => {
    setDeviceFilter((p) => {
      if (!p) setMacFilter(false);
      return !p;
    });
  };

  const toggleMacFilter = () => {
    setMacFilter((p) => {
      if (!p) setDeviceFilter(false);
      return !p;
    });
  };

  const fetchWallpapers = useCallback(async (reset: boolean) => {
    const setter = reset ? setLoading : setLoadingMore;
    setter(true);
    try {
      const params: Parameters<typeof getWallpapers>[0] = {
        cursor: reset ? undefined : cursor,
        limit: 20,
      };
      if (macFilter) {
        params.dynamic_only = true;
      } else if (deviceFilter) {
        params.device_width = screen.width;
        params.device_height = screen.height;
        if (isMac) params.include_dynamic = true;
      }
      if (sortTrending) {
        params.sort = 'trending';
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
  }, [cursor, screen, deviceFilter, macFilter, sortTrending]);

  useEffect(() => {
    fetchWallpapers(true);
  }, [deviceFilter, macFilter, sortTrending]);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex items-center justify-between gap-2 mb-6">
        {/* Filters */}
        <div className="flex items-center gap-2">
          <span className="text-xs font-medium text-gray-400 uppercase tracking-wider mr-1 hidden sm:inline">Filter</span>
          <button
            onClick={toggleDeviceFilter}
            title={deviceFilter ? `${screen.width}×${screen.height} — click to show all` : 'Filter for your device'}
            className={`flex items-center gap-1.5 px-3.5 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
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
          <button
            onClick={toggleMacFilter}
            title={macFilter ? 'Showing macOS dynamic wallpapers — click to show all' : 'Show only macOS dynamic wallpapers'}
            className={`flex items-center gap-1.5 px-3.5 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
              macFilter
                ? 'bg-gray-900 text-white dark:bg-white dark:text-gray-900'
                : 'bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-700'
            }`}
          >
            <AppleIcon size={15} />
            <span className="hidden sm:inline">macOS</span>
          </button>

          <div className="w-px h-6 bg-gray-200 dark:bg-gray-600 mx-1" />

          {/* Sort */}
          <span className="text-xs font-medium text-gray-400 uppercase tracking-wider mr-1 hidden sm:inline">Sort</span>
          <button
            onClick={() => setSortTrending((p) => !p)}
            title={sortTrending ? 'Showing trending — click for latest' : 'Sort by trending'}
            className={`flex items-center gap-1.5 px-3.5 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
              sortTrending
                ? 'bg-orange-500 text-white'
                : 'bg-gray-100 text-gray-500 hover:bg-gray-200 hover:text-gray-700'
            }`}
          >
            <MdTrendingUp size={18} />
            <span className="hidden sm:inline">Trending</span>
          </button>
        </div>

        {/* Layout */}
        <div className="flex items-center gap-1.5">
          {TOOLBAR_ITEMS.map((item, i) => {
            const isActive = item.type === 'view'
              ? viewMode === item.key
              : sizeMode === item.key;
            const showDivider = i === 2;
            const Icon = item.icon;
            return (
              <div key={`${item.type}-${item.key}`} className="flex items-center gap-1.5">
                {showDivider && (
                  <div className="w-px h-6 bg-gray-200 dark:bg-gray-600 mx-0.5" />
                )}
                <button
                  onClick={() => {
                    if (item.type === 'view') handleViewChange(item.key as ViewMode);
                    else handleSizeChange(item.key as SizeMode);
                  }}
                  title={item.label}
                  className={`w-10 h-10 flex items-center justify-center rounded-xl transition-all duration-200 ${
                    isActive
                      ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400 shadow-sm'
                      : 'bg-gray-100 text-gray-400 hover:bg-green-50 hover:text-green-600 hover:shadow-sm dark:bg-gray-800 dark:text-gray-500 dark:hover:bg-green-900/20 dark:hover:text-green-400'
                  }`}
                >
                  <Icon size={20} />
                </button>
              </div>
            );
          })}
        </div>
      </div>

      {loading ? (
        <SkeletonGrid />
      ) : (
        <>
          <WallpaperGrid wallpapers={wallpapers} viewMode={viewMode} sizeMode={sizeMode} />
          {hasMore && (
            <div className="flex justify-center mt-8">
              <button
                onClick={() => fetchWallpapers(false)}
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
