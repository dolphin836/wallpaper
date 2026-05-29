import { useState, useEffect, useCallback, useRef, useMemo, useLayoutEffect } from 'react';
import { motion, useMotionValue, useTransform, animate } from 'framer-motion';
import { useParams, useLocation, Link } from 'react-router-dom';
import {
  AiOutlineHeart, AiFillHeart,
  AiOutlineStar, AiFillStar,
  AiOutlineDownload, AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import type { DeviceProfile, Wallpaper } from '../types';
import { getDeviceBySlug, getWallpapersForDevice } from '../api';
import { useWallpaperActions } from '../hooks/useWallpaperActions';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import FeedFooter, { type FooterState } from '../components/FeedFooter';

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
  // Sticky-frame state: the right-column mockup always shows whichever
  // wallpaper the cursor most recently hovered. Defaults to the first
  // pick so the frame is never empty. We *don't* reset on mouse-leave
  // so the frame doesn't flicker back to the default while the cursor
  // travels between tiles.
  const [featuredIdx, setFeaturedIdx] = useState(0);
  const featured = wallpapers[featuredIdx] ?? wallpapers[0] ?? null;
  const featuredCover = featured?.preview_url || featured?.thumb_url;
  const onTileHover = useCallback((idx: number) => setFeaturedIdx(idx), []);
  // Preview mode — Plain (just wallpaper), Home (dock + menu bar /
  // status bar), Lock (centered clock + date). Same three modes most
  // device preview tools surface. Mutually exclusive.
  const [previewMode, setPreviewMode] = useState<'plain' | 'home' | 'lock'>('plain');

  // Page mesh + sticky-frame backdrop both pick up colour from the
  // currently-featured wallpaper. Hovering a tile changes featuredIdx
  // which → ripples through both via this effect.
  const rootRef = useRef<HTMLDivElement | null>(null);
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
  // CSS class hook for the platform-specific device chrome (keyboard
  // base, phone notch, monitor stand, etc). See .dev-mockup.* in
  // index.css.
  const mockupClass = device ? `dev-mockup is-${device.platform}` : 'dev-mockup';
  const isAppleDesktop = device?.platform === 'desktop' && (device?.brand || '').toLowerCase() === 'apple';

  // ── Floating-island layout state ─────────────────────────────
  // The wallpaper grid is no longer a CSS Grid — it's a measured
  // canvas of absolutely-positioned tiles. The device mockup is a
  // draggable motion.div that "sits" in the top-left and pushes
  // tiles out of its way as it moves. When the user releases drag,
  // tiles flow back into the cells the mockup vacated.
  //
  // Why absolute positioning instead of CSS Grid:
  //   - We need continuous (sub-cell) preview motion for the drag
  //     interaction; grid placement is integer-only.
  //   - Tiles need to spring-animate between cells as the preview's
  //     occupied region changes; CSS Grid doesn't animate cell
  //     placement, but framer-motion's animate prop on x/y does.
  //   - Drag bounds, scroll-follow, and ripple-on-contact all need
  //     pixel-accurate positions.
  const wallRef = useRef<HTMLDivElement>(null);
  const [wallWidth, setWallWidth] = useState(0);
  useLayoutEffect(() => {
    if (!wallRef.current) return;
    const el = wallRef.current;
    const update = () => setWallWidth(el.clientWidth);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // Responsive column count derived from the wall's actual width.
  // The hard breakpoints aim for ~260-380px tile cells across the
  // range so the wall feels equally "dense" at every viewport.
  const cols = useMemo(() => {
    if (wallWidth >= 1500) return 6;
    if (wallWidth >= 1200) return 5;
    if (wallWidth >= 900)  return 4;
    if (wallWidth >= 640)  return 3;
    return 2;
  }, [wallWidth]);

  const gap = 12;
  // Tile dimensions: width from container/cols, height from device
  // aspect ratio. Clamped to keep the wall sane on extreme aspects
  // (e.g., 32:9 ultrawide tile would otherwise be ~80px tall).
  const tileW = wallWidth > 0 ? (wallWidth - gap * (cols - 1)) / cols : 0;
  const rawTileH = tileW / (deviceAspect || 1.78);
  const tileH = Math.max(140, Math.min(480, rawTileH));

  const isPhone = device?.platform === 'phone';
  const previewColSpan = 2;
  const previewRowSpan = isPhone ? 1 : 2;
  const previewW = tileW * previewColSpan + gap * (previewColSpan - 1);
  const previewH = tileH * previewRowSpan + gap * (previewRowSpan - 1);

  // Preview's pixel position relative to the wall's top-left,
  // tracked as motion values so framer-motion can spring/animate
  // them without React re-rendering the whole tree on every frame.
  const previewX = useMotionValue(0);
  const previewY = useMotionValue(0);
  const [isDragging, setIsDragging] = useState(false);

  // Scroll-follow: when the user has scrolled the wall enough that
  // the top of the page is below the preview's home row, the
  // preview's resting Y shifts downward to stay in view. The
  // tile-placement logic treats this shifted Y just like a drag —
  // tiles flow around the preview's *current* grid cell, wherever
  // it happens to be. (User goal: 'preview always visible while
  // scrolling, leaves moving relative to the boat'.)
  const [scrollFollowY, setScrollFollowY] = useState(0);
  useEffect(() => {
    const update = () => {
      const wall = wallRef.current;
      if (!wall) return;
      const rect = wall.getBoundingClientRect();
      // Top inset matches the page header / sticky nav so the
      // mockup doesn't slip under the chrome.
      const inset = 100;
      const targetY = Math.max(0, inset - rect.top);
      // But never push the preview below the bottom edge of the
      // wall, otherwise it'd float off into empty space.
      const maxY = Math.max(0, rect.height - previewH - 8);
      setScrollFollowY(Math.min(targetY, maxY));
    };
    update();
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('scroll', update);
      window.removeEventListener('resize', update);
    };
  }, [previewH]);

  // When not dragging, the preview animates toward (0, scrollFollowY)
  // — its top-left "home" column with the scroll-follow Y. During
  // drag, framer-motion owns x/y directly via the drag handlers.
  useEffect(() => {
    if (isDragging) return;
    const ax = animate(previewX, 0, { type: 'spring', stiffness: 220, damping: 28 });
    const ay = animate(previewY, scrollFollowY, { type: 'spring', stiffness: 220, damping: 28 });
    return () => { ax.stop(); ay.stop(); };
  }, [isDragging, scrollFollowY, previewX, previewY]);

  // Mirror the preview's continuous motion into discrete grid cell
  // coordinates that the tile-placement logic reads. Throttled by
  // motion-value 'change' events (one tick per animation frame),
  // which is plenty fast for the reflow to feel responsive while
  // keeping React renders to one per actual cell change.
  const previewColMV = useTransform(previewX, (x) => {
    if (tileW <= 0) return 0;
    const c = Math.round(x / (tileW + gap));
    return Math.max(0, Math.min(cols - previewColSpan, c));
  });
  const previewRowMV = useTransform(previewY, (y) => {
    if (tileH <= 0) return 0;
    return Math.max(0, Math.round(y / (tileH + gap)));
  });
  const [previewCell, setPreviewCell] = useState({ col: 0, row: 0 });
  useEffect(() => {
    const u1 = previewColMV.on('change', (v) => setPreviewCell((p) => p.col === v ? p : { ...p, col: v }));
    const u2 = previewRowMV.on('change', (v) => setPreviewCell((p) => p.row === v ? p : { ...p, row: v }));
    return () => { u1(); u2(); };
  }, [previewColMV, previewRowMV]);

  // Walk the grid in row-major order, skip cells that fall inside
  // the preview's footprint, and assign each tile the next free
  // cell. As the preview moves, this mapping shifts — tiles spring
  // to their new (col, row) via motion.div animate on x/y.
  const tilePositions = useMemo(() => {
    const out: { col: number; row: number }[] = [];
    const n = wallpapers.length;
    if (!device || n === 0 || cols <= 0) return out;
    const { col: pc, row: pr } = previewCell;
    const pcsEnd = pc + previewColSpan;
    const prsEnd = pr + previewRowSpan;
    let r = 0, c = 0;
    while (out.length < n) {
      const inPreview = c >= pc && c < pcsEnd && r >= pr && r < prsEnd;
      if (!inPreview) {
        out.push({ col: c, row: r });
      }
      c++;
      if (c >= cols) { c = 0; r++; }
      // Safety net for pathological inputs (shouldn't happen).
      if (r > n + 4) break;
    }
    return out;
  }, [wallpapers.length, cols, previewCell.col, previewCell.row, previewColSpan, previewRowSpan, device]);

  // Total wall height — enough rows to hold all tiles plus the
  // preview footprint, no matter where the preview is parked.
  const wallHeight = useMemo(() => {
    if (!device || cols <= 0 || wallpapers.length === 0) {
      return previewH; // just the preview during empty/initial state
    }
    const lastTile = tilePositions[tilePositions.length - 1];
    const lastTileBottom = lastTile ? (lastTile.row + 1) * tileH + lastTile.row * gap : 0;
    const previewBottom = (previewCell.row + previewRowSpan) * tileH + (previewCell.row + previewRowSpan - 1) * gap;
    return Math.max(lastTileBottom, previewBottom);
  }, [tilePositions, tileH, gap, previewCell.row, previewRowSpan, previewH, device, cols, wallpapers.length]);

  // Ripple-on-contact: tiles immediately adjacent to the preview's
  // current footprint get a class that triggers a soft scaling +
  // shadow ripple. Cheap CSS — no per-frame JS.
  const isTileAdjacent = useCallback((col: number, row: number) => {
    const { col: pc, row: pr } = previewCell;
    const colNear = col >= pc - 1 && col < pc + previewColSpan + 1;
    const rowNear = row >= pr - 1 && row < pr + previewRowSpan + 1;
    return colNear && rowNear;
  }, [previewCell, previewColSpan, previewRowSpan]);

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

        {/* Floating-island wall. The wallpaper "grid" is an absolutely
            positioned canvas, not CSS Grid — see the comment block
            on layout state above for why. The device mockup is a
            draggable motion.div pinned at the top-left by default;
            tiles flow around its current footprint via the
            tilePositions mapping, and spring to their new cells when
            the mockup moves. Scroll-follow keeps the mockup in view
            as the user scrolls past the wall's top. */}
        {loadingList && wallpapers.length === 0 ? (
          // Skeleton: still uses a plain CSS grid since absolute
          // positioning needs measured wallWidth which isn't ready
          // yet on first render.
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            <div className="skeleton-card" style={{ aspectRatio: `${(device?.width || 16) * 2} / ${(device?.height || 9) * (device?.platform === 'phone' ? 1 : 2)}`, gridColumn: 'span 2', gridRow: device?.platform === 'phone' ? 'auto' : 'span 2' }} />
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
        ) : (
          <>
            <div
              ref={wallRef}
              className="dev-wall-area"
              style={{ height: wallHeight }}
            >
              {/* Draggable device mockup. dragConstraints clamp it
                  to the wall's rectangle, so the user can shove it
                  around but never out into empty space. dragElastic
                  is low (0.06) so the edges feel firm — this isn't
                  a free-fly toy, it's a heavy preview frame. On
                  drag end the spring-animate effect above pulls it
                  back to (0, scrollFollowY). */}
              {device && wallWidth > 0 && (
                <motion.div
                  className={`dev-preview-floating${isDragging ? ' is-dragging' : ''}`}
                  drag
                  dragConstraints={{
                    left: 0,
                    top: 0,
                    right: Math.max(0, wallWidth - previewW),
                    bottom: Math.max(0, wallHeight - previewH),
                  }}
                  dragElastic={0.06}
                  dragMomentum={false}
                  onDragStart={() => setIsDragging(true)}
                  onDragEnd={() => setIsDragging(false)}
                  whileDrag={{ scale: 1.02, cursor: 'grabbing' }}
                  style={{
                    x: previewX,
                    y: previewY,
                    width: previewW,
                    height: previewH,
                  }}
                >
                  <div
                    className="dev-page-sticky-inner"
                    style={{
                      ['--featured-bg' as string]: featuredCover ? `url(${JSON.stringify(featuredCover)})` : 'none',
                    } as React.CSSProperties}
                  >
                    <div className="dev-page-sticky-bg" aria-hidden />
                    <div
                      className={`${mockupClass}${isAppleDesktop ? ' is-imac' : ''}`}
                      style={{
                        ['--dev-aspect' as string]: `${device.width || 16} / ${device.height || 9}`,
                      } as React.CSSProperties}
                      aria-hidden
                    >
                      <div className="dev-mockup-screen">
                        {featuredCover ? (
                          <img src={featuredCover} alt="" draggable={false} />
                        ) : (
                          <div className="dev-frame-empty" />
                        )}
                        {previewMode === 'lock' && (
                          <PreviewLockOverlay platform={device.platform} />
                        )}
                        {previewMode === 'home' && (
                          <PreviewHomeOverlay platform={device.platform} />
                        )}
                      </div>
                      {device.platform === 'phone' && <span className="dev-mockup-notch" aria-hidden />}
                      {device.platform === 'laptop' && (
                        <>
                          <span className="dev-mockup-laptop-base" aria-hidden />
                          <span className="dev-mockup-laptop-notch" aria-hidden />
                        </>
                      )}
                      {device.platform === 'desktop' && !isAppleDesktop && (
                        <>
                          <span className="dev-mockup-stand-neck" aria-hidden />
                          <span className="dev-mockup-stand-foot" aria-hidden />
                        </>
                      )}
                    </div>

                    <div className="dev-mode-toggles" role="radiogroup" aria-label="Preview mode">
                      {(['plain', 'home', 'lock'] as const).map((m) => (
                        <button
                          key={m}
                          type="button"
                          role="radio"
                          aria-checked={previewMode === m}
                          onClick={() => setPreviewMode(m)}
                          onPointerDown={(e) => e.stopPropagation()}
                          className={`dev-mode-pill${previewMode === m ? ' is-on' : ''}`}
                        >
                          {m === 'plain' ? 'Plain' : m === 'home' ? 'Home' : 'Lock'}
                        </button>
                      ))}
                    </div>
                  </div>
                </motion.div>
              )}

              {/* Absolutely-positioned wallpaper tiles. Each one
                  animates its (x, y) toward the cell assigned by
                  tilePositions[i]; framer-motion's spring smooths
                  the reflow when the preview moves. Tiles within
                  one cell of the preview footprint get a 'rippled'
                  class for the contact-edge wave. */}
              {wallpapers.map((wp, i) => {
                const pos = tilePositions[i];
                if (!pos) return null;
                const adj = isTileAdjacent(pos.col, pos.row);
                return (
                  <motion.div
                    key={wp.id}
                    className={`dev-wall-slot${adj ? ' is-rippled' : ''}`}
                    initial={false}
                    animate={{
                      x: pos.col * (tileW + gap),
                      y: pos.row * (tileH + gap),
                    }}
                    transition={{ type: 'spring', stiffness: 230, damping: 28, mass: 0.6 }}
                    style={{ width: tileW, height: tileH }}
                  >
                    <DevTile
                      wallpaper={wp}
                      device={device}
                      index={i}
                      isFeatured={i === featuredIdx}
                      onHover={onTileHover}
                    />
                  </motion.div>
                );
              })}
            </div>

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
        )}

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

/* Device tile — simple wallpaper card at device aspect, with a
   sequence badge + action rail on hover. Hovering bumps the parent's
   featuredIdx so the right-column sticky mockup re-renders this
   tile's wallpaper. The wallpaper-on-device 'try it on' read happens
   in the sticky frame, not here. */
function DevTile({
  wallpaper: w, device, index, isFeatured, onHover,
}: {
  wallpaper: Wallpaper;
  device: DeviceProfile | null;
  index: number;
  isFeatured: boolean;
  onHover: (idx: number) => void;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const aspect = device ? `${device.width} / ${device.height}` : '16 / 9';
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };
  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      className={`dev-spec-card${isFeatured ? ' is-featured' : ''}`}
      style={{ animationDelay: `${index * 30}ms` }}
      onMouseEnter={() => onHover(index)}
    >
      <div className="dev-spec-card-screen" style={{ aspectRatio: aspect }}>
        <img
          src={w.preview_url || w.thumb_url}
          alt={w.title || `Wallpaper ${w.id}`}
          loading="lazy"
          className="dev-spec-card-img"
          style={{ backgroundColor: w.dominant_color || undefined }}
        />
        {/* Corner brackets — four hairline L's drawn with pseudo
            elements via the .dev-spec-card-screen::before/::after
            stacks (see index.css). */}
        <div className="tile-actions">
          <button
            type="button"
            onClick={(e) => stop(e, acts.handleFavorite)}
            disabled={acts.favLoading}
            className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
            title={acts.favorited ? 'Unfavorite' : 'Favorite'}
          >
            {acts.favLoading
              ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
              : acts.favorited
                ? <AiFillStar size={15} />
                : <AiOutlineStar size={15} />}
          </button>
          <button
            type="button"
            onClick={(e) => stop(e, acts.handleLike)}
            disabled={acts.likeLoading}
            className={`t-act ${acts.liked ? 'is-liked' : ''}`}
            title={acts.liked ? 'Unlike' : 'Like'}
          >
            {acts.likeLoading
              ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
              : acts.liked
                ? <AiFillHeart size={15} />
                : <AiOutlineHeart size={15} />}
          </button>
          {acts.canDownload && (
            <button
              type="button"
              onClick={(e) => stop(e, acts.handleDownload)}
              disabled={acts.downloading}
              className={`t-act ${acts.downloaded ? 'is-downloaded' : ''}`}
              title={acts.downloaded ? 'Downloaded' : 'Download (1 coin)'}
            >
              {acts.downloading
                ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                : acts.downloaded
                  ? <AiOutlineCheckCircle size={15} />
                  : <AiOutlineDownload size={15} />}
            </button>
          )}
        </div>
      </div>
    </Link>
  );
}

// FloatingMockup retired — replaced by the right-column sticky frame
// pattern. Hovering a tile bumps featuredIdx; the sticky frame on
// the right stays in view and always reflects the current pick.

/* PreviewLockOverlay — large centered clock + date + a subtle scrim,
   mirrors the iOS/macOS lock-screen typography. Time pulled from the
   live clock (formats per platform: iOS = HH:MM, macOS = HH:MM); date
   uses the user's locale. */
function PreviewLockOverlay({ platform }: { platform: DeviceProfile['platform'] }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30000);
    return () => clearInterval(id);
  }, []);
  const time = now.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });
  const date = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
  // Phones bias the clock toward the top (under the notch). Laptop/
  // desktop bias more toward middle — closer to the macOS login look.
  const topAnchor = platform === 'phone' ? '14%' : platform === 'tablet' ? '20%' : '32%';
  return (
    <div className="dev-overlay-lock" style={{ paddingTop: topAnchor }} aria-hidden>
      <div className="dev-overlay-lock-time">{time}</div>
      <div className="dev-overlay-lock-date">{date}</div>
    </div>
  );
}

/* PreviewHomeOverlay — a dock of small icon squares pinned to the
   bottom + (for laptop/desktop) a thin menu bar at the top.
   Different layouts by platform so the overlay reads like the real
   thing without committing to brand-specific assets. */
function PreviewHomeOverlay({ platform }: { platform: DeviceProfile['platform'] }) {
  // Six distinctly-coloured "app" dots — different hue per icon so
  // the dock reads as a real one without showing actual brand logos.
  const HUES = [25, 90, 150, 210, 280, 330];
  const dockSize = platform === 'phone' ? 5 : 6;
  return (
    <div className="dev-overlay-home" aria-hidden>
      {(platform === 'laptop' || platform === 'desktop') && (
        <div className="dev-overlay-menubar" />
      )}
      <div className={`dev-overlay-dock is-${platform}`}>
        {HUES.slice(0, dockSize).map((h, i) => (
          <span
            key={i}
            className="dev-overlay-dock-icon"
            style={{ ['--ico-h' as string]: String(h) } as React.CSSProperties}
          />
        ))}
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
