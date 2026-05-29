import { useEffect, useMemo, useState } from 'react';
import type { DeviceProfile } from '../types';
import { getDevices } from '../api';

// useCurrentDeviceId — match the visitor's display against the
// known device profiles, return the closest match's id (or null).
// Pure function over an already-fetched devices array; identical
// to the implementation that lived inline in DeviceIndexPage,
// pulled out here so DiscoverPage / floating-wall layouts can
// share the detection.
export function useCurrentDeviceId(devices: DeviceProfile[]): number | null {
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

// useCurrentDevice — convenience hook that fetches the devices list
// and resolves to the matching DeviceProfile. Synchronous fallback
// from window.screen lets callers (skeleton placeholders, floating-
// wall layouts) start with a sensible device shape on first render
// even before the async fetch resolves. Once the real list lands,
// the matched profile replaces the synthetic one — UI just refines.
export function useCurrentDevice(): {
  device: DeviceProfile | null;
  loading: boolean;
} {
  const fallback = useMemo<DeviceProfile | null>(() => {
    if (typeof window === 'undefined') return null;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.round(window.screen.width * dpr);
    const h = Math.round(window.screen.height * dpr);
    const ratio = w / Math.max(1, h);
    // Coarse platform guess from aspect — refined when the real
    // device list arrives.
    let platform: DeviceProfile['platform'] = 'desktop';
    if (ratio < 0.8) platform = 'phone';
    else if (ratio < 1.3) platform = 'tablet';
    else if (ratio < 1.7) platform = 'laptop';
    return {
      id: 0,
      slug: '',
      brand: '',
      name: 'Your device',
      platform,
      width: w,
      height: h,
      ppi: 0,
      sort_order: 0,
      is_active: true,
    };
  }, []);

  const [devices, setDevices] = useState<DeviceProfile[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let cancelled = false;
    getDevices()
      .then((res) => {
        if (cancelled) return;
        setDevices((res.data.data || []) as DeviceProfile[]);
      })
      .catch(() => { /* swallow — fallback continues to serve */ })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);
  const id = useCurrentDeviceId(devices);
  const matched = useMemo(() => devices.find((d) => d.id === id) ?? null, [devices, id]);
  return { device: matched ?? fallback, loading };
}
