import { useState, useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import type { DeviceProfile } from '../types';
import { getDevices } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';

interface DeviceWithCount extends DeviceProfile {
  wallpaper_count: number;
}

// Top-level /wallpapers-for hub. Lists every active device profile
// grouped by platform with a link to its dedicated landing page. Also
// gives Google a single page where all 42 device URLs are internally
// linked, which helps surface the per-device pages during indexing.
export default function DeviceIndexPage() {
  const [devices, setDevices] = useState<DeviceWithCount[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    getDevices()
      .then((res) => { setDevices(res.data.data as unknown as DeviceWithCount[]); setError(false); })
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, []);

  // Group by platform in a fixed render order.
  const groups = useMemo(() => {
    const order: Array<DeviceProfile['platform']> = ['desktop', 'laptop', 'tablet', 'phone'];
    const labels: Record<string, string> = {
      desktop: 'Desktops',
      laptop: 'Laptops',
      tablet: 'Tablets',
      phone: 'Phones',
    };
    return order
      .map((platform) => ({
        platform,
        label: labels[platform] || platform,
        items: devices.filter((d) => d.platform === platform),
      }))
      .filter((g) => g.items.length > 0);
  }, [devices]);

  const totalDevices = devices.length;

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title="Wallpapers by Device — Pixel-Perfect Downloads for Every Screen"
        description="Browse wallpapers cropped for forty-plus device profiles, from the iMac 27″ Retina to the iPhone 16 Pro Max. Pick your device, find the right wallpaper at the exact pixel size."
      />

      <div className="px-6 sm:px-10 pt-7 pb-12 max-w-[1100px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-9">
          <div className="kicker text-muted">Wallpapers for · {totalDevices || '—'} devices</div>
          <h1 className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-ink">
            Pick a screen. <span className="italic-d">We have a wallpaper for it.</span>
          </h1>
          <p className="text-[15px] leading-[1.55] text-ink-2 mt-5 max-w-[640px]">
            Every wallpaper in the archive is automatically resized for
            the device profiles below. Click yours to see all wallpapers
            cropped exactly for that screen.
          </p>
        </header>

        {/* ─── Error ─── */}
        {error && devices.length === 0 && <ErrorState />}

        {/* ─── Loading ─── */}
        {!error && loading && groups.length === 0 && (
          <div className="space-y-9">
            {[0, 1, 2, 3].map((i) => (
              <div key={i}>
                <div className="h-3 w-32 bg-paper-3 skeleton-card mb-4" />
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {[0, 1, 2, 3, 4, 5].map((j) => (
                    <div key={j} className="h-[64px] bg-paper-3 skeleton-card" />
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* ─── Groups ─── */}
        {groups.map((g) => (
          <section key={g.platform} className="mb-9">
            <div className="flex items-baseline justify-between mb-4">
              <h2 className="display text-[24px] leading-tight text-ink">{g.label}</h2>
              <span className="mono text-[10px] tracking-[0.14em] uppercase text-muted">
                {g.items.length} {g.items.length === 1 ? 'device' : 'devices'}
              </span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
              {g.items.map((d) => (
                <DeviceCard key={d.id} device={d} />
              ))}
            </div>
          </section>
        ))}

      </div>
    </div>
  );
}

function DeviceCard({ device }: { device: DeviceWithCount }) {
  const count = device.wallpaper_count;
  return (
    <Link
      to={`/wallpapers-for/${device.slug}`}
      className="group block border border-hair bg-paper hover:border-ink-2 hover:bg-paper-2 transition-colors no-underline"
    >
      <div className="px-4 py-3.5 flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="text-[14.5px] font-medium text-ink truncate">
            {device.name}
          </div>
          <div className="mono text-[10px] tracking-[0.06em] text-muted mt-0.5">
            {device.brand} · {device.width.toLocaleString()}×{device.height.toLocaleString()}
          </div>
        </div>
        <div className="text-right flex-shrink-0">
          <div className="display text-[18px] leading-none text-ink">
            {count.toLocaleString()}
          </div>
          <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted mt-1">
            {count === 1 ? 'wallpaper' : 'wallpapers'}
          </div>
        </div>
      </div>
    </Link>
  );
}
