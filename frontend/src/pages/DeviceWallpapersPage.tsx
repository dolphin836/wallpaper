import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, Link } from 'react-router-dom';
import type { DeviceProfile, Wallpaper } from '../types';
import { getDeviceBySlug, getWallpapersForDevice } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import FeedFooter, { type FooterState } from '../components/FeedFooter';
import DeviceFloatingWall from '../components/DeviceFloatingWall';

// SEO long-tail landing for one device profile. The route is /wallpapers-for/:slug
// (e.g. /wallpapers-for/iphone-16-pro). Page survives "no matches" gracefully
// — the device spec box + invite-to-upload stays so the URL keeps SEO value
// even before any contributor uploads work that fits this resolution.
export default function DeviceWallpapersPage() {
  const { slug = '' } = useParams<{ slug: string }>();

  const [device, setDevice] = useState<DeviceProfile | null>(null);
  const [wallpaperCount, setWallpaperCount] = useState(0);
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>(undefined);
  const [hasMore, setHasMore] = useState(false);
  const [loadingDevice, setLoadingDevice] = useState(true);
  const [loadingList, setLoadingList] = useState(false);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState(false);
  // Pagination failure state for the infinite-scroll feed. Top-level
  // `error` covers the device fetch; this covers a load-more hiccup so
  // the FeedFooter can offer a Try-again pill.
  const [loadError, setLoadError] = useState(false);
  // Refs to keep IntersectionObserver's callback closure-free.
  const cursorRef = useRef(cursor);
  const hasMoreRef = useRef(hasMore);
  const busyRef = useRef(false);
  cursorRef.current = cursor;
  hasMoreRef.current = hasMore;

  useEffect(() => {
    setLoadingDevice(true);
    setNotFound(false);
    setError(false);
    getDeviceBySlug(slug)
      .then((res) => {
        setDevice(res.data.data.device);
        setWallpaperCount(res.data.data.wallpaper_count);
      })
      .catch((e) => {
        if (e?.response?.status === 404) setNotFound(true);
        else setError(true);
      })
      .finally(() => setLoadingDevice(false));
  }, [slug]);

  const fetchPage = useCallback(async (reset: boolean) => {
    if (!device) return;
    if (!reset && (busyRef.current || !hasMoreRef.current)) return;
    busyRef.current = true;
    setLoadingList(true);
    try {
      const res = await getWallpapersForDevice(slug, {
        cursor: reset ? undefined : cursorRef.current,
        limit: 24,
      });
      const { items, next_cursor, has_more } = res.data.data;
      let appendedFresh = 0;
      setWallpapers((prev) => {
        if (reset) {
          appendedFresh = items.length;
          return items;
        }
        // Defensive dedupe — same shape as Discover. Backend should
        // never repeat ids in a forward scan, but if it ever does the
        // SPA won't render dupes.
        const seen = new Set(prev.map((w) => w.id));
        const fresh = items.filter((w) => !seen.has(w.id));
        appendedFresh = fresh.length;
        return [...prev, ...fresh];
      });
      const cursorStalled = !reset && next_cursor === cursorRef.current;
      setCursor(has_more ? next_cursor : undefined);
      setHasMore(has_more && !cursorStalled && (reset || appendedFresh > 0));
      setLoadError(false);
    } catch {
      setLoadError(true);
    } finally {
      setLoadingList(false);
      busyRef.current = false;
    }
  }, [device, slug]);

  // First page once we've resolved the device.
  useEffect(() => {
    if (device) fetchPage(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [device?.id]);

  // IntersectionObserver — fires fetchPage(false) when the sentinel
  // enters a ~2-screen buffer above the viewport bottom. Re-attaches
  // every time the sentinel ref reaches the DOM (handles the case
  // where loading replaces sentinel with the skeleton placeholder).
  const fetchPageRef = useRef(fetchPage);
  fetchPageRef.current = fetchPage;
  const observerRef = useRef<IntersectionObserver | null>(null);
  const attachSentinel = useCallback((el: HTMLDivElement | null) => {
    if (observerRef.current) {
      observerRef.current.disconnect();
      observerRef.current = null;
    }
    if (!el) return;
    const obs = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting) fetchPageRef.current(false);
      },
      { rootMargin: `${window.innerHeight * 2}px 0px` },
    );
    obs.observe(el);
    observerRef.current = obs;
  }, []);

  // Belt + braces: after a fetch the list grows but the observer
  // only fires on STATE CHANGE; if the new page didn't push the
  // sentinel out of the trigger zone, re-check on the next frame.
  useEffect(() => {
    if (loadingList || !hasMore) return;
    const id = requestAnimationFrame(() => {
      if (busyRef.current || !hasMoreRef.current) return;
      fetchPageRef.current(false);
    });
    return () => cancelAnimationFrame(id);
  }, [wallpapers.length, loadingList, hasMore]);

  // ─── Server / network error ───
  if (error && !device) {
    return (
      <div className="bg-paper text-ink min-h-full">
        <PageMeta title="Couldn't load device" description="Server error" />
        <ErrorState />
      </div>
    );
  }

  // ─── 404 ───
  if (notFound) {
    return (
      <div className="bg-paper text-ink min-h-full">
        <PageMeta title="Device not found" description="We don't have a wallpaper variant set up for that device yet." />
        <div className="px-6 sm:px-10 pt-10 pb-12 max-w-[820px] mx-auto text-center">
          <div className="kicker text-muted">404 · Device not found</div>
          <h1 className="display text-[40px] sm:text-[52px] leading-[0.96] mt-3 tracking-[-0.02em] text-ink">
            We don't have <span className="italic-d">that device</span> yet.
          </h1>
          <p className="text-[14.5px] leading-[1.6] text-ink-2 mt-5 max-w-[520px] mx-auto">
            The device library is curated — if you'd like to see your hardware
            covered, drop us a line at{' '}
            <a className="text-ink underline" href="mailto:hello@wallpaperexchange.com">
              hello@wallpaperexchange.com
            </a>.
          </p>
          <Link
            to="/"
            className="inline-flex items-center mt-6 px-5 py-2.5 rounded-full bg-ink text-paper text-[13px] font-medium no-underline hover:bg-ink-2 transition-colors"
          >
            Browse the archive
          </Link>
        </div>
      </div>
    );
  }

  const deviceAspect = device ? device.width / device.height : 16 / 9;
  // Page mesh palette tracks whichever tile the floating wall has
  // marked as featured (hover-driven inside DeviceFloatingWall).
  // The component fires onFeatureChange whenever it swaps featured
  // tiles, and the effect below stamps the wallpaper's palette/
  // dominant colour onto --d-c1/c2/c3 at the page root.
  const rootRef = useRef<HTMLDivElement | null>(null);
  const [featured, setFeatured] = useState<Wallpaper | null>(null);
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    if (!featured) {
      root.style.removeProperty('--d-c1');
      root.style.removeProperty('--d-c2');
      root.style.removeProperty('--d-c3');
      return;
    }
    const palette = (featured.color_palette || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (palette.length >= 3) {
      root.style.setProperty('--d-c1', palette[0]);
      root.style.setProperty('--d-c2', palette[Math.floor(palette.length / 2)]);
      root.style.setProperty('--d-c3', palette[palette.length - 1]);
    } else if (featured.dominant_color) {
      root.style.setProperty('--d-c1', featured.dominant_color);
      root.style.setProperty('--d-c2', featured.dominant_color);
      root.style.setProperty('--d-c3', featured.dominant_color);
    }
  }, [featured?.id, featured?.color_palette, featured?.dominant_color]);


  return (
    <div ref={rootRef} className="devices-page min-h-full">
      <div className="devices-mesh" aria-hidden />
      <PageMeta
        title={device ? `${device.name} Wallpapers — ${device.width} × ${device.height} pixel-perfect downloads` : 'Wallpapers'}
        description={
          device
            ? `Browse ${wallpaperCount} wallpapers cropped for the ${device.name}'s ${device.width} × ${device.height} display. Free, pixel-perfect, no signup required to view.`
            : 'Wallpapers for your device.'
        }
        image={wallpapers[0]?.preview_url || wallpapers[0]?.thumb_url}
      />

      <div className="relative z-10 px-6 sm:px-10 lg:px-14 py-10 max-w-[1600px] mx-auto">

        <header className="mb-8">
          <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
            Wallpapers for · {device?.brand || '—'}
          </div>
          {loadingDevice ? (
            <div className="c-detail-skel-bar h-[44px] w-2/3 mt-3" />
          ) : (
            <h1 className="display text-[clamp(34px,3.8vw,52px)] leading-[1.05] mt-2 tracking-[-0.012em] text-ink">
              {device?.name}
            </h1>
          )}
          {device && (
            <div className="mono text-[11px] tracking-[0.18em] uppercase text-muted mt-3 flex flex-wrap gap-x-4 gap-y-1 tabular-nums">
              <span>{device.width.toLocaleString()} × {device.height.toLocaleString()}</span>
              {device.ppi > 0 && <span>· {device.ppi} ppi</span>}
              <span>· {deviceAspect.toFixed(2)}:1</span>
              <span>· {wallpaperCount.toLocaleString()} wallpapers</span>
            </div>
          )}
        </header>

        {/* Floating-island wall encapsulated in DeviceFloatingWall.
            See the component for the layout-state details (drag,
            scroll-follow, dent-on-overlap). The page provides the
            data + responds to featured-tile changes for the mesh
            palette. */}
        {loadingList && wallpapers.length === 0 ? (
          // Skeleton: still uses a plain CSS grid since absolute
          // positioning needs measured wallWidth which isn't ready
          // yet on first render. The first cell mimics the device
          // mockup card — same glass surface, same span footprint —
          // so the page doesn't shift when the live wall takes over.
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            <div
              className="dev-preview-skel"
              style={{
                gridColumn: 'span 2',
                gridRow: 'span 2',
                aspectRatio: device
                  ? `${device.width * 2} / ${device.height * 2}`
                  : '32 / 18',
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
            {Array.from({ length: 12 }).map((_, i) => (
              <div
                key={i}
                className="dev-spec-card skeleton-card"
                style={{
                  aspectRatio: `${device?.width || 16} / ${device?.height || 9}`,
                  animationDelay: `${i * 30}ms`,
                }}
              />
            ))}
          </div>
        ) : wallpapers.length === 0 && !loadingDevice ? (
          <EmptyForDevice device={device} />
        ) : device ? (
          <>
            <DeviceFloatingWall
              device={device}
              wallpapers={wallpapers}
              onFeatureChange={setFeatured}
            />
            <div ref={attachSentinel} />
            <FeedFooter
              state={(
                loadError ? 'retry'
                : loadingList && hasMore ? 'loading'
                : !hasMore && wallpapers.length > 0 ? 'end'
                : 'idle'
              ) as FooterState}
              count={wallpapers.length}
              onRetry={() => fetchPage(false)}
            />
          </>
        ) : null}

        {/* Footer copy */}
        {device && (
          <section className="mt-14 border-t border-hair pt-7">
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted mb-3">
              About the {device.name}
            </div>
            <p className="text-[13px] leading-[1.65] text-ink-2 max-w-[640px]">
              Every wallpaper on this page has a variant cropped exactly for
              the {device.name}'s {device.width.toLocaleString()} × {device.height.toLocaleString()} display. Click into
              any wallpaper to see the per-device download list — or use the
              Download button on the detail page, which automatically picks
              the right variant for your current screen.
            </p>
          </section>
        )}

      </div>
    </div>
  );
}


// ─── Sub-components ─────────────────────────────────────────────────

function EmptyForDevice({ device }: { device: DeviceProfile | null }) {
  return (
    <div className="border border-dashed border-hair px-6 sm:px-10 py-12 text-center max-w-[640px] mx-auto">
      <div className="display italic-d text-[24px] sm:text-[28px] text-ink leading-tight">
        No wallpapers <span className="italic-d">yet</span>.
      </div>
      <p className="text-[13.5px] leading-[1.6] text-ink-2 mt-3 max-w-[460px] mx-auto">
        {device ? `Nobody has uploaded a wallpaper sized for the ${device.name} yet — but the variant pipeline is ready. Be the first.` : 'Be the first to upload one.'}
      </p>
      <Link
        to="/contribute"
        className="inline-flex items-center mt-5 px-5 py-2.5 rounded-full bg-ink text-paper text-[13px] font-medium no-underline hover:bg-ink-2 transition-colors"
      >
        Upload a wallpaper
      </Link>
    </div>
  );
}

// LoadMoreFooter removed — replaced by the shared FeedFooter +
// IntersectionObserver-driven infinite scroll.

// DeviceSpecGrid / SpecCell removed — replaced inline by the new
// .dev-spec-grid + DevSpec components in the hero column.
