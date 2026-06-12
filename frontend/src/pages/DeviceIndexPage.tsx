import { useState, useEffect, useMemo } from 'react';
import { Link } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import {
  MdPhoneIphone, MdPhoneAndroid,
  MdTabletMac, MdTabletAndroid,
  MdLaptopMac, MdLaptopWindows, MdLaptopChromebook,
  MdDesktopMac, MdDesktopWindows,
  MdDevices,
} from 'react-icons/md';
import type { IconType } from 'react-icons';
import type { DeviceProfile } from '../types';
import { getDevices } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';

// Best-effort 'what device is the user on' lookup. Computes the
// browser's physical pixel resolution (screen × devicePixelRatio)
// and finds an exact (or ±2px fuzzy) match in the profile list.
// Handles portrait/landscape swap so a phone held sideways still
// matches. Returns null when nothing fits.
function useCurrentDeviceId(devices: DeviceProfile[]): number | null {
  return useMemo(() => {
    if (typeof window === 'undefined' || !devices.length) return null;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.round(window.screen.width * dpr);
    const h = Math.round(window.screen.height * dpr);
    const exact = devices.find((d) =>
      (d.width === w && d.height === h) || (d.width === h && d.height === w),
    );
    if (exact) return exact.id;
    const fuzzy = devices.find((d) =>
      (Math.abs(d.width - w) <= 2 && Math.abs(d.height - h) <= 2) ||
      (Math.abs(d.width - h) <= 2 && Math.abs(d.height - w) <= 2),
    );
    return fuzzy?.id ?? null;
  }, [devices]);
}

// Brand-aware platform icon. We don't ship per-device renders (would
// require hundreds of bespoke assets); instead we pick a Material
// Design icon that matches platform + brand so an Apple laptop reads
// distinctly different from a Windows laptop in the list.
function iconFor(d: DeviceProfile): IconType {
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

interface DeviceWithCount extends DeviceProfile {
  wallpaper_count: number;
}

// Top-level /wallpapers-for hub. Lists every active device profile
// grouped by platform with a link to its dedicated landing page. Also
// gives Google a single page where all 42 device URLs are internally
// linked, which helps surface the per-device pages during indexing.
export default function DeviceIndexPage() {
  const { t } = useTranslation('devices');
  const [devices, setDevices] = useState<DeviceWithCount[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    getDevices()
      .then((res) => { setDevices(res.data.data as unknown as DeviceWithCount[]); setError(false); })
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, []);

  // Group by aspect ratio (square-ish first, ultrawide last). The
  // device.width / device.height ratio snaps to the nearest common
  // standard (16:9, 16:10, 4:3, 19.5:9, …) within ±0.04. Anything
  // farther becomes its own 'custom' bucket label. Always reduced to
  // landscape orientation (max/min) so a phone in portrait still
  // joins the same bucket as a tablet with the same ratio sideways.
  const groups = useMemo(() => {
    const known: Array<{ r: number; label: string }> = [
      { r: 5 / 4,    label: '5:4' },
      { r: 4 / 3,    label: '4:3' },
      { r: 3 / 2,    label: '3:2' },
      { r: 16 / 10,  label: '16:10' },
      { r: 16 / 9,   label: '16:9' },
      { r: 19 / 9,   label: '19:9' },
      { r: 19.5 / 9, label: '19.5:9' },
      { r: 20 / 9,   label: '20:9' },
      { r: 21 / 9,   label: '21:9' },
    ];
    const bucketFor = (d: DeviceProfile): string => {
      const a = Math.max(d.width, d.height) / Math.min(d.width, d.height);
      let best = known[0]; let bestDiff = Math.abs(a - best.r);
      for (const k of known) {
        const diff = Math.abs(a - k.r);
        if (diff < bestDiff) { best = k; bestDiff = diff; }
      }
      if (bestDiff <= 0.04) return best.label;
      // Fallback to a clean N.NN:1 string for outliers (rare).
      return `${a.toFixed(2)}:1`;
    };
    const bucketOrder = (label: string): number => {
      const i = known.findIndex((k) => k.label === label);
      return i === -1 ? known.length + 1 : i;
    };
    const map = new Map<string, DeviceWithCount[]>();
    for (const d of devices) {
      const key = bucketFor(d);
      const arr = map.get(key) || [];
      arr.push(d);
      map.set(key, arr);
    }
    return Array.from(map.entries())
      .map(([label, items]) => ({ label, items }))
      .sort((a, b) => bucketOrder(a.label) - bucketOrder(b.label));
  }, [devices]);

  const totalDevices = devices.length;
  const currentDeviceId = useCurrentDeviceId(devices);
  const currentDevice = currentDeviceId
    ? devices.find((d) => d.id === currentDeviceId) ?? null
    : null;

  return (
    <div className="devices-page min-h-full">
      <div className="devices-mesh" aria-hidden />
      <PageMeta
        title={t('index.metaTitle')}
        description={t('index.metaDescription')}
      />

      <div className="relative z-10 px-6 sm:px-10 lg:px-14 py-12 max-w-[1600px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-12">
          <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
            {t('index.kicker', { num: totalDevices || '—' })}
          </div>
          <h1 className="display text-[clamp(36px,4vw,56px)] leading-[1.05] mt-2 tracking-[-0.012em] text-ink">
            <Trans i18nKey="index.title" ns="devices" components={[<em key="0" className="devices-title-tail" />]} />
          </h1>
          <p className="text-[15px] leading-[1.55] text-ink-2 mt-4 max-w-[640px]">
            {t('index.subtitle')}
          </p>
        </header>

        {/* ─── Current-device callout ───
            Best-effort match against screen × DPR. Quietly absent when
            no profile matches the user's actual resolution. */}
        {currentDevice && (
          <Link to={`/wallpapers-for/${currentDevice.slug}`} className="device-current-callout">
            <span className="device-current-dot" aria-hidden />
            <span className="device-current-text">
              <Trans
                i18nKey="index.currentCallout"
                ns="devices"
                values={{ name: currentDevice.name }}
                components={[<strong key="0" />]}
              />
              <span className="device-current-meta"> · {currentDevice.width}×{currentDevice.height}</span>
            </span>
            <span className="device-current-cta">{t('index.currentCta')}</span>
          </Link>
        )}

        {/* ─── Error ─── */}
        {error && devices.length === 0 && <ErrorState />}

        {/* ─── Loading ─── */}
        {!error && loading && groups.length === 0 && (
          <div className="space-y-10">
            {[0, 1, 2, 3].map((i) => (
              <div key={i}>
                <div className="device-skel-head skeleton-card" />
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
                  {[0, 1, 2, 3, 4, 5].map((j) => (
                    <div key={j} className="device-card skeleton-card" />
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}

        {/* ─── Groups (by aspect ratio) ─── */}
        {groups.map((g) => (
          <section key={g.label} className="mb-10">
            <div className="flex items-baseline justify-between mb-4 pb-2 border-b border-hair">
              <h2 className="display text-[24px] leading-tight tracking-[-0.005em] text-ink">
                <span className="mono tabular-nums tracking-[0.02em] text-[20px]">{g.label}</span>
                <span className="text-muted text-[16px] mono tracking-[0.18em] uppercase ml-3"> · {t('index.aspect')}</span>
              </h2>
              <span className="mono text-[10px] tracking-[0.16em] uppercase text-muted">
                {g.items.length === 1 ? t('index.deviceOne') : t('index.deviceMany', { num: g.items.length })}
              </span>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {g.items.map((d) => (
                <DeviceCard key={d.id} device={d} isCurrent={d.id === currentDeviceId} />
              ))}
            </div>
          </section>
        ))}

      </div>
    </div>
  );
}

function DeviceCard({ device, isCurrent }: { device: DeviceWithCount; isCurrent: boolean }) {
  const { t } = useTranslation('devices');
  const count = device.wallpaper_count;
  const Icon = iconFor(device);
  return (
    <Link
      to={`/wallpapers-for/${device.slug}`}
      className={`device-card group${isCurrent ? ' is-current' : ''}`}
    >
      {isCurrent && <span className="device-card-badge">{t('index.yourDevice')}</span>}
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3.5 min-w-0">
          <span className="device-icon" aria-hidden>
            <Icon size={26} />
          </span>
          <div className="min-w-0">
            <div className="text-[14.5px] font-medium text-ink truncate">
              {device.name}
            </div>
            <div className="mono text-[10px] tracking-[0.06em] text-muted mt-0.5 tabular-nums">
              {device.brand} · {device.width.toLocaleString()}×{device.height.toLocaleString()}
            </div>
          </div>
        </div>
        <div className="text-right flex-shrink-0">
          <div className="display text-[18px] leading-none text-ink tabular-nums">
            {count.toLocaleString()}
          </div>
          <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted mt-1">
            {count === 1 ? t('index.wallpaperUnitOne') : t('index.wallpaperUnitMany')}
          </div>
        </div>
      </div>
    </Link>
  );
}
