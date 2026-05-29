import { useState, useEffect, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import { useParams, useLocation, Link } from 'react-router-dom';
import {
  MdPhoneIphone, MdPhoneAndroid,
  MdTabletMac, MdTabletAndroid,
  MdLaptopMac, MdLaptopWindows, MdLaptopChromebook,
  MdDesktopMac, MdDesktopWindows,
  MdDevices,
} from 'react-icons/md';
import {
  AiOutlineHeart, AiFillHeart,
  AiOutlineStar, AiFillStar,
  AiOutlineDownload, AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import type { IconType } from 'react-icons';
import type { DeviceProfile, Wallpaper } from '../types';
import { getDeviceBySlug, getWallpapersForDevice } from '../api';
import { useWallpaperActions } from '../hooks/useWallpaperActions';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import { WallpaperGridSkeleton } from '../components/Skeletons';

function deviceIcon(d: DeviceProfile | null): IconType {
  if (!d) return MdDevices;
  const brand = (d.brand || '').toLowerCase();
  const isApple = brand === 'apple';
  const isChromebook = brand.includes('chromebook') || /chrome ?os/i.test(d.name);
  switch (d.platform) {
    case 'phone':   return isApple ? MdPhoneIphone : MdPhoneAndroid;
    case 'tablet':  return isApple ? MdTabletMac : MdTabletAndroid;
    case 'laptop':  return isChromebook ? MdLaptopChromebook : isApple ? MdLaptopMac : MdLaptopWindows;
    case 'desktop': return isApple ? MdDesktopMac : MdDesktopWindows;
    default:        return MdDevices;
  }
}

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
    if (!device || loadingList) return;
    setLoadingList(true);
    try {
      const res = await getWallpapersForDevice(slug, {
        cursor: reset ? undefined : cursor,
        limit: 20,
      });
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => reset ? items : [...prev, ...items]);
      setCursor(has_more ? next_cursor : undefined);
      setHasMore(has_more);
    } catch {
      // Pagination failure — silent here; the loadingList flag flips
      // back and the user can scroll/retry. The top-level error state
      // only fires for the device fetch failure.
    } finally {
      setLoadingList(false);
    }
  }, [device, slug, cursor, loadingList]);

  // First page once we've resolved the device.
  useEffect(() => {
    if (device) fetchPage(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [device?.id]);

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
  const featuredCover = wallpapers[0]?.preview_url || wallpapers[0]?.thumb_url;
  // Hover-driven floating mockup: a single portal-rendered preview
  // follows whichever tile is hovered. We track the wallpaper + the
  // tile's rect; the FloatingMockup positions itself left/right of
  // the rect based on available room. Lifting state here (rather
  // than per-tile) means only one mockup ever paints.
  const [hovered, setHovered] = useState<{ wp: Wallpaper; rect: DOMRect } | null>(null);
  const onTileEnter = useCallback((wp: Wallpaper, el: HTMLElement) => {
    setHovered({ wp, rect: el.getBoundingClientRect() });
  }, []);
  const onTileLeave = useCallback(() => setHovered(null), []);
  // CSS class hook for the platform-specific device chrome (keyboard
  // base, phone notch, monitor stand, etc). See .dev-mockup.* in
  // index.css.
  const mockupClass = device ? `dev-mockup is-${device.platform}` : 'dev-mockup';
  const isAppleDesktop = device?.platform === 'desktop' && (device?.brand || '').toLowerCase() === 'apple';

  return (
    <div className="devices-page min-h-full">
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

        {/* ─── Hero: device frame + spec block ───
            Two-column layout: a screen frame at the device's real
            aspect ratio (the first wallpaper from the grid stands in
            as 'what one of these looks like on this device') paired
            with a mono spec table on the right. Phones / tablets get
            big corner radii so the frame reads as that device class
            without needing per-device silhouettes. */}
        <header className="dev-hero">
          <div className="dev-hero-left">
            <div
              className={`${mockupClass}${isAppleDesktop ? ' is-imac' : ''}`}
              style={{
                ['--dev-aspect' as string]: `${device?.width || 16} / ${device?.height || 9}`,
              } as React.CSSProperties}
              aria-hidden
            >
              <div className="dev-mockup-screen">
                {featuredCover ? (
                  <img src={featuredCover} alt="" />
                ) : (
                  <div className="dev-frame-empty" />
                )}
              </div>
              {/* Platform-specific chrome — phone gets a notch, laptop
                  a keyboard deck, desktop a stand, iMac a chin. CSS
                  draws everything; no per-device assets. */}
              {device?.platform === 'phone' && <span className="dev-mockup-notch" aria-hidden />}
              {device?.platform === 'laptop' && (
                <>
                  <span className="dev-mockup-laptop-base" aria-hidden />
                  <span className="dev-mockup-laptop-notch" aria-hidden />
                </>
              )}
              {device?.platform === 'desktop' && !isAppleDesktop && (
                <>
                  <span className="dev-mockup-stand-neck" aria-hidden />
                  <span className="dev-mockup-stand-foot" aria-hidden />
                </>
              )}
            </div>
          </div>

          <div className="dev-hero-right">
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
              <>
                <div className="dev-spec-grid">
                  <DevSpec label="Resolution" value={`${device.width.toLocaleString()} × ${device.height.toLocaleString()}`} />
                  {device.ppi > 0 && <DevSpec label="PPI" value={`${device.ppi}`} />}
                  <DevSpec label="Aspect" value={(deviceAspect).toFixed(2)} />
                  <DevSpec label="Wallpapers" value={wallpaperCount.toLocaleString()} />
                </div>
              </>
            )}
          </div>
        </header>

        {/* ─── Grid ───
            Each cell renders at the device's exact aspect ratio so
            the wall reads as 'these all fit your screen' — not a
            generic 3:2 catalog. */}
        {loadingList && wallpapers.length === 0 ? (
          <WallpaperGridSkeleton count={8} cols="4" />
        ) : wallpapers.length === 0 && !loadingDevice ? (
          <EmptyForDevice device={device} />
        ) : (
          <>
            <div className={`grid gap-4 ${
              deviceAspect < 0.8 ? 'grid-cols-3 sm:grid-cols-4 lg:grid-cols-6'  // phone-ish portrait → more cols
              : deviceAspect < 1.2 ? 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-5' // square-ish tablet → mid
              : 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4'                     // landscape laptop/desktop
            }`}>
              {wallpapers.map((wp, i) => (
                <DevSpecCard
                  key={wp.id}
                  wallpaper={wp}
                  device={device}
                  index={i}
                  onEnter={onTileEnter}
                  onLeave={onTileLeave}
                />
              ))}
            </div>
            {hovered && device && (
              <FloatingMockup wp={hovered.wp} device={device} anchorRect={hovered.rect} />
            )}

            <LoadMoreFooter
              loading={loadingList}
              hasMore={hasMore}
              empty={wallpapers.length === 0}
              onLoadMore={() => fetchPage(false)}
            />
          </>
        )}

        {/* ─── Footer copy ─── */}
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

/* Spec card — the new tile for the device-detail grid. Wallpaper at
   device aspect inside a thin steel border + corner brackets, with a
   bottom info strip carrying the device icon, mono resolution, and
   sequence number (01/24 style). Hover lifts the card, brings actions
   in over the image. Reads as 'an index card from a spec book' — a
   distinct treatment vs Discover salon / Weekly portrait / Collection
   framed-mat. */
function DevSpecCard({
  wallpaper: w, device, index, onEnter, onLeave,
}: {
  wallpaper: Wallpaper;
  device: DeviceProfile | null;
  index: number;
  onEnter: (w: Wallpaper, el: HTMLElement) => void;
  onLeave: () => void;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const Icon = deviceIcon(device);
  const aspect = device ? `${device.width} / ${device.height}` : '16 / 9';
  const ref = useRef<HTMLAnchorElement | null>(null);
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };
  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      ref={ref}
      className="dev-spec-card"
      style={{ animationDelay: `${index * 30}ms` }}
      onMouseEnter={() => { if (ref.current) onEnter(w, ref.current); }}
      onMouseLeave={onLeave}
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
      <div className="dev-spec-card-strip">
        <span className="dev-spec-card-icon" aria-hidden><Icon size={13} /></span>
        <span className="dev-spec-card-res">
          {device ? `${device.width}×${device.height}` : `${w.width}×${w.height}`}
        </span>
        <span className="dev-spec-card-seq">
          № {String(index + 1).padStart(2, '0')}
        </span>
      </div>
    </Link>
  );
}

/* Floating mockup — single portaled element that follows whichever
   spec-card is hovered. Renders a mini version of the device hero's
   chrome (.dev-mockup family) with the hovered wallpaper inside, so
   the user gets to see "what this looks like on the device" before
   committing to click. Positions itself to the right of the anchor
   when there's room, otherwise flips to the left; vertically biased
   to keep within the viewport. */
function FloatingMockup({
  wp, device, anchorRect,
}: {
  wp: Wallpaper;
  device: DeviceProfile;
  anchorRect: DOMRect;
}) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => { setMounted(true); }, []);
  if (!mounted) return null;

  // Phone-shaped mockups are narrow + tall; landscape mockups are
  // wide + short. Pick a target width per platform so the popup
  // always sits at a similar visible footprint.
  const targetWidth =
    device.platform === 'phone' ? 200 :
    device.platform === 'tablet' ? 240 :
    300;
  const aspect = device.width / device.height;
  // Estimated height including platform chrome (laptop deck +14,
  // desktop stand +36, iMac chin already in border, phone notch
  // already inside, tablet nothing extra). Reserved so vertical
  // clamping has the right target.
  const chromeExtra =
    device.platform === 'laptop' ? 22 :
    device.platform === 'desktop' && device.brand?.toLowerCase() !== 'apple' ? 40 :
    0;
  const estHeight = targetWidth / aspect + chromeExtra;

  const GAP = 18;
  const vw = window.innerWidth;
  const vh = window.innerHeight;
  const rightSpace = vw - anchorRect.right - GAP;
  const placeRight = rightSpace >= targetWidth;
  const left = placeRight
    ? anchorRect.right + GAP
    : Math.max(GAP, anchorRect.left - targetWidth - GAP);
  // Bias vertical: align top with anchor top, but clamp to viewport.
  const idealTop = anchorRect.top + (anchorRect.height - estHeight) / 2;
  const top = Math.max(20, Math.min(vh - estHeight - 20, idealTop));

  const isAppleDesktop = device.platform === 'desktop' && (device.brand || '').toLowerCase() === 'apple';
  const mockupClass = `dev-mockup is-${device.platform}${isAppleDesktop ? ' is-imac' : ''} is-floating${placeRight ? '' : ' is-left'}`;

  return createPortal(
    <div
      className="dev-tile-mockup-host"
      style={{
        position: 'fixed',
        left,
        top,
        width: targetWidth,
        pointerEvents: 'none',
        zIndex: 50,
      }}
    >
      <div
        className={mockupClass}
        style={{ ['--dev-aspect' as string]: `${device.width} / ${device.height}` } as React.CSSProperties}
        aria-hidden
      >
        <div className="dev-mockup-screen">
          <img src={wp.preview_url || wp.thumb_url} alt="" />
        </div>
        {device.platform === 'phone' && <span className="dev-mockup-notch" />}
        {device.platform === 'laptop' && (
          <>
            <span className="dev-mockup-laptop-base" />
            <span className="dev-mockup-laptop-notch" />
          </>
        )}
        {device.platform === 'desktop' && !isAppleDesktop && (
          <>
            <span className="dev-mockup-stand-neck" />
            <span className="dev-mockup-stand-foot" />
          </>
        )}
      </div>
    </div>,
    document.body,
  );
}

function DevSpec({ label, value }: { label: string; value: string }) {
  return (
    <div className="dev-spec">
      <div className="dev-spec-label">{label}</div>
      <div className="dev-spec-value">{value}</div>
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

function LoadMoreFooter({
  loading, hasMore, empty, onLoadMore,
}: { loading: boolean; hasMore: boolean; empty: boolean; onLoadMore: () => void }) {
  if (empty) return null;
  if (loading) {
    return (
      <div className="text-center mt-8 mono text-[10px] tracking-[0.14em] uppercase text-muted">
        Loading more…
      </div>
    );
  }
  if (hasMore) {
    return (
      <div className="text-center mt-8">
        <button
          onClick={onLoadMore}
          className="inline-flex px-5 py-2 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2 hover:border-ink-2 transition-colors"
        >
          Load more
        </button>
      </div>
    );
  }
  return (
    <div className="flex items-center justify-center gap-3 mt-10">
      <span className="w-8 h-px bg-hair" />
      <span className="mono text-[10px] tracking-[0.18em] uppercase text-muted">End</span>
      <span className="w-8 h-px bg-hair" />
    </div>
  );
}

// DeviceSpecGrid / SpecCell removed — replaced inline by the new
// .dev-spec-grid + DevSpec components in the hero column.
