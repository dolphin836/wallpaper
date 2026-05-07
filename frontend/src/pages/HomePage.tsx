import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { MdDevices } from 'react-icons/md';
import { AiOutlineStar, AiOutlineClockCircle, AiOutlineAppstore, AiOutlineBars } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers } from '../api';
import WallpaperGrid from '../components/WallpaperGrid';
import type { ViewMode, SizeMode } from '../components/WallpaperGrid';

function getScreenResolution() {
  const dpr = window.devicePixelRatio || 1;
  return {
    width: Math.round(window.screen.width * dpr),
    height: Math.round(window.screen.height * dpr),
  };
}

function SkeletonGrid() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
      {Array.from({ length: 9 }).map((_, i) => (
        <div
          key={i}
          className="aspect-[4/3] rounded-xl bg-slate-100 dark:bg-ws-dark-card skeleton-card"
          style={{ animationDelay: `${i * 80}ms` }}
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

const CACHE_KEY = 'home_feed_cache';

interface FeedCache {
  wallpapers: Wallpaper[];
  cursor?: number;
  hasMore: boolean;
  scrollY: number;
  deviceFilter: boolean;
  macFilter: boolean;
  sortTrending: boolean;
}

function saveFeedCache(data: FeedCache) {
  try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(data)); } catch { /* quota */ }
}

function loadFeedCache(): FeedCache | null {
  try {
    const raw = sessionStorage.getItem(CACHE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch { return null; }
}

export default function HomePage() {
  const cached = useMemo(() => loadFeedCache(), []);

  const [wallpapers, setWallpapers] = useState<Wallpaper[]>(cached?.wallpapers ?? []);
  const [cursor, setCursor] = useState<number | undefined>(cached?.cursor);
  const [hasMore, setHasMore] = useState(cached?.hasMore ?? false);
  const [loading, setLoading] = useState(!cached);
  const [loadingMore, setLoadingMore] = useState(false);
  const [deviceFilter, setDeviceFilter] = useState(cached?.deviceFilter ?? false);
  const [macFilter, setMacFilter] = useState(cached?.macFilter ?? false);
  const [sortTrending, setSortTrending] = useState(cached?.sortTrending ?? false);
  const restoredRef = useRef(false);
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
    restoredRef.current = false;
    sessionStorage.removeItem(CACHE_KEY);
    setDeviceFilter((p) => {
      if (!p) setMacFilter(false);
      return !p;
    });
  };

  const toggleMacFilter = () => {
    restoredRef.current = false;
    sessionStorage.removeItem(CACHE_KEY);
    setMacFilter((p) => {
      if (!p) setDeviceFilter(false);
      return !p;
    });
  };

  const busyRef = useRef(false);

  const fetchWallpapers = useCallback(async (reset: boolean) => {
    if (!reset && (busyRef.current || !hasMore)) return;
    busyRef.current = true;
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
      busyRef.current = false;
    }
  }, [cursor, screen, deviceFilter, macFilter, sortTrending, hasMore]);

  const sentinelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (cached && !restoredRef.current) {
      restoredRef.current = true;
      requestAnimationFrame(() => {
        window.scrollTo(0, cached.scrollY);
      });
      return;
    }
    fetchWallpapers(true);
  }, [deviceFilter, macFilter, sortTrending]);

  useEffect(() => {
    const saveScroll = () => {
      saveFeedCache({
        wallpapers, cursor, hasMore,
        scrollY: window.scrollY,
        deviceFilter, macFilter, sortTrending,
      });
    };
    window.addEventListener('scroll', saveScroll, { passive: true });
    return () => window.removeEventListener('scroll', saveScroll);
  }, [wallpapers, cursor, hasMore, deviceFilter, macFilter, sortTrending]);

  useEffect(() => {
    const el = sentinelRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) fetchWallpapers(false);
      },
      { rootMargin: '200px' },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [fetchWallpapers]);

  const filterPill = (active: boolean, activeClass: string, inactiveClass: string) =>
    active ? activeClass : inactiveClass;

  const SIZE_KEYS: SizeMode[] = ['sm', 'md', 'lg'];

  return (
    <div className="px-6 py-4">
      {/* Control bar */}
      <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
        {/* Left: filter pills */}
        <div className="flex items-center gap-2">
          <button
            onClick={() => { restoredRef.current = false; sessionStorage.removeItem(CACHE_KEY); setSortTrending((p) => !p); }}
            className={`flex items-center gap-2 px-5 py-2.5 text-sm font-semibold rounded-full transition-colors shadow-sm ${
              filterPill(
                sortTrending,
                'bg-ws-purple text-white',
                'bg-ws-purple text-white',
              )
            }`}
          >
            <AiOutlineStar size={16} />
            Popular
          </button>
          <button
            onClick={() => { restoredRef.current = false; sessionStorage.removeItem(CACHE_KEY); if (sortTrending) setSortTrending(false); }}
            className={`flex items-center gap-2 px-5 py-2.5 text-sm font-semibold rounded-full border transition-colors ${
              !sortTrending
                ? 'bg-ws-purple text-white border-ws-purple shadow-sm'
                : 'text-slate-600 dark:text-ws-dark-muted border-ws-border dark:border-white/10 dark:bg-ws-dark-card hover:bg-ws-bg dark:hover:bg-white/5'
            }`}
          >
            <AiOutlineClockCircle size={16} />
            Recent
          </button>

          <button
            onClick={toggleDeviceFilter}
            title={deviceFilter ? `${screen.width}×${screen.height}` : 'Filter for your device'}
            className={`flex items-center gap-2 px-5 py-2.5 text-sm font-semibold rounded-full border transition-colors ${
              deviceFilter
                ? 'bg-ws-purple text-white border-ws-purple shadow-sm'
                : 'text-slate-600 dark:text-ws-dark-muted border-ws-border dark:border-white/10 dark:bg-ws-dark-card hover:bg-ws-bg dark:hover:bg-white/5'
            }`}
          >
            <MdDevices size={16} />
            <span className="hidden sm:inline">{deviceFilter ? `${screen.width}×${screen.height}` : 'Device'}</span>
          </button>

          {isMac && (
            <button
              onClick={toggleMacFilter}
              className={`flex items-center gap-2 px-5 py-2.5 text-sm font-semibold rounded-full border transition-colors ${
                macFilter
                  ? 'bg-ws-purple text-white border-ws-purple shadow-sm'
                  : 'text-slate-600 dark:text-ws-dark-muted border-ws-border dark:border-white/10 dark:bg-ws-dark-card hover:bg-ws-bg dark:hover:bg-white/5'
              }`}
            >
              <AppleIcon size={14} />
              <span className="hidden sm:inline">macOS</span>
            </button>
          )}
        </div>

        {/* Right: view + size toggles */}
        <div className="flex items-center gap-3">
          {/* View toggle */}
          <div className="flex items-center p-1 bg-ws-purple-light dark:bg-ws-dark-card rounded-lg">
            <button
              onClick={() => handleViewChange('justified')}
              className={`p-2 rounded-md transition-colors ${
                viewMode === 'justified'
                  ? 'bg-ws-purple text-white shadow-sm'
                  : 'text-ws-purple dark:text-ws-dark-muted hover:bg-indigo-50 dark:hover:bg-white/5'
              }`}
              title="Grid"
            >
              <AiOutlineAppstore size={16} />
            </button>
            <button
              onClick={() => handleViewChange('grid')}
              className={`p-2 rounded-md transition-colors ${
                viewMode === 'grid'
                  ? 'bg-ws-purple text-white shadow-sm'
                  : 'text-ws-purple dark:text-ws-dark-muted hover:bg-indigo-50 dark:hover:bg-white/5'
              }`}
              title="List"
            >
              <AiOutlineBars size={16} />
            </button>
          </div>

          {/* Size toggle */}
          <div className="flex items-center h-10 bg-ws-purple-light dark:bg-ws-dark-card rounded-lg overflow-hidden">
            {SIZE_KEYS.map((k) => (
              <button
                key={k}
                onClick={() => handleSizeChange(k)}
                className={`px-4 text-sm font-bold transition-colors ${
                  sizeMode === k
                    ? 'bg-ws-purple text-white shadow-sm'
                    : 'text-ws-purple dark:text-ws-dark-muted hover:bg-ws-purple/10 dark:hover:bg-white/5'
                }`}
              >
                {k.toUpperCase()}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Gallery */}
      {loading ? (
        <SkeletonGrid />
      ) : (
        <>
          <WallpaperGrid wallpapers={wallpapers} viewMode={viewMode} sizeMode={sizeMode} />
          {hasMore && (
            <div ref={sentinelRef} className="flex justify-center py-8">
              {loadingMore && (
                <div className="w-6 h-6 border-2 border-slate-200 dark:border-ws-dark-card border-t-ws-purple rounded-full animate-spin" />
              )}
            </div>
          )}
        </>
      )}
    </div>
  );
}
