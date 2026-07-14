import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import FeedFooter, { type FooterState } from '../components/FeedFooter';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers, getForYouWallpapers } from '../api';
import { useCategories } from '../hooks/useCategories';
import { useAuthStore } from '../store/auth';
import type { SizeMode } from '../components/WallpaperGrid';
import DeviceFloatingWall from '../components/DeviceFloatingWall';
import { useCurrentDevice } from '../hooks/useCurrentDevice';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';

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

function calculatePageSize(sizeMode: SizeMode, screens = 5): number {
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const containerWidth = vw - 48;
  const gap = 16;
  const bp = GRID_BREAKPOINT_COLS[sizeMode];
  let cols: number;
  if (containerWidth >= 1024) cols = bp[3];
  else if (containerWidth >= 768) cols = bp[2];
  else if (containerWidth >= 640) cols = bp[1];
  else cols = bp[0];
  const cardWidth = (containerWidth - gap * (cols - 1)) / cols;
  const cardHeight = cardWidth * 0.75;
  const rowsPerScreen = Math.max(1, Math.floor(vh / (cardHeight + gap)));
  const count = cols * rowsPerScreen * screens;

  // 40 = ~1 row of tiles + buffer for the floating-wall preview
  // slot. Ceiling 100 dodges the backend service-layer clamp
  // (anything > 100 there gets reset to the default 20 — the
  // exact symptom of the "All shows only 20" report).
  return Math.max(40, Math.min(100, count));
}

const isMac = /Macintosh|Mac OS X/i.test(navigator.userAgent);

// Single discovery filter. Each option fully specifies *what* gets fetched
// and *how* it's sorted — there is no separate sort toggle.
type FilterMode = 'latest' | 'trending' | 'for_you' | 'my_device' | 'live' | 'ai';

// Visible labels live in the `browse` namespace; this maps each mode
// (the API-facing value, untranslated) onto its translation key.
const FILTER_LABEL_KEYS: Record<FilterMode, string> = {
  latest:    'discover.filterLatest',
  trending:  'discover.filterTrending',
  for_you:   'discover.filterForYou',
  my_device: 'discover.filterMyDevice',
  live:      'discover.filterLive',
  ai:        'discover.filterAi',
};

function SkeletonRows({
  sizeMode,
  device,
}: { sizeMode: SizeMode; device: { width: number; height: number; platform: string } | null }) {
  // Floating-wall-shaped skeleton: first cell mimics the glass
  // mockup card spanning 2×2, the rest use the device's actual
  // aspect so the placeholder footprint matches what's coming.
  const bp = GRID_BREAKPOINT_COLS[sizeMode];
  const count = bp[3] * 4;
  const cols =
    sizeMode === 'lg' ? 'grid-cols-1 sm:grid-cols-2 md:grid-cols-2 lg:grid-cols-3'
    : sizeMode === 'md' ? 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5'
    : 'grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8';

  const aspect = device ? `${device.width || 16} / ${device.height || 9}` : '16 / 9';
  const previewAspect = device
    ? `${(device.width || 16) * 2} / ${(device.height || 9) * 2}`
    : '32 / 18';
  return (
    <div className={`grid gap-3 ${cols}`}>
      <div
        className="dev-preview-skel"
        style={{
          gridColumn: 'span 2',
          gridRow: 'span 2',
          aspectRatio: previewAspect,
        }}
        aria-hidden
      >
        <div className="dev-preview-skel-mockup skeleton-card" />
        <div className="dev-preview-skel-toggles">
          <span className="skeleton-card" />
          <span className="skeleton-card" />
          <span className="skeleton-card" />
        </div>
      </div>
      {Array.from({ length: Math.max(0, count - 4) }).map((_, i) => (
        <div
          key={i}
          className="dev-spec-card skeleton-card"
          style={{
            aspectRatio: aspect,
            animationDelay: `${i * 30}ms`,
          }}
        />
      ))}
    </div>
  );
}

// FeedFooter moved to components/FeedFooter.tsx — shared with the
// DeviceWallpapersPage infinite-scroll feed. Same loading / retry /
// end vocabulary, same CSS.

// Back-to-top floating pill. Pinned to the right edge of the centered
// content column (max-w 1600px) — not the viewport edge — at 100px
// from the visible top. Fades in once the user crosses into the
// second screen and smooth-scrolls back to the top when clicked.
//
// IMPORTANT: portaled to document.body. Layout's <div className=
// "animate-route-in"> applies `transform: translateY(0)` as the final
// keyframe (with animation-fill-mode: both, the transform stays
// computed after the animation ends). Any non-`none` transform on
// an ancestor makes that ancestor the containing block for fixed
// descendants — so without the portal, top:100px would be measured
// from the route-in div (which scrolls with the page), not from the
// viewport, and the button would scroll off-screen with the content.
function BackToTop() {
  const { t } = useTranslation('browse');
  const [show, setShow] = useState(false);
  const [mounted, setMounted] = useState(false);
  useEffect(() => { setMounted(true); }, []);
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
  if (!mounted) return null;
  return createPortal(
    <button
      type="button"
      aria-label={t('discover.backToTop')}
      onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
      className={`back-to-top${show ? ' is-visible' : ''}`}
    >
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor"
        strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
        <polyline points="6 14 12 8 18 14" />
      </svg>
    </button>,
    document.body,
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
  const { t } = useTranslation('browse');
  // For-you is only meaningful for signed-in users — hide it for guests
  // so the dropdown doesn't surface an option that immediately falls
  // back to Latest.
  const options: FilterMode[] = p.isAuthenticated
    ? ['latest', 'trending', 'for_you', 'my_device', 'live', 'ai']
    : ['latest', 'trending', 'my_device', 'live', 'ai'];

  return (
    <div className="relative" ref={p.ddRef}>
      <button
        onClick={() => p.setOpen(!p.open)}
        className="inline-flex items-center gap-3 h-8 px-3.5 rounded-lg bg-paper-2 border border-hair text-[12px] text-ink-2"
      >
        <span className="mono text-[10px] tracking-[0.1em] text-muted">{t('discover.filterKicker')}</span>
        {t(FILTER_LABEL_KEYS[p.mode])}
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M5 9l7 7 7-7" strokeLinecap="round" strokeLinejoin="round" /></svg>
      </button>
      {p.open && (
        <div className="absolute right-0 mt-1 w-44 bg-paper border border-hair rounded-lg shadow-lg z-20 py-1">
          {options.map((opt) => (
            <button
              key={opt}
              onClick={() => { p.setMode(opt); p.setOpen(false); }}
              className={`w-full text-left px-4 py-2 text-[13px] transition-colors ${p.mode === opt ? 'text-accent-ink bg-accent-soft font-medium' : 'text-ink-2 hover:bg-paper-2'}`}
            >{t(FILTER_LABEL_KEYS[opt])}</button>
          ))}
        </div>
      )}
    </div>
  );
}

interface SizeControlsProps {
  sizeMode: SizeMode;
  onSize: (s: SizeMode) => void;
}

function SizeControls(p: SizeControlsProps) {
  const { t } = useTranslation('browse');
  return (
    <>
      <div className="inline-flex items-center p-[3px] gap-0.5 bg-paper-2 border border-hair rounded-lg">
        {(['md', 'lg'] as SizeMode[]).map((k) => {
          const on = p.sizeMode === k;
          return (
            <button
              key={k}
              onClick={() => p.onSize(k)}
              title={t('discover.sizeTitle', { size: k.toUpperCase() })}
              className={`min-w-[30px] h-[26px] px-[9px] rounded-[5px] mono text-[11px] tracking-[0.04em] transition-colors ${on ? 'bg-ink text-paper font-semibold shadow-[0_1px_2px_rgba(0,0,0,0.18)]' : 'text-muted font-medium'}`}
            >{k.toUpperCase()}</button>
          );
        })}
      </div>
    </>
  );
}

export default function DiscoverPage() {
  const { t } = useTranslation('browse');
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
    const allowed: FilterMode[] = ['latest', 'trending', 'for_you', 'my_device', 'live', 'ai'];
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
  // Categories come from the shared TanStack Query cache; loading still
  // drives the chip-strip skeleton placeholders after "All" so the strip
  // doesn't start collapsed on a cold cache.
  const { categories, loading: categoriesLoading } = useCategories();
  const currentCategory = useMemo(
    () => (categorySlug ? categories.find((c) => c.slug === categorySlug) : undefined),
    [categories, categorySlug],
  );
  const categoryFilter: number | null = currentCategory ? currentCategory.id : null;
  const cursorRef = useRef(cursor);
  const hasMoreRef = useRef(hasMore);
  const wallpaperIdsRef = useRef<Set<number>>(new Set());
  const [sizeMode, setSizeMode] = useState<SizeMode>(() => {
    // SM was retired from the UI; saved 'sm' from older sessions
    // silently bumps to 'md'. New default is 'lg'.
    const saved = localStorage.getItem('wallpaper_size_mode') as SizeMode | null;
    if (saved === 'md' || saved === 'lg') return saved;
    if (saved === 'sm') return 'md';
    return 'lg';
  });
  const sizeModeRef = useRef(sizeMode);

  const screen = useMemo(() => getScreenResolution(), []);

  // Detect the visitor's actual device profile so the floating-
  // wall layout can size itself to *their* screen aspect.
  // Synthetic fallback from window.screen ensures device is never
  // null after first render, so we always run the floating wall.
  const { device: currentDevice } = useCurrentDevice();

  const handleSizeChange = (size: SizeMode) => {
    sizeModeRef.current = size;
    setSizeMode(size);
    localStorage.setItem('wallpaper_size_mode', size);
  };

  const busyRef = useRef(false);
  const [, setStaggerFrom] = useState(0);
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
        wallpaperIdsRef.current = new Set(items.map((w) => w.id));
        setCursor(undefined);
        cursorRef.current = undefined;
        setHasMore(false);
        hasMoreRef.current = false;
        setLoadError(false);
        return;
      }
      const params: Parameters<typeof getWallpapers>[0] = {
        cursor: reset ? undefined : cursorRef.current,
        limit: calculatePageSize(sizeModeRef.current),
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
        case 'live':
          // Live = Mac dynamic (is_dynamic) ∪ video. Backend's dynamic_only
          // covers both since the SQL filter was widened to include
          // file_type LIKE 'video/%'.
          params.dynamic_only = true;
          break;
        case 'ai':
          params.ai_only = true;
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
      // Compute dedupe synchronously instead of mutating a local variable
      // inside React's state updater. More importantly, publish the new
      // cursor refs before busyRef is unlocked in finally: the observer can
      // fire between the response and React's next render, and must never
      // request the just-finished cursor again.
      const seen = reset ? new Set<number>() : wallpaperIdsRef.current;
      const freshItems = reset ? items : items.filter((w) => !seen.has(w.id));
      wallpaperIdsRef.current = reset
        ? new Set(items.map((w) => w.id))
        : new Set([...seen, ...freshItems.map((w) => w.id)]);
      setWallpapers((prev) => {
        const base = reset ? [] : prev;
        setStaggerFrom(base.length);
        return reset ? items : [...base, ...freshItems];
      });
      const cursorStalled = !reset && next_cursor === cursorRef.current;
      const canLoadMore = has_more && !cursorStalled && (reset || freshItems.length > 0);
      cursorRef.current = next_cursor || undefined;
      hasMoreRef.current = canLoadMore;
      setCursor(next_cursor || undefined);
      setHasMore(canLoadMore);
      setLoadError(false);
    } catch {
      // Reset-time failures still surface a toast (they're catastrophic — no
      // content at all on the page). Pagination failures are handled by the
      // FeedFooter retry CTA instead of a transient toast.
      if (reset) toast.error(t('discover.loadFailed'));
      setLoadError(true);
    } finally {
      if (reset) setLoading(false);
      else setLoadingMore(false);
      busyRef.current = false;
    }
  }, [screen, filterMode, categoryFilter, t]);

  // Holds latest fetchWallpapers so the (stable) sentinel ref-callback always calls the latest closure.
  const fetchWallpapersRef = useRef(fetchWallpapers);
  useEffect(() => {
    fetchWallpapersRef.current = fetchWallpapers;
  }, [fetchWallpapers]);

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
      { rootMargin: `${window.innerHeight * 4}px 0px` },
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
      // Trigger zone = viewport bottom + rootMargin = vh + 4vh = 5vh from viewport top.
      if (rect.top <= window.innerHeight * 5) {
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
        title={currentCategory ? t('discover.categoryMetaTitle', { name: currentCategory.name }) : t('discover.metaTitle')}
        description={
          currentCategory
            ? t('discover.categoryMetaDescription', { name: currentCategory.name, nameLower: currentCategory.name.toLowerCase() })
            : t('discover.metaDescription')
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
                label={t('discover.allCategories')}
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
            <SizeControls
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
              {t('discover.outOfCoins')}
            </span>
            <span className="ml-auto mono text-[10px] tracking-[0.12em] uppercase font-semibold text-accent group-hover:text-accent-ink whitespace-nowrap">
              {t('discover.uploadNow')}
            </span>
          </Link>
        )}

        {loading ? (
          <SkeletonRows sizeMode={sizeMode} device={currentDevice} />
        ) : loadError && wallpapers.length === 0 ? (
          <ErrorState />
        ) : currentDevice ? (
          <>
            <DeviceFloatingWall
              device={currentDevice}
              wallpapers={wallpapers}
              // Track the floating wall's featured (hovered) tile
              // so the page-mesh palette swaps to its dominant
              // colour. Old tile-cell event-delegation no longer
              // applies — the floating-wall tiles are .dev-spec-
              // card, not .tile-cell.
              onFeatureChange={(wp) => applyPalette(wp?.color_palette)}
              // Whenever there's more to load, reserve a few rows
              // of skeleton tiles at the bottom of the wall. They
              // soak up fast scrolling so the preview's follow
              // never outruns the rendered content, and they
              // surface a continuous "more coming" cue inside
              // the grid. Belt-and-braces fires the fetch as the
              // user gets close; tiles slot into the pending
              // positions seamlessly when the response lands.
              pendingCount={hasMore ? 24 : 0}
              colsForWidth={(w) => {
                if (sizeMode === 'lg') {
                  if (w >= 1500) return 4;
                  if (w >= 1000) return 3;
                  return 2;
                }
                if (w >= 1700) return 5;
                if (w >= 1100) return 4;
                if (w >= 760)  return 3;
                return 2;
              }}
            />
            <div ref={attachSentinel} />
            <FeedFooter
              state={footerState}
              count={wallpapers.length}
              onRetry={() => fetchWallpapers(true)}
            />
          </>
        ) : null}
      </main>
      </div>
      <BackToTop />
    </div>
  );
}
