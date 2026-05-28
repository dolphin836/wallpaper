import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { AiOutlineAppstore, AiOutlineBars, AiOutlineReload } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { Wallpaper, Category } from '../types';
import { getWallpapers, getForYouWallpapers, getCategories } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import { SIZE_HEIGHTS, SALON_ROW_BY_SIZE } from '../components/WallpaperGrid';
import type { ViewMode, SizeMode } from '../components/WallpaperGrid';
import PageMeta from '../components/PageMeta';

function getScreenResolution() {
  const dpr = window.devicePixelRatio || 1;
  return {
    width: Math.round(window.screen.width * dpr),
    height: Math.round(window.screen.height * dpr),
  };
}

// Cols per breakpoint [<640, 640+, 768+, 1024+]. Sized to land roughly at
// the same visual density as the matching Justified row height — Grid LG
// used to read as Justified MD because [2,2,3,4] put 4 tiles across a
// 1500-wide container, each ~363px wide × 242px tall — about equal to
// Justified MD's 260 row height. Each tier is now one column wider in
// tile size (one fewer column on screen).
const GRID_BREAKPOINT_COLS: Record<SizeMode, [number, number, number, number]> = {
  lg: [1, 2, 2, 3],
  md: [2, 3, 4, 5],
  sm: [3, 4, 6, 8],
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

  if (viewMode === 'grid') {
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
  } else if (viewMode === 'salon') {
    // Salon layout: 11-col CSS grid with mixed-span tiles, ~2.7 tiles per
    // pattern row on average. Estimate using the row height and a tile-per-
    // pattern-row coefficient instead of average aspect ratio.
    const rowHeight = SALON_ROW_BY_SIZE[sizeMode];
    const rowsPerScreen = Math.max(1, Math.floor(vh / (rowHeight + 8)));
    // Each "pattern cycle" spans ~5 rows and holds 10 tiles → 2 tiles per row.
    count = Math.round(rowsPerScreen * 2.5 * screens);
  } else {
    // justified (legacy)
    const rowHeight = SIZE_HEIGHTS[sizeMode];
    const avgAspect = 1.6;
    const itemsPerRow = Math.max(1, Math.floor(containerWidth / (rowHeight * avgAspect + gap)));
    const rowsPerScreen = Math.max(1, Math.floor(vh / (rowHeight + gap)));
    count = itemsPerRow * rowsPerScreen * screens;
  }

  return Math.max(20, Math.min(200, count));
}

const isMac = /Macintosh|Mac OS X/i.test(navigator.userAgent);

// Single discovery filter. Each option fully specifies *what* gets fetched
// and *how* it's sorted — there is no separate sort toggle.
type FilterMode = 'latest' | 'trending' | 'for_you' | 'my_device' | 'mac_dynamic' | 'ai' | 'video';

const FILTER_LABELS: Record<FilterMode, string> = {
  latest:      'Latest',
  trending:    'Trending',
  for_you:     'For You',
  my_device:   'My Device',
  mac_dynamic: 'macOS Dynamic',
  ai:          'AI Generated',
  video:       'Video',
};

// Default view mode = 'justified' (justified-layout library, uniform row
// height) — what the page used to ship. 'salon' (mosaic) is implemented in
// WallpaperGrid but no longer surfaced through the toggle; the saved value
// still round-trips so anyone who explicitly picked it before keeps it.
function readSavedViewMode(): ViewMode {
  const raw = localStorage.getItem('wallpaper_view_mode');
  if (raw === 'salon' || raw === 'justified' || raw === 'grid') {
    return raw;
  }
  return 'grid';
}

function SkeletonRows({
  viewMode,
  sizeMode,
  rowHeight = 260,
}: { viewMode: ViewMode; sizeMode: SizeMode; rowHeight?: number }) {
  // Grid mode lays out fixed-aspect cells in a CSS grid — match the real
  // breakpoint counts in GRID_BREAKPOINT_COLS so the skeleton occupies
  // the same footprint at every viewport size.
  if (viewMode === 'grid') {
    const bp = GRID_BREAKPOINT_COLS[sizeMode];
    const count = bp[3] * 2;
    const cols =
      sizeMode === 'lg' ? 'grid-cols-1 sm:grid-cols-2 md:grid-cols-2 lg:grid-cols-3'
      : sizeMode === 'md' ? 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5'
      : 'grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8';
    return (
      <div className={`grid gap-4 ${cols}`}>
        {Array.from({ length: count }).map((_, i) => (
          <div
            key={i}
            className="tile-cell skeleton-card aspect-[3/2]"
            style={{ animationDelay: `${i * 60}ms` }}
          />
        ))}
      </div>
    );
  }
  // Justified / salon — three rows of mixed-width tiles at the target row
  // height. Approximate but reads as "content will land here."
  const rows = [
    [3, 4, 3],
    [2, 3, 3, 3],
    [4, 3, 4],
  ];
  return (
    <div className="flex flex-col gap-4">
      {rows.map((row, ri) => (
        <div key={ri} className="flex gap-4" style={{ height: rowHeight }}>
          {row.map((flex, ci) => (
            <div
              key={ci}
              className="tile-cell skeleton-card"
              style={{ flex, animationDelay: `${(ri * row.length + ci) * 80}ms` }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}

type FooterState = 'idle' | 'loading' | 'retry' | 'end';

function FeedFooter({ state, count, onRetry }: { state: FooterState; count: number; onRetry: () => void }) {
  if (state === 'idle') return null;
  if (state === 'loading') {
    return (
      <div className="feed-foot">
        <span className="feed-spinner" aria-hidden />
        <span className="feed-foot__label">Loading more wallpapers</span>
      </div>
    );
  }
  if (state === 'retry') {
    return (
      <div className="feed-foot">
        <span className="feed-foot__label feed-foot__label--warn">
          Couldn't auto-load · network hiccup
        </span>
        <button className="feed-foot__btn" onClick={onRetry}>
          <AiOutlineReload size={13} />
          Try again
        </button>
      </div>
    );
  }
  // end — no animation, no blinking caret. Just a quiet editorial mark.
  return (
    <div className="feed-foot feed-foot--end">
      <div className="feed-end-mark">
        <em>end</em> of the archive.
      </div>
      <div className="feed-end-count">
        {count.toLocaleString()} wallpapers
      </div>
    </div>
  );
}

// Back-to-top floating pill. Pinned to the right edge of the centered
// content column (max-w 1600px) — not the viewport edge — at 100px
// from the visible top. Fades in once the user crosses into the
// second screen and smooth-scrolls back to the top when clicked.
// Throttled to the rAF beat so scroll handlers don't thrash state.
function BackToTop() {
  const [show, setShow] = useState(false);
  useEffect(() => {
    let ticking = false;
    const onScroll = () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        setShow(window.scrollY > window.innerHeight);
        ticking = false;
      });
    };
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);
  return (
    <button
      type="button"
      aria-label="Back to top"
      onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
      className={`back-to-top${show ? ' is-visible' : ''}`}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor"
        strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <polyline points="6 14 12 8 18 14" />
      </svg>
    </button>
  );
}

function CategoryChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`inline-flex items-center px-4 py-1.5 text-[12px] font-medium rounded-full border whitespace-nowrap transition-colors ${
        active
          ? 'bg-ink text-paper border-ink'
          : 'bg-paper text-ink-2 border-hair hover:border-ink-2 hover:text-ink'
      }`}
    >
      {label}
    </button>
  );
}

// Skeleton chip — varied widths so the strip looks like real category
// names while the API roundtrips, instead of N identical placeholders.
const CATEGORY_SKELETON_WIDTHS = [72, 92, 60, 108, 82, 68, 96, 78];
function CategoryChipSkeleton({ width }: { width: number }) {
  return (
    <span
      aria-hidden
      className="inline-block h-[30px] rounded-full bg-paper-2 border border-hair-soft skeleton-card"
      style={{ width: `${width}px` }}
    />
  );
}

interface FilterDropdownProps {
  mode: FilterMode;
  setMode: (m: FilterMode) => void;
  open: boolean;
  setOpen: (b: boolean) => void;
  ddRef: React.RefObject<HTMLDivElement | null>;
  isAuthenticated: boolean;
}

function FilterDropdown(p: FilterDropdownProps) {
  // For-you is only meaningful for signed-in users — hide it for guests
  // so the dropdown doesn't surface an option that immediately falls
  // back to Latest.
  const options: FilterMode[] = p.isAuthenticated
    ? ['latest', 'trending', 'for_you', 'my_device', 'mac_dynamic', 'ai', 'video']
    : ['latest', 'trending', 'my_device', 'mac_dynamic', 'ai', 'video'];

  return (
    <div className="relative" ref={p.ddRef}>
      <button
        onClick={() => p.setOpen(!p.open)}
        className="inline-flex items-center gap-3 h-8 px-3.5 rounded-lg bg-paper-2 border border-hair text-[12px] text-ink-2"
      >
        <span className="mono text-[10px] tracking-[0.1em] text-muted">FILTER</span>
        {FILTER_LABELS[p.mode]}
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M5 9l7 7 7-7" strokeLinecap="round" strokeLinejoin="round" /></svg>
      </button>
      {p.open && (
        <div className="absolute right-0 mt-1 w-44 bg-paper border border-hair rounded-lg shadow-lg z-20 py-1">
          {options.map((opt) => (
            <button
              key={opt}
              onClick={() => { p.setMode(opt); p.setOpen(false); }}
              className={`w-full text-left px-4 py-2 text-[13px] transition-colors ${p.mode === opt ? 'text-accent-ink bg-accent-soft font-medium' : 'text-ink-2 hover:bg-paper-2'}`}
            >{FILTER_LABELS[opt]}</button>
          ))}
        </div>
      )}
    </div>
  );
}

interface ViewSizeControlsProps {
  viewMode: ViewMode;
  onView: (v: ViewMode) => void;
  sizeMode: SizeMode;
  onSize: (s: SizeMode) => void;
}

function ViewSizeControls(p: ViewSizeControlsProps) {
  return (
    <>
      {/* View toggle — icon + label, icon first. Grid is the editorial
          default (uniform 3:2 cards in a CSS grid); Justified packs by
          the justified-layout library at a uniform row height. Salon
          (mosaic) is no longer surfaced here — saved value still
          round-trips for users who picked it before. */}
      <div className="inline-flex items-center p-[3px] gap-0.5 bg-paper-2 border border-hair rounded-lg">
        <button
          onClick={() => p.onView('grid')}
          title="Grid"
          className={`h-[26px] px-2.5 rounded-[5px] inline-flex items-center gap-1.5 text-[11px] transition-colors ${p.viewMode === 'grid' ? 'bg-ink text-paper' : 'text-muted hover:text-ink-2'}`}
        ><AiOutlineBars size={13} /><span>Grid</span></button>
        <button
          onClick={() => p.onView('justified')}
          title="Justified"
          className={`h-[26px] px-2.5 rounded-[5px] inline-flex items-center gap-1.5 text-[11px] transition-colors ${p.viewMode === 'justified' || p.viewMode === 'salon' ? 'bg-ink text-paper' : 'text-muted hover:text-ink-2'}`}
        ><AiOutlineAppstore size={13} /><span>Justified</span></button>
      </div>
      <div className="inline-flex items-center p-[3px] gap-0.5 bg-paper-2 border border-hair rounded-lg">
        {(['md', 'lg'] as SizeMode[]).map((k) => {
          const on = p.sizeMode === k;
          return (
            <button
              key={k}
              onClick={() => p.onSize(k)}
              title={`Size · ${k.toUpperCase()}`}
              className={`min-w-[30px] h-[26px] px-[9px] rounded-[5px] mono text-[11px] tracking-[0.04em] transition-colors ${on ? 'bg-ink text-paper font-semibold shadow-[0_1px_2px_rgba(0,0,0,0.18)]' : 'text-muted font-medium'}`}
            >{k.toUpperCase()}</button>
          );
        })}
      </div>
    </>
  );
}

export default function DiscoverPage() {
  const { isAuthenticated, user } = useAuthStore();

  // Discover liquid mesh — brand-warm/deep defaults that switch to a
  // hovered wallpaper's palette via event delegation. Setting CSS vars on
  // the scoped root keeps the effect bounded to Discover; other pages
  // don't see these vars.
  const liquidRootRef = useRef<HTMLDivElement | null>(null);
  const applyPalette = useCallback((palette: string | undefined) => {
    const root = liquidRootRef.current;
    if (!root) return;
    if (!palette) {
      // Revert to brand defaults — clearing inline overrides lets the
      // stylesheet's :root / .dark rules take over.
      root.style.removeProperty('--d3-c1');
      root.style.removeProperty('--d3-c2');
      root.style.removeProperty('--d3-c3');
      return;
    }
    const parts = palette.split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length < 3) return;
    root.style.setProperty('--d3-c1', parts[parts.length - 2] || parts[0]);
    root.style.setProperty('--d3-c2', parts[1] || parts[0]);
    root.style.setProperty('--d3-c3', parts[parts.length - 1] || parts[2]);
  }, []);
  // Event-delegated hover: any descendant <a class="tile-cell"
  // data-palette="..."> emits its palette to the mesh, no per-card prop
  // wiring needed. closest() climbs from the hovered DOM node up to the
  // tile root.
  const onTileOver = useCallback((e: React.MouseEvent) => {
    const tile = (e.target as HTMLElement).closest<HTMLElement>('.tile-cell');
    if (tile && tile.dataset.palette) applyPalette(tile.dataset.palette);
  }, [applyPalette]);
  const onTileLeave = useCallback((e: React.MouseEvent) => {
    // Only reset when the pointer actually leaves the tile (not when it
    // crosses between children) — relatedTarget tells us where it went.
    const tile = (e.target as HTMLElement).closest<HTMLElement>('.tile-cell');
    if (!tile) return;
    const next = e.relatedTarget as Node | null;
    if (next && tile.contains(next)) return;
    applyPalette(undefined);
  }, [applyPalette]);

  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  // Unified filter mode replaces the four separate toggles (feed,
  // device, mac, sort). Each option fully describes both the data
  // source and the sort order — see fetchWallpapers below for the
  // mapping to backend params.
  // URL ?filter=<mode> is honored once on mount so deep-links from
  // other pages (e.g. HomePage's "All AI wallpapers →") land on the
  // right filter. We don't sync changes BACK to the URL — the dropdown
  // owns the live state from there on.
  const [filterMode, setFilterMode] = useState<FilterMode>(() => {
    const raw = new URLSearchParams(window.location.search).get('filter');
    const allowed: FilterMode[] = ['latest', 'trending', 'for_you', 'my_device', 'mac_dynamic', 'ai', 'video'];
    return (allowed as string[]).includes(raw || '') ? (raw as FilterMode) : 'latest';
  });
  const [filterOpen, setFilterOpen] = useState(false);
  const filterRef = useRef<HTMLDivElement>(null);
  const [loadError, setLoadError] = useState(false);
  // URL is the source of truth for the category filter — `/` means "All",
  // `/category/:slug` pins to that category. Chip clicks navigate; the
  // categoryFilter id is derived (not state) from the URL slug + the
  // loaded category list.
  const { slug: categorySlug } = useParams<{ slug?: string }>();
  const navigate = useNavigate();
  const [categories, setCategories] = useState<Category[]>([]);
  // Tracks the initial categories fetch so the chip strip can show
  // skeleton placeholders after "All" instead of starting collapsed
  // (it used to be "All" alone for ~300ms, then the rest popped in).
  const [categoriesLoading, setCategoriesLoading] = useState(true);
  useEffect(() => {
    getCategories()
      .then((r) => setCategories(r.data.data || []))
      .catch(() => setCategories([]))
      .finally(() => setCategoriesLoading(false));
  }, []);
  const currentCategory = useMemo(
    () => (categorySlug ? categories.find((c) => c.slug === categorySlug) : undefined),
    [categories, categorySlug],
  );
  const categoryFilter: number | null = currentCategory ? currentCategory.id : null;
  const cursorRef = useRef(cursor);
  const hasMoreRef = useRef(hasMore);
  cursorRef.current = cursor;
  hasMoreRef.current = hasMore;
  const [viewMode, setViewMode] = useState<ViewMode>(readSavedViewMode);
  const [sizeMode, setSizeMode] = useState<SizeMode>(() => {
    // SM was retired from the UI (too small to read; not worth the
    // toggle slot). Saved 'sm' from older sessions silently bumps to
    // 'md' on read so users land on something visible. New default
    // is 'lg' — poster scale fits the editorial Liquid Surface
    // direction better than mid-density.
    const saved = localStorage.getItem('wallpaper_size_mode') as SizeMode | null;
    if (saved === 'md' || saved === 'lg') return saved;
    if (saved === 'sm') return 'md';
    return 'lg';
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
      if (filterMode === 'for_you') {
        if (!reset) return;
        const res = await getForYouWallpapers(30);
        const items = res.data.data || [];
        if (items.length === 0) {
          setFilterMode('latest');
          return;
        }
        setStaggerFrom(0);
        setWallpapers(items);
        setCursor(undefined);
        setHasMore(false);
        setLoadError(false);
        return;
      }
      const params: Parameters<typeof getWallpapers>[0] = {
        cursor: reset ? undefined : cursorRef.current,
        limit: calculatePageSize(viewModeRef.current, sizeModeRef.current),
      };
      switch (filterMode) {
        case 'trending':
          params.sort = 'trending';
          break;
        case 'my_device':
          params.device_width = screen.width;
          params.device_height = screen.height;
          if (isMac) params.include_dynamic = true;
          break;
        case 'mac_dynamic':
          params.dynamic_only = true;
          break;
        case 'ai':
          params.ai_only = true;
          break;
        case 'video':
          params.video_only = true;
          break;
        case 'latest':
          // No special params — default backend behavior is latest first.
          break;
      }
      if (categoryFilter !== null) {
        params.category_id = categoryFilter;
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
      setLoadError(false);
    } catch {
      // Reset-time failures still surface a toast (they're catastrophic — no
      // content at all on the page). Pagination failures are handled by the
      // FeedFooter retry CTA instead of a transient toast.
      if (reset) toast.error('Failed to load wallpapers');
      setLoadError(true);
    } finally {
      if (reset) setLoading(false);
      else setLoadingMore(false);
      busyRef.current = false;
    }
  }, [screen, filterMode, categoryFilter]);

  // Holds latest fetchWallpapers so the (stable) sentinel ref-callback always calls the latest closure.
  const fetchWallpapersRef = useRef(fetchWallpapers);
  fetchWallpapersRef.current = fetchWallpapers;

  const sentinelRef = useRef<HTMLDivElement | null>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);

  // Ref callback: attaches/recreates the IntersectionObserver whenever the sentinel mounts.
  // Bug fix: the previous useEffect-based attach ran when the sentinel was still null
  // (initial load shows the SkeletonRows placeholder, sentinel hadn't mounted yet) and
  // never re-ran when loading flipped to false, so autoload was permanently broken on
  // first paint.
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
  }, [filterMode, categoryFilter]);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (filterRef.current && !filterRef.current.contains(e.target as Node)) setFilterOpen(false);
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

  const footerState: FooterState =
    loadError ? 'retry'
    : loadingMore && hasMore ? 'loading'
    : !hasMore && wallpapers.length > 0 ? 'end'
    : 'idle';

  return (
    <div
      ref={liquidRootRef}
      className="d3-discover min-h-full"
      onMouseOver={onTileOver}
      onMouseOut={onTileLeave}
    >
      <PageMeta
        title={currentCategory ? `${currentCategory.name} wallpapers` : 'Discover'}
        description={
          currentCategory
            ? `${currentCategory.name} wallpapers — community-curated HD, 4K, and macOS dynamic wallpapers in the ${currentCategory.name.toLowerCase()} category. Browse and download for free on Wallpaper Exchange.`
            : 'Browse and download community-uploaded HD and 4K wallpapers — phone, desktop, and macOS dynamic wallpapers, sorted by latest and popular.'
        }
      />
      <div className="d3-discover-mesh" aria-hidden />
      <div className="d3-discover-main">

      {/* Unified discover toolbar. No hard divider lines — the chips +
          buttons carry their own borders, and the feed below has its own
          padding-top, so a horizontal rule here just stacked two parallel
          lines (top-nav border + this one) that read as a sandwich seam.
          Letting the mesh flow through reads cleaner. */}
      <div>
        <div className="max-w-[1600px] mx-auto flex items-center gap-4 px-6 sm:px-10 lg:px-14 pt-5 pb-3">
          <div className="flex-1 min-w-0 overflow-x-auto no-scrollbar">
            <div className="flex items-center gap-2">
              <CategoryChip
                label="All"
                active={categoryFilter === null}
                onClick={() => navigate('/discover')}
              />
              {categoriesLoading
                ? CATEGORY_SKELETON_WIDTHS.map((w, i) => (
                    <CategoryChipSkeleton key={`csk-${i}`} width={w} />
                  ))
                : categories.map((c) => (
                    <CategoryChip
                      key={c.id}
                      label={c.name}
                      active={categoryFilter === c.id}
                      onClick={() => navigate(`/category/${c.slug}`)}
                    />
                  ))}
            </div>
          </div>
          <div className="flex items-center gap-2.5 flex-shrink-0">
            <FilterDropdown
              mode={filterMode}
              setMode={setFilterMode}
              open={filterOpen}
              setOpen={setFilterOpen}
              ddRef={filterRef}
              isAuthenticated={isAuthenticated}
            />
            <ViewSizeControls
              viewMode={viewMode}
              onView={handleViewChange}
              sizeMode={sizeMode}
              onSize={handleSizeChange}
            />
          </div>
        </div>
      </div>

      <main className="max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-8">
        {isAuthenticated && user && user.coins <= 0 && (
          <Link
            to="/upload"
            className="flex items-center gap-3 mb-6 px-5 py-3 rounded-xl bg-accent-soft border border-hair hover:border-accent transition-colors group"
          >
            <span className="text-lg">✨</span>
            <span className="text-sm text-accent-ink">
              You're out of coins. Share your wallpapers with the community to earn more and keep downloading.
            </span>
            <span className="ml-auto mono text-[10px] tracking-[0.12em] uppercase font-semibold text-accent group-hover:text-accent-ink whitespace-nowrap">
              Upload now &rarr;
            </span>
          </Link>
        )}

        {loading ? (
          <SkeletonRows viewMode={viewMode} sizeMode={sizeMode} rowHeight={SIZE_HEIGHTS[sizeMode]} />
        ) : (
          <>
            <WallpaperGrid
              wallpapers={wallpapers}
              viewMode={viewMode}
              sizeMode={sizeMode}
              staggerFrom={staggerFrom}
            />
            <div ref={attachSentinel} />
            <FeedFooter
              state={footerState}
              count={wallpapers.length}
              onRetry={() => fetchWallpapers(false)}
            />
          </>
        )}
      </main>
      </div>
      <BackToTop />
    </div>
  );
}
