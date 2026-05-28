import { useState, useEffect, useCallback, useMemo } from 'react';
import { useParams, Link } from 'react-router-dom';
import type { DeviceProfile, Wallpaper } from '../types';
import { getDeviceBySlug, getWallpapersForDevice } from '../api';
import PageMeta from '../components/PageMeta';
import WallpaperCard from '../components/WallpaperCard';
import ErrorState from '../components/ErrorState';
import { WallpaperGridSkeleton } from '../components/Skeletons';

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

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title={device ? `${device.name} Wallpapers — ${device.width} × ${device.height} pixel-perfect downloads` : 'Wallpapers'}
        description={
          device
            ? `Browse ${wallpaperCount} wallpapers cropped for the ${device.name}'s ${device.width} × ${device.height} display. Free, pixel-perfect, no signup required to view.`
            : 'Wallpapers for your device.'
        }
        image={wallpapers[0]?.preview_url || wallpapers[0]?.thumb_url}
      />

      <div className="px-6 sm:px-10 pt-7 pb-12 max-w-[1200px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-7">
          <div className="kicker text-muted">Wallpapers for · {device?.brand || '—'}</div>
          {loadingDevice ? (
            <div className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-paper-3 bg-paper-3 inline-block w-[60%] h-[56px] skeleton-card" />
          ) : (
            <h1 className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-ink">
              {device?.name}
            </h1>
          )}
          {device && (
            <div className="mono text-[11px] tracking-[0.12em] uppercase text-muted mt-3 flex flex-wrap gap-x-4 gap-y-1">
              <span>{device.width.toLocaleString()} × {device.height.toLocaleString()} px</span>
              {device.ppi > 0 && <span>· {device.ppi} ppi</span>}
              <span>· {wallpaperCount.toLocaleString()} wallpapers</span>
            </div>
          )}
        </header>

        {/* ─── Grid ─── */}
        {loadingList && wallpapers.length === 0 ? (
          <WallpaperGridSkeleton count={8} cols="4" />
        ) : wallpapers.length === 0 && !loadingDevice ? (
          <EmptyForDevice device={device} />
        ) : (
          <>
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
              {wallpapers.map((wp) => (
                <WallpaperCard key={wp.id} wallpaper={wp} fixedAspect hideActions />
              ))}
            </div>

            <LoadMoreFooter
              loading={loadingList}
              hasMore={hasMore}
              empty={wallpapers.length === 0}
              onLoadMore={() => fetchPage(false)}
            />
          </>
        )}

        {/* ─── Device spec block ─── */}
        {device && (
          <section className="mt-12 border-t border-hair pt-7">
            <div className="label-rule mb-3">About the {device.name}</div>
            <DeviceSpecGrid device={device} />
            <p className="text-[13px] leading-[1.6] text-ink-2 mt-5 max-w-[640px]">
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

function DeviceSpecGrid({ device }: { device: DeviceProfile }) {
  const orientation = useMemo(() => device.height > device.width ? 'Portrait' : 'Landscape', [device]);
  const platformLabel = device.platform.charAt(0).toUpperCase() + device.platform.slice(1);
  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 border border-hair border-r-0">
      <SpecCell label="Brand" value={device.brand} />
      <SpecCell label="Platform" value={platformLabel} />
      <SpecCell label="Resolution" value={`${device.width.toLocaleString()} × ${device.height.toLocaleString()}`} />
      <SpecCell label="Orientation" value={orientation} />
    </div>
  );
}

function SpecCell({ label, value }: { label: string; value: string }) {
  return (
    <div className="px-3 py-2.5 sm:px-3.5 sm:py-3 border-r border-hair">
      <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted">{label}</div>
      <div className="text-[14px] font-medium text-ink mt-1 truncate">{value}</div>
    </div>
  );
}
