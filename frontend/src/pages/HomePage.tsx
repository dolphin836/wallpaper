import { useState, useEffect, useCallback, useMemo } from 'react';
import { MdDevices } from 'react-icons/md';
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

export default function HomePage() {
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [deviceFilter, setDeviceFilter] = useState(false);
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

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex items-center justify-between gap-2 mb-6">
        <button
          onClick={() => setDeviceFilter((p) => !p)}
          title={deviceFilter ? `${screen.width}×${screen.height} — click to show all` : 'Filter for your device'}
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
