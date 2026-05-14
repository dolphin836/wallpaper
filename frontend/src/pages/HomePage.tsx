import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Link } from 'react-router-dom';
import { MdDevices } from 'react-icons/md';
import { AiOutlineAppstore, AiOutlineBars } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers, getForYouWallpapers } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import { SIZE_HEIGHTS } from '../components/WallpaperGrid';
import type { ViewMode, SizeMode } from '../components/WallpaperGrid';
import PageMeta from '../components/PageMeta';

function getScreenResolution() {
  const dpr = window.devicePixelRatio || 1;
  return {
    width: Math.round(window.screen.width * dpr),
    height: Math.round(window.screen.height * dpr),
  };
}

const GRID_BREAKPOINT_COLS: Record<SizeMode, [number, number, number, number]> = {
  lg: [2, 2, 3, 4],
  md: [3, 4, 5, 6],
  sm: [4, 6, 8, 10],
};

function calculatePageSize(
  viewMode: ViewMode,
  sizeMode: SizeMode,
  screens = 4,
): number {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const containerWidth = vw - 48;
  const gap = 16;

  let count: number;

  if (viewMode === 'justified') {
    const rowHeight = SIZE_HEIGHTS[sizeMode];
    const avgAspect = 1.6;
    const itemsPerRow = Math.max(1, Math.floor(containerWidth / (rowHeight * avgAspect + gap)));
    const rowsPerScreen = Math.max(1, Math.floor(vh / (rowHeight + gap)));
    count = itemsPerRow * rowsPerScreen * screens;
  } else {
    const bp = GRID_BREAKPOINT_COLS[sizeMode];
    let cols: number;
    if (containerWidth >= 1024) cols = bp[3];
    else if (containerWidth >= 768) cols = bp[2];
    else if (containerWidth >= 640) cols = bp[1];
    else cols = bp[0];

    const cardWidth = (containerWidth - gap * (cols - 1)) / cols;
    const cardHeight = cardWidth * 0.75;
    const rowsPerScreen = Math.max(1, Math.floor(vh / (cardHeight + gap)));
    count = cols * rowsPerScreen * screens;
  }

  return Math.max(20, Math.min(200, count));
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

export default function HomePage() {
  const { isAuthenticated, user } = useAuthStore();

  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [deviceFilter, setDeviceFilter] = useState(false);
  const [macFilter, setMacFilter] = useState(false);
  const [sortTrending, setSortTrending] = useState(false);
  const [sortOpen, setSortOpen] = useState(false);
  const [feed, setFeed] = useState<'latest' | 'for_you'>('latest');
  const sortRef = useRef<HTMLDivElement>(null);
  const cursorRef = useRef(cursor);
  const hasMoreRef = useRef(hasMore);
  cursorRef.current = cursor;
  hasMoreRef.current = hasMore;
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    return (localStorage.getItem('wallpaper_view_mode') as ViewMode) || 'justified';
  });
  const [sizeMode, setSizeMode] = useState<SizeMode>(() => {
    return (localStorage.getItem('wallpaper_size_mode') as SizeMode) || 'md';
  });
  const viewModeRef = useRef(viewMode);
  const sizeModeRef = useRef(sizeMode);
  viewModeRef.current = viewMode;
  sizeModeRef.current = sizeMode;

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

  const busyRef = useRef(false);
  const [staggerFrom, setStaggerFrom] = useState(0);
  const [loadingMore, setLoadingMore] = useState(false);

  const fetchWallpapers = useCallback(async (reset: boolean) => {
    if (!reset && (busyRef.current || !hasMoreRef.current)) return;
    busyRef.current = true;
    if (reset) setLoading(true);
    else setLoadingMore(true);
    try {
      // For-you is a single-shot top-N feed (no cursor). When it returns
      // empty, fall back to latest so cold-start users still see content.
      if (feed === 'for_you') {
        if (!reset) return;
        const res = await getForYouWallpapers(30);
        const items = res.data.data || [];
        if (items.length === 0) {
          setFeed('latest');
          return;
        }
        setStaggerFrom(0);
        setWallpapers(items);
        setCursor(undefined);
        setHasMore(false);
        return;
      }
      const params: Parameters<typeof getWallpapers>[0] = {
        cursor: reset ? undefined : cursorRef.current,
        limit: calculatePageSize(viewModeRef.current, sizeModeRef.current),
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
      setWallpapers((prev) => {
        const base = reset ? [] : prev;
        setStaggerFrom(base.length);
        return [...base, ...items];
      });
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load wallpapers');
    } finally {
      if (reset) setLoading(false);
      else setLoadingMore(false);
      busyRef.current = false;
    }
  }, [screen, deviceFilter, macFilter, sortTrending, feed]);

  // Holds latest fetchWallpapers so the (stable) sentinel ref-callback always calls the latest closure.
  const fetchWallpapersRef = useRef(fetchWallpapers);
  fetchWallpapersRef.current = fetchWallpapers;

  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);

  // Ref callback: attaches/recreates the IntersectionObserver whenever the sentinel mounts.
  // Bug fix: the previous useEffect-based attach ran when the sentinel was still null
  // (initial load shows <SkeletonGrid/>, sentinel hadn't mounted yet) and never re-ran when
  // loading flipped to false, so autoload was permanently broken on first paint.
  const attachSentinel = useCallback((el: HTMLDivElement | null) => {
    if (observerRef.current) {
      observerRef.current.disconnect();
      observerRef.current = null;
    }
    sentinelRef.current = el;
    if (!el) return;
    // Trigger when the sentinel is within ~2 screens of the viewport — matches the
    // "start loading when the 3rd screen of a 4-screen page enters viewport" intent.
    const obs = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) fetchWallpapersRef.current(false);
      },
      { rootMargin: `${window.innerHeight * 2}px 0px` },
    );
    obs.observe(el);
    observerRef.current = obs;
  }, []);

  useEffect(() => {
    fetchWallpapers(true);
  }, [deviceFilter, macFilter, sortTrending, feed]);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (sortRef.current && !sortRef.current.contains(e.target as Node)) setSortOpen(false);
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // After each fetch the list grows, but IntersectionObserver only fires on *state change*.
  // If the just-loaded page didn't push the sentinel out of the trigger zone (e.g. page came
  // back smaller than expected, or the viewport is much taller than the page), the observer
  // sits silently until the user scrolls. So we manually re-check after every length change.
  useEffect(() => {
    if (loading || loadingMore || !hasMore) return;
    const id = requestAnimationFrame(() => {
      const el = sentinelRef.current;
      if (!el || busyRef.current || !hasMoreRef.current) return;
      const rect = el.getBoundingClientRect();
      // Trigger zone = viewport bottom + rootMargin = vh + 2vh = 3vh from viewport top.
      if (rect.top <= window.innerHeight * 3) {
        fetchWallpapersRef.current(false);
      }
    });
    return () => cancelAnimationFrame(id);
  }, [wallpapers.length, loading, loadingMore, hasMore]);

  const SIZE_KEYS: SizeMode[] = ['sm', 'md', 'lg'];

  return (
    <div className="px-6 py-4">
      <PageMeta
        title="Discover"
        description="Browse and download community-uploaded HD and 4K wallpapers — phone, desktop, and macOS dynamic wallpapers, sorted by latest and popular."
      />
      {/* Control bar */}
      <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
        {/* Left: filters */}
        <div className="flex items-center gap-2">
          {isAuthenticated && (
            <div className="flex items-center bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-full p-0.5 mr-1">
              <button
                onClick={() => setFeed('latest')}
                className={`px-4 py-2 text-sm font-semibold rounded-full transition-colors ${
                  feed === 'latest' ? 'bg-white dark:bg-white/10 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-ws-dark-muted'
                }`}
              >
                Latest
              </button>
              <button
                onClick={() => setFeed('for_you')}
                className={`px-4 py-2 text-sm font-semibold rounded-full transition-colors ${
                  feed === 'for_you' ? 'bg-white dark:bg-white/10 text-slate-900 dark:text-white shadow-sm' : 'text-slate-500 dark:text-ws-dark-muted'
                }`}
              >
                For You
              </button>
            </div>
          )}
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
            <span className="hidden sm:inline">{deviceFilter ? `${screen.width}×${screen.height}` : 'My Device'}</span>
          </button>

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
        </div>

        {/* Right: view + size + sort.
            flex-wrap + min-w-0 so the three sub-controls re-flow on narrow
            viewports — without these, on a ~390px phone the combined
            ~384px content overflows the px-6 page wrapper (~342px content
            area) and pushes the body wider than the viewport. */}
        <div className="flex flex-wrap items-center gap-4 min-w-0">
          {/* View toggle */}
          <div className="flex items-center p-1 bg-ws-bg dark:bg-ws-dark-card rounded-lg border border-ws-border dark:border-white/10">
            <button
              onClick={() => handleViewChange('justified')}
              className={`p-2 rounded-md transition-colors ${
                viewMode === 'justified'
                  ? 'bg-ws-purple text-white shadow-sm'
                  : 'text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple'
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
                  : 'text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple'
              }`}
              title="List"
            >
              <AiOutlineBars size={16} />
            </button>
          </div>

          {/* Size toggle */}
          <div className="flex items-center h-10 bg-ws-bg dark:bg-ws-dark-card rounded-lg overflow-hidden border border-ws-border dark:border-white/10">
            {SIZE_KEYS.map((k) => (
              <button
                key={k}
                onClick={() => handleSizeChange(k)}
                className={`px-4 h-full text-sm font-bold transition-colors ${
                  sizeMode === k
                    ? 'bg-ws-purple text-white'
                    : 'text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple dark:hover:text-white'
                }`}
              >
                {k.toUpperCase()}
              </button>
            ))}
          </div>

          {/* Sort dropdown */}
          <div className="relative" ref={sortRef}>
            <button
              onClick={() => setSortOpen((p) => !p)}
              className="flex items-center gap-5 px-4 py-2.5 bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 text-sm font-medium text-slate-700 dark:text-ws-dark-muted rounded-lg hover:bg-slate-50 dark:hover:bg-white/5 transition-colors"
            >
              {sortTrending ? 'Trending' : 'Latest'}
              <svg className="h-4 w-4 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M19 9l-7 7-7-7" strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} /></svg>
            </button>
            {sortOpen && (
              <div className="absolute right-0 mt-1 w-36 bg-white dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-lg shadow-lg z-10 py-1">
                <button
                  onClick={() => { if (sortTrending) setSortTrending(false); setSortOpen(false); }}
                  className={`w-full text-left px-4 py-2 text-sm transition-colors ${!sortTrending ? 'text-ws-purple font-semibold bg-ws-purple-light dark:bg-ws-dark-active' : 'text-slate-700 dark:text-ws-dark-muted hover:bg-ws-bg dark:hover:bg-white/5'}`}
                >
                  Latest
                </button>
                <button
                  onClick={() => { if (!sortTrending) setSortTrending(true); setSortOpen(false); }}
                  className={`w-full text-left px-4 py-2 text-sm transition-colors ${sortTrending ? 'text-ws-purple font-semibold bg-ws-purple-light dark:bg-ws-dark-active' : 'text-slate-700 dark:text-ws-dark-muted hover:bg-ws-bg dark:hover:bg-white/5'}`}
                >
                  Trending
                </button>
              </div>
            )}
          </div>
        </div>
      </div>

      {isAuthenticated && user && user.coins <= 0 && (
        <Link
          to="/upload"
          className="flex items-center gap-3 mb-5 px-5 py-3 rounded-xl bg-gradient-to-r from-amber-50 to-yellow-50 dark:from-amber-900/10 dark:to-yellow-900/5 border border-amber-200/50 dark:border-amber-700/20 hover:border-amber-300 dark:hover:border-amber-600/30 transition-colors group"
        >
          <span className="text-lg">✨</span>
          <span className="text-sm text-amber-800 dark:text-amber-300">
            You're out of coins! Share your wallpapers with the community to earn coins and keep downloading.
          </span>
          <span className="ml-auto text-xs font-semibold text-amber-600 dark:text-amber-400 group-hover:text-amber-700 dark:group-hover:text-amber-300 whitespace-nowrap">
            Upload now &rarr;
          </span>
        </Link>
      )}

      {/* Gallery */}
      {loading ? (
        <SkeletonGrid />
      ) : (
        <>
          <WallpaperGrid wallpapers={wallpapers} viewMode={viewMode} sizeMode={sizeMode} staggerFrom={staggerFrom} />
          <div ref={attachSentinel} className="flex justify-center py-10">
            {hasMore && (
              <button
                onClick={() => fetchWallpapers(false)}
                disabled={loadingMore}
                className="px-6 py-2 text-sm font-medium rounded-full border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:bg-slate-50 dark:hover:bg-white/5 transition-colors disabled:opacity-50"
              >
                {loadingMore ? (
                  <span className="flex items-center gap-2">
                    <span className="w-3.5 h-3.5 border-2 border-slate-200 dark:border-white/10 border-t-ws-purple rounded-full animate-spin" />
                    Loading...
                  </span>
                ) : (
                  'Load more'
                )}
              </button>
            )}
            {!hasMore && wallpapers.length > 0 && (
              <span className="text-xs text-ws-muted/60 dark:text-ws-dark-muted/40">You've reached the end</span>
            )}
          </div>
        </>
      )}
    </div>
  );
}
