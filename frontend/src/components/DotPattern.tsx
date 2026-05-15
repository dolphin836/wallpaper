import { useId, useEffect, useRef, useState } from 'react';

interface Props {
  width?: number;        // grid cell width in CSS pixels
  height?: number;       // grid cell height
  cr?: number;           // dot radius
  className?: string;    // controls the BASE color (Tailwind text-* class)
  spotlightClassName?: string; // BLOOM color near the cursor; should be a stronger/darker text-* class
  spotlightRadius?: number; // half-width of the bloom patch, in dot cells (so 3 = 6×6 patch)
}

/**
 * Background dot grid with a cursor-following "spotlight" bloom.
 *
 * Implementation: two SVG layers stacked.
 *   1. <pattern>-filled rect → cheap, repaints zero times after first render,
 *      renders every dot in the visible area at the base color.
 *   2. A handful of darker circles overlaid on top of the dots closest to
 *      the cursor — opacity falls off with euclidean distance so the dot
 *      *under* the cursor is most intense and the ring fades out smoothly.
 *
 * The overlay circles share grid positions with the base pattern, so the
 * effect reads as "the dots near the cursor turn a darker shade" rather
 * than "extra dots appear."
 */
export default function DotPattern({
  width = 20,
  height = 20,
  cr = 1,
  className = '',
  spotlightClassName = 'text-slate-500 dark:text-white/40',
  spotlightRadius = 3,
}: Props) {
  const id = useId();
  const containerRef = useRef<HTMLDivElement>(null);
  const [mouse, setMouse] = useState<{ x: number; y: number } | null>(null);
  const rafRef = useRef(0);
  const pendingRef = useRef<{ x: number; y: number } | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    // Hover-capable pointer only — on touch devices a "follow the cursor"
    // bloom is just visual noise that triggers on every tap.
    if (!window.matchMedia('(hover: hover)').matches) return;

    const handleMove = (e: MouseEvent) => {
      const rect = el.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      // Reject when the cursor is outside our own bounding box (sidebar,
      // header, etc.) so the bloom doesn't follow off-screen and waste work.
      if (x < 0 || y < 0 || x > rect.width || y > rect.height) {
        pendingRef.current = null;
        if (mouse) setMouse(null);
        return;
      }
      pendingRef.current = { x, y };
      if (rafRef.current) return;
      rafRef.current = requestAnimationFrame(() => {
        rafRef.current = 0;
        if (pendingRef.current) setMouse(pendingRef.current);
      });
    };
    const handleLeave = () => {
      pendingRef.current = null;
      setMouse(null);
    };
    // Listen on window: lots of children of <main> have their own
    // background or pointer-events, so a listener on the container would
    // miss moves over cards/buttons. We translate to local coords with the
    // bounding rect above.
    window.addEventListener('mousemove', handleMove, { passive: true });
    window.addEventListener('mouseleave', handleLeave);
    return () => {
      window.removeEventListener('mousemove', handleMove);
      window.removeEventListener('mouseleave', handleLeave);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  // mouse intentionally omitted: handler reads via pendingRef + setMouse
  // (closure capture only matters for the bounds-clear branch, which is
  // safe even if `mouse` is briefly stale).
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Build the bloom: 2*radius cells on each axis = (2r)² candidate dots
  // around the cursor's nearest grid cell. Opacity = squared falloff so
  // the center spike feels brighter than a linear ramp would.
  const dots: { cx: number; cy: number; op: number }[] = [];
  if (mouse) {
    const cxDot = Math.round(mouse.x / width);
    const cyDot = Math.round(mouse.y / height);
    const maxDist = spotlightRadius * Math.max(width, height);
    for (let dy = -spotlightRadius; dy < spotlightRadius; dy++) {
      for (let dx = -spotlightRadius; dx < spotlightRadius; dx++) {
        const px = (cxDot + dx) * width + width / 2;
        const py = (cyDot + dy) * height + height / 2;
        const d = Math.hypot(px - mouse.x, py - mouse.y);
        const t = Math.max(0, 1 - d / maxDist);
        if (t > 0.02) {
          // Squared falloff — softer ring, brighter core. Capped under 1
          // so even the dead-center dot stays a hint of overlay, not a
          // solid puck.
          dots.push({ cx: px, cy: py, op: Math.min(0.95, t * t) });
        }
      }
    }
  }

  return (
    <div
      ref={containerRef}
      aria-hidden="true"
      className={`pointer-events-none absolute inset-0 ${className}`}
    >
      <svg className="absolute inset-0 h-full w-full">
        <defs>
          <pattern id={id} width={width} height={height} patternUnits="userSpaceOnUse">
            <circle cx={width / 2} cy={height / 2} r={cr} fill="currentColor" />
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill={`url(#${id})`} />
        {dots.length > 0 && (
          <g className={spotlightClassName}>
            {dots.map((d, i) => (
              // r slightly larger than the base dot so the bloom reads as
              // "the dot grew + darkened" rather than "a brighter dot
              // floats on top of the base one."
              <circle key={i} cx={d.cx} cy={d.cy} r={cr + 0.4} fill="currentColor" opacity={d.op} />
            ))}
          </g>
        )}
      </svg>
    </div>
  );
}
