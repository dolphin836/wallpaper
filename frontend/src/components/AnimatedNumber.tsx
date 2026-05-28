import { useEffect, useRef, useState } from 'react';

/**
 * Tweens a number from its previous render to the current value over `duration`
 * milliseconds, using ease-out-quart. Mounts at the initial value (no animation
 * on first paint); only subsequent value changes animate. Cancels pending
 * tweens if the value changes mid-animation, so rapid updates don't queue.
 *
 * Used by the sidebar coin balance so a +1 earned / −1 spent feels like a
 * meter moving, not a digit jumping. Cheap: one rAF loop per active tween,
 * single-component scope.
 */
export default function AnimatedNumber({
  value,
  duration = 480,
  format,
}: {
  value: number;
  duration?: number;
  format?: (n: number) => string;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);

  useEffect(() => {
    const from = prevRef.current;
    const to = value;
    if (from === to) return;
    // Respect reduced-motion: jump immediately, no tween.
    const reduced = window.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
    if (reduced) {
      setDisplay(to);
      prevRef.current = to;
      return;
    }
    const start = performance.now();
    let raf = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / duration);
      // ease-out-quart
      const eased = 1 - Math.pow(1 - t, 4);
      const n = Math.round(from + (to - from) * eased);
      setDisplay(n);
      if (t < 1) {
        raf = requestAnimationFrame(tick);
      } else {
        prevRef.current = to;
      }
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, duration]);

  return <>{format ? format(display) : display}</>;
}
