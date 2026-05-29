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
// and resolves to the matching DeviceProfile. Pages that already
// have the devices array can call useCurrentDeviceId directly.
export function useCurrentDevice(): {
  device: DeviceProfile | null;
  loading: boolean;
} {
  const [devices, setDevices] = useState<DeviceProfile[]>([]);
  const [loading, setLoading] = useState(true);
  useEffect(() => {
    let cancelled = false;
    getDevices()
      .then((res) => {
        if (cancelled) return;
        setDevices((res.data.data || []) as DeviceProfile[]);
      })
      .catch(() => { /* swallow — null device gracefully degrades */ })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);
  const id = useCurrentDeviceId(devices);
  const device = useMemo(() => devices.find((d) => d.id === id) ?? null, [devices, id]);
  return { device, loading };
}
