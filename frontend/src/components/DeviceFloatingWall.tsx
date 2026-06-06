import {
  useState, useEffect, useCallback, useMemo, useLayoutEffect, useRef,
} from 'react';
import { useLocation, Link } from 'react-router-dom';
import {
  motion, useMotionValue, useTransform, useSpring, animate,
  useVelocity, type MotionValue,
} from 'framer-motion';
import {
  AiOutlineHeart, AiFillHeart,
  AiOutlineStar, AiFillStar,
  AiOutlineDownload, AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import type { DeviceProfile, Wallpaper } from '../types';
import { useWallpaperActions } from '../hooks/useWallpaperActions';

/**
 * DeviceFloatingWall — the draggable-mockup wallpaper canvas that
 * powers both DeviceWallpapersPage and DiscoverPage's grid view.
 *
 * Shape of the interaction (all encapsulated here):
 *   - Tiles are absolutely positioned on a measured canvas, sized
 *     to the device's display aspect.
 *   - A device-mockup motion.div sits in the top-left, draggable
 *     within the wall's rect. When the user drags it past 62% of a
 *     cell boundary, it snaps to the new cell; otherwise it springs
 *     back to where it was last parked.
 *   - As the mockup moves (drag, or one-row-at-a-time scroll-
 *     follow), adjacent tiles keep a stable layout box while their
 *     image surface dents at the contact edge with a small liquid
 *     push. No React re-renders during the interaction — framer-
 *     motion drives transforms on the DOM directly.
 *
 * The component is self-contained: it manages its own featured-tile
 * state, preview-mode (Plain/Home/Lock) state, and wall measurement
 * via ResizeObserver. Callers provide `device` + `wallpapers` and
 * optionally a viewport→cols mapping function (DiscoverPage passes
 * a size-mode-aware mapping; DeviceWallpapersPage uses the default).
 */

const DEFAULT_COLS_FOR_WIDTH = (w: number): number => {
  if (w >= 1800) return 5;
  if (w >= 1100) return 4;
  if (w >= 760) return 3;
  return 2;
};
const PREVIEW_SNAP_THRESHOLD = 0.62;

type WaveSide = 'none' | 'left' | 'right' | 'top' | 'bottom';

interface ContactWaveState {
  pressure: number;
  side: WaveSide;
  center: number;
}

const NO_WAVE: ContactWaveState = {
  pressure: 0,
  side: 'none',
  center: 0,
};

const clamp = (value: number, min: number, max: number) => Math.max(min, Math.min(max, value));
const smooth = (value: number) => {
  const t = clamp(value, 0, 1);
  return t * t * (3 - 2 * t);
};

const curvedWaveClipPath = (
  side: WaveSide,
  pressure: number,
  width: number,
  height: number,
  center: number,
) => {
  if (side === 'none' || pressure < 0.025 || width <= 0 || height <= 0) return 'inset(0 round 8px)';
  const w = Math.round(width);
  const h = Math.round(height);
  const horizontal = side === 'left' || side === 'right';
  const axisLength = horizontal ? h : w;
  const dent = Math.round(clamp(Math.min(w, h) * (0.035 + pressure * 0.115), 8, 42));
  const halfWave = clamp(axisLength * (0.16 + pressure * 0.10), 34, axisLength * 0.36);
  const c = clamp(center || axisLength / 2, halfWave + 6, axisLength - halfWave - 6);
  const a = Math.round(c - halfWave);
  const b = Math.round(c + halfWave);

  switch (side) {
    case 'left':
      return `path("M 0 0 H ${w} V ${h} H 0 V ${b} C ${dent} ${b} ${dent} ${a} 0 ${a} V 0 Z")`;
    case 'right':
      return `path("M 0 0 H ${w} V ${a} C ${w - dent} ${a} ${w - dent} ${b} ${w} ${b} V ${h} H 0 Z")`;
    case 'top':
      return `path("M 0 0 H ${a} C ${a} ${dent} ${b} ${dent} ${b} 0 H ${w} V ${h} H 0 Z")`;
    case 'bottom':
      return `path("M 0 0 H ${w} V ${h} H ${b} C ${b} ${h - dent} ${a} ${h - dent} ${a} ${h} H 0 Z")`;
    default:
      return 'inset(0 round 8px)';
  }
};

export interface DeviceFloatingWallProps {
  device: DeviceProfile;
  wallpapers: Wallpaper[];
  /** Optional viewport→cols mapping. */
  colsForWidth?: (w: number) => number;
  /** Notify the parent when the currently-featured wallpaper
   *  changes (hover). Used by DeviceWallpapersPage to drive the
   *  page-mesh palette. */
  onFeatureChange?: (wp: Wallpaper | null) => void;
  /** Reserve N skeleton tiles at the end of the wall while a
   *  pagination fetch is in flight. The wall grows to include
   *  them so the preview can scroll-follow into the loading area
   *  instead of stalling at the bottom of the last real tile. */
  pendingCount?: number;
}

export default function DeviceFloatingWall({
  device,
  wallpapers,
  colsForWidth = DEFAULT_COLS_FOR_WIDTH,
  onFeatureChange,
  pendingCount = 0,
}: DeviceFloatingWallProps) {
  const deviceAspect = (device.width || 16) / (device.height || 9);
  const mockupClass = `dev-mockup is-${device.platform}`;
  const isAppleDesktop = device.platform === 'desktop' && (device.brand || '').toLowerCase() === 'apple';

  // Featured tile — drives the mockup screen image and notifies
  // the parent (e.g., page mesh palette) of the change.
  const [featuredIdx, setFeaturedIdx] = useState(0);
  const featured = wallpapers[featuredIdx] ?? wallpapers[0] ?? null;
  const featuredCover = featured?.preview_url || featured?.thumb_url;
  const onTileHover = useCallback((idx: number) => setFeaturedIdx(idx), []);
  useEffect(() => {
    onFeatureChange?.(featured);
  }, [featured, onFeatureChange]);

  const [previewMode, setPreviewMode] = useState<'plain' | 'home' | 'lock'>('plain');

  // ── Wall measurement (callback ref handles conditional mount) ──
  const [wallEl, setWallEl] = useState<HTMLDivElement | null>(null);
  const wallRef = useCallback((el: HTMLDivElement | null) => setWallEl(el), []);
  const [wallWidth, setWallWidth] = useState(0);
  useLayoutEffect(() => {
    if (!wallEl) return;
    const update = () => setWallWidth(wallEl.clientWidth);
    update();
    const ro = new ResizeObserver(update);
    ro.observe(wallEl);
    return () => ro.disconnect();
  }, [wallEl]);

  const cols = useMemo(() => colsForWidth(wallWidth), [wallWidth, colsForWidth]);
  const gap = 12;
  const tileW = wallWidth > 0 ? (wallWidth - gap * (cols - 1)) / cols : 0;
  const rawTileH = tileW / (deviceAspect || 1.78);
  const tileH = Math.max(140, Math.min(480, rawTileH));

  const previewColSpan = 2;
  const previewRowSpan = 2;
  const previewW = tileW * previewColSpan + gap * (previewColSpan - 1);
  const previewH = tileH * previewRowSpan + gap * (previewRowSpan - 1);

  // Mockup sizing — solve for the largest aspect-correct screen
  // rect that fits the available content area minus padding,
  // mode-toggle row, and platform-specific chrome (stand / base).
  const mockupSize = useMemo(() => {
    if (previewW <= 0 || previewH <= 0) return { w: 0, h: 0 };
    const padX = 28;
    const padY = 26;
    const togglesH = 30;
    const innerGap = 12;
    let chromeH = 0;
    if (device.platform === 'desktop' && !isAppleDesktop) chromeH = 36;
    else if (device.platform === 'laptop') chromeH = 18;
    const availW = Math.max(40, previewW - padX);
    const availH = Math.max(40, previewH - padY - togglesH - innerGap - chromeH);
    const widthBoundH = availW / deviceAspect;
    const heightBoundW = availH * deviceAspect;
    const w = widthBoundH <= availH ? availW : heightBoundW;
    const h = widthBoundH <= availH ? widthBoundH : availH;
    return { w: Math.floor(w), h: Math.floor(h) };
  }, [previewW, previewH, deviceAspect, device.platform, isAppleDesktop]);

  // ── Preview motion state ──────────────────────────────────────
  const previewX = useMotionValue(0);
  const previewY = useMotionValue(0);
  const previewVX = useVelocity(previewX);
  const previewVY = useVelocity(previewY);
  const [isDragging, setIsDragging] = useState(false);
  const [parkedCell, setParkedCell] = useState({ col: 0, row: 0 });

  // Scroll-follow — writes directly into previewY (not via state +
  // spring) so the preview tracks smooth-scroll updates frame-by-
  // frame. The earlier spring-based version restarted its animation
  // on every scroll event, so by the time the spring made any
  // visible progress the next event had cancelled it; "back to top"
  // looked like the preview never moved. Direct .set() bypasses
  // that. Spring is only used for drag-end settle below.
  const parkedRef = useRef(parkedCell);
  parkedRef.current = parkedCell;
  const isDraggingRef = useRef(isDragging);
  isDraggingRef.current = isDragging;

  // Continuous scroll-follow Y (no row snap during scroll). The
  // 62% hysteresis on previewCol/RowMV below converts the
  // continuous Y into discrete previewCell jumps, which is what
  // drives tile reflow — so as the user scrolls, tiles around
  // the preview compress (dent) just like during drag, then pop
  // past at the 70% threshold. Once scroll idles, a debounced
  // settle springs the preview to its current discrete cell so
  // it lands cleanly on a grid boundary.
  const computeFollowY = useCallback((): number => {
    if (!wallEl) return 0;
    const rect = wallEl.getBoundingClientRect();
    const headerInset = 100;
    const followTarget = Math.max(0, headerInset - rect.top);
    const maxY = Math.max(0, rect.height - previewH);
    const baseY = parkedRef.current.row * (tileH + gap);
    return Math.min(maxY, Math.max(baseY, followTarget));
  }, [wallEl, tileH, gap, previewH]);

  const previewCellRef = useRef({ col: 0, row: 0 });
  useEffect(() => {
    let idleTimer: number | undefined;
    const update = () => {
      if (isDraggingRef.current) return;
      previewY.set(computeFollowY());
      if (idleTimer !== undefined) window.clearTimeout(idleTimer);
      // Once scroll has been idle for 250ms, spring previewY to
      // the discrete-cell-aligned home so it doesn't rest between
      // rows.
      if (tileH > 0) {
        idleTimer = window.setTimeout(() => {
          if (isDraggingRef.current) return;
          const cellH = tileH + gap;
          const baseY = parkedRef.current.row * cellH;
          const target = Math.max(baseY, previewCellRef.current.row * cellH);
          animate(previewY, target, { type: 'spring', stiffness: 200, damping: 30 });
        }, 250);
      }
    };
    update();
    window.addEventListener('scroll', update, { passive: true });
    window.addEventListener('resize', update);
    return () => {
      window.removeEventListener('scroll', update);
      window.removeEventListener('resize', update);
      if (idleTimer !== undefined) window.clearTimeout(idleTimer);
    };
  }, [computeFollowY, previewY, tileH, gap]);

  // Drag-end settle — only fires on isDragging or parkedCell
  // change (not on scroll); the scroll listener handles its own Y
  // updates with the idle-snap timer.
  useEffect(() => {
    if (isDragging) return;
    const targetX = parkedCell.col * (tileW + gap);
    const targetY = computeFollowY();
    const ax = animate(previewX, targetX, { type: 'spring', stiffness: 220, damping: 28 });
    const ay = animate(previewY, targetY, { type: 'spring', stiffness: 220, damping: 28 });
    return () => { ax.stop(); ay.stop(); };
  }, [isDragging, parkedCell.col, parkedCell.row, tileW, gap, computeFollowY, previewX, previewY]);

  // 62% hysteresis snap for the running preview cell.
  const previewColMV = useTransform(previewX, (x) => {
    if (tileW <= 0) return 0;
    const cellW = tileW + gap;
    const base = Math.floor(x / cellW);
    const progress = (x - base * cellW) / cellW;
    const c = progress > PREVIEW_SNAP_THRESHOLD ? base + 1 : base;
    return Math.max(0, Math.min(cols - previewColSpan, c));
  });
  const previewRowMV = useTransform(previewY, (y) => {
    if (tileH <= 0) return 0;
    const cellH = tileH + gap;
    const base = Math.floor(y / cellH);
    const progress = (y - base * cellH) / cellH;
    const r = progress > PREVIEW_SNAP_THRESHOLD ? base + 1 : base;
    return Math.max(0, r);
  });
  const [previewCell, setPreviewCell] = useState({ col: 0, row: 0 });
  previewCellRef.current = previewCell;
  useEffect(() => {
    const u1 = previewColMV.on('change', (v) => setPreviewCell((p) => p.col === v ? p : { ...p, col: v }));
    const u2 = previewRowMV.on('change', (v) => setPreviewCell((p) => p.row === v ? p : { ...p, row: v }));
    return () => { u1(); u2(); };
  }, [previewColMV, previewRowMV]);

  // Tile positions — array of { left, top, w, h } per wallpaper,
  // computed per mode.
  //
  // Walk row-major, skip cells inside the preview's current
  // footprint (driven by previewCell, which moves with the 70%
  // hysteresis snap). Length = wallpapers + pending placeholders;
  // the parent passes pendingCount > 0 while a paginated fetch is
  // in flight, so the wall reserves space for the incoming tiles
  // and the scroll-follow preview has somewhere to go instead of
  // jamming at the last loaded row.
  const totalCount = wallpapers.length + pendingCount;
  const tilePositions = useMemo<{ left: number; top: number; w: number; h: number }[]>(() => {
    if (totalCount === 0 || wallWidth <= 0 || cols <= 0 || tileW <= 0) return [];
    const out: { left: number; top: number; w: number; h: number }[] = [];
    const { col: pc, row: pr } = previewCell;
    const pcsEnd = pc + previewColSpan;
    const prsEnd = pr + previewRowSpan;
    let r = 0, c = 0;
    while (out.length < totalCount) {
      const inPreview = c >= pc && c < pcsEnd && r >= pr && r < prsEnd;
      if (!inPreview) {
        out.push({
          left: c * (tileW + gap),
          top: r * (tileH + gap),
          w: tileW,
          h: tileH,
        });
      }
      c++;
      if (c >= cols) { c = 0; r++; }
      if (r > totalCount + 4) break;
    }
    return out;
  }, [totalCount, wallWidth, cols, tileW, tileH, gap, previewCell.col, previewCell.row]);

  const wallHeight = useMemo(() => {
    if (wallpapers.length === 0) return previewH;
    let maxBottom = previewH; // preview always claims its footprint
    for (const p of tilePositions) {
      const bottom = p.top + p.h;
      if (bottom > maxBottom) maxBottom = bottom;
    }
    return maxBottom;
  }, [tilePositions, previewH, wallpapers.length]);

  return (
    <div ref={wallRef} className="dev-wall-area" style={{ height: wallHeight }}>
      {wallWidth > 0 && (
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
          onDragEnd={() => {
            setIsDragging(false);
            setParkedCell({ col: previewCell.col, row: previewCell.row });
          }}
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
                width: mockupSize.w || undefined,
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

      {wallpapers.map((wp, i) => {
        const pos = tilePositions[i];
        if (!pos) return null;
        return (
          <DevWallSlot
            key={wp.id}
            wp={wp}
            device={device}
            index={i}
            isFeatured={i === featuredIdx}
            onHover={onTileHover}
            targetLeft={pos.left}
            targetTop={pos.top}
            tileW={pos.w}
            tileH={pos.h}
            previewX={previewX}
            previewY={previewY}
            previewVX={previewVX}
            previewVY={previewVY}
            previewW={previewW}
            previewH={previewH}
            gap={gap}
          />
        );
      })}
      {/* Pending placeholders — skeleton tiles for the in-flight
          page. Outer slot is absolutely positioned; the inner card
          carries the skeleton shimmer + dev-spec-card chrome.
          They must be separate elements because .dev-wall-slot
          (position: absolute) and .dev-spec-card (position:
          relative) both set `position`, and the latter loses
          when combined on the same node — the placeholder ended
          up in normal flow at the top of the wall instead of at
          the bottom. */}
      {pendingCount > 0 && Array.from({ length: pendingCount }).map((_, k) => {
        const i = wallpapers.length + k;
        const pos = tilePositions[i];
        if (!pos) return null;
        return (
          <div
            key={`pending-${k}`}
            className="dev-wall-slot"
            style={{
              transform: `translate(${pos.left}px, ${pos.top}px)`,
              width: pos.w,
              height: pos.h,
            }}
            aria-hidden
          >
            <div
              className="dev-spec-card skeleton-card"
              style={{ width: '100%', height: '100%', animationDelay: `${k * 30}ms` }}
            />
          </div>
        );
      })}
    </div>
  );
}

/* DevWallSlot — one wallpaper tile, absolutely positioned. Owns a
   useSpring for its assigned cell + a contact-wave MotionValue for
   the liquid edge deformation. See DeviceFloatingWall for the
   overall interaction model. */
function DevWallSlot({
  wp, device, index, isFeatured, onHover,
  targetLeft, targetTop,
  tileW, tileH,
  previewX, previewY, previewVX, previewVY, previewW, previewH, gap,
}: {
  wp: Wallpaper;
  device: DeviceProfile;
  index: number;
  isFeatured: boolean;
  onHover: (idx: number) => void;
  targetLeft: number;
  targetTop: number;
  tileW: number;
  tileH: number;
  previewX: MotionValue<number>;
  previewY: MotionValue<number>;
  previewVX: MotionValue<number>;
  previewVY: MotionValue<number>;
  previewW: number;
  previewH: number;
  gap: number;
}) {
  const cellX = useSpring(targetLeft, { stiffness: 240, damping: 28, mass: 0.6 });
  const cellY = useSpring(targetTop, { stiffness: 240, damping: 28, mass: 0.6 });
  useEffect(() => { cellX.set(targetLeft); }, [targetLeft, cellX]);
  useEffect(() => { cellY.set(targetTop); }, [targetTop, cellY]);

  const computeWave = (
    cx: number,
    cy: number,
    px: number,
    py: number,
    vx: number,
    vy: number,
  ): ContactWaveState => {
    if (tileW <= 0 || tileH <= 0 || previewW <= 0 || previewH <= 0) return NO_WAVE;

    const tileRight = cx + tileW;
    const tileBottom = cy + tileH;
    const previewRight = px + previewW;
    const previewBottom = py + previewH;
    const xSpan = Math.min(tileRight, previewRight) - Math.max(cx, px);
    const ySpan = Math.min(tileBottom, previewBottom) - Math.max(cy, py);
    const tileCenterX = cx + tileW / 2;
    const tileCenterY = cy + tileH / 2;
    const previewCenterX = px + previewW / 2;
    const previewCenterY = py + previewH / 2;
    const radius = clamp(Math.min(tileW, tileH) * 0.24, 42, 92);
    const pick = (a: ContactWaveState, b: ContactWaveState) => (b.pressure > a.pressure ? b : a);
    let best = NO_WAVE;

    const makeState = (side: WaveSide, pressure: number, center: number): ContactWaveState => ({
      side,
      pressure: smooth(pressure),
      center,
    });

    if (xSpan > 0 && ySpan > 0) {
      const xRatio = xSpan / Math.max(tileW, 1);
      const yRatio = ySpan / Math.max(tileH, 1);
      if (xRatio <= yRatio) {
        const fromRight = tileCenterX >= previewCenterX;
        best = pick(best, makeState(
          fromRight ? 'left' : 'right',
          0.44 + clamp(xRatio, 0, 1) * 0.42,
          clamp(previewCenterY - cy, tileH * 0.2, tileH * 0.8),
        ));
      } else {
        const fromBottom = tileCenterY >= previewCenterY;
        best = pick(best, makeState(
          fromBottom ? 'top' : 'bottom',
          0.44 + clamp(yRatio, 0, 1) * 0.42,
          clamp(previewCenterX - cx, tileW * 0.2, tileW * 0.8),
        ));
      }
    } else {
      const horizontalGap = cx >= previewRight
        ? cx - previewRight
        : px >= tileRight
          ? px - tileRight
          : 0;
      const verticalGap = cy >= previewBottom
        ? cy - previewBottom
        : py >= tileBottom
          ? py - tileBottom
          : 0;
      const nearHorizontalFace = horizontalGap > 0 && horizontalGap <= radius && ySpan > -radius * 0.45;
      const nearVerticalFace = verticalGap > 0 && verticalGap <= radius && xSpan > -radius * 0.45;

      if (nearHorizontalFace && (!nearVerticalFace || horizontalGap <= verticalGap)) {
        const fromRight = tileCenterX >= previewCenterX;
        best = pick(best, makeState(
          fromRight ? 'left' : 'right',
          Math.pow(1 - horizontalGap / radius, 1.45) * 0.54,
          clamp(previewCenterY - cy, tileH * 0.2, tileH * 0.8),
        ));
      } else if (nearVerticalFace) {
        const fromBottom = tileCenterY >= previewCenterY;
        best = pick(best, makeState(
          fromBottom ? 'top' : 'bottom',
          Math.pow(1 - verticalGap / radius, 1.45) * 0.54,
          clamp(previewCenterX - cx, tileW * 0.2, tileW * 0.8),
        ));
      }
    }

    const cellW = tileW + gap;
    const cellH = tileH + gap;
    const absVX = Math.abs(vx);
    const absVY = Math.abs(vy);
    const velocity = Math.max(absVX, absVY);

    if (velocity > 24) {
      if (absVY >= absVX) {
        const dir = vy >= 0 ? 1 : -1;
        const gridY = py / cellH;
        const frac = gridY - Math.floor(gridY);
        const progress = dir > 0 ? frac / PREVIEW_SNAP_THRESHOLD : (1 - frac) / PREVIEW_SNAP_THRESHOLD;
        const crossOverlap = Math.min(tileRight, previewRight) - Math.max(cx, px);
        if (crossOverlap > tileW * 0.08) {
          const distance = dir > 0 ? cy - previewBottom : py - tileBottom;
          if (distance > -tileH * 0.55) {
            const rank = Math.floor(Math.max(distance, 0) / cellH);
            if (rank >= 0 && rank <= 2) {
              const starts = [0.02, 0.24, 0.44];
              const weights = [0.95, 0.62, 0.38];
              const local = (clamp(progress, 0, 1.08) - starts[rank]) / Math.max(0.01, 1 - starts[rank]);
              if (local > 0) {
                best = pick(best, makeState(
                  dir > 0 ? 'top' : 'bottom',
                  clamp(local, 0, 1) * weights[rank],
                  clamp(previewCenterX - cx, tileW * 0.18, tileW * 0.82),
                ));
              }
            }
          }
        }
      } else {
        const dir = vx >= 0 ? 1 : -1;
        const gridX = px / cellW;
        const frac = gridX - Math.floor(gridX);
        const progress = dir > 0 ? frac / PREVIEW_SNAP_THRESHOLD : (1 - frac) / PREVIEW_SNAP_THRESHOLD;
        const crossOverlap = Math.min(tileBottom, previewBottom) - Math.max(cy, py);
        if (crossOverlap > tileH * 0.08) {
          const distance = dir > 0 ? cx - previewRight : px - tileRight;
          if (distance > -tileW * 0.55) {
            const rank = Math.floor(Math.max(distance, 0) / cellW);
            if (rank >= 0 && rank <= 2) {
              const starts = [0.02, 0.24, 0.44];
              const weights = [0.95, 0.62, 0.38];
              const local = (clamp(progress, 0, 1.08) - starts[rank]) / Math.max(0.01, 1 - starts[rank]);
              if (local > 0) {
                best = pick(best, makeState(
                  dir > 0 ? 'left' : 'right',
                  clamp(local, 0, 1) * weights[rank],
                  clamp(previewCenterY - cy, tileH * 0.18, tileH * 0.82),
                ));
              }
            }
          }
        }
      }
    }

    return best.pressure > 0 ? best : NO_WAVE;
  };

  const wave = useTransform([cellX, cellY, previewX, previewY, previewVX, previewVY], ([cx, cy, px, py, vx, vy]) => (
    computeWave(cx as number, cy as number, px as number, py as number, vx as number, vy as number)
  ));
  const imageClipPath = useTransform(wave, (state) => (
    curvedWaveClipPath(state.side, state.pressure, tileW, tileH, state.center)
  ));
  const waveLeftOpacity = useTransform(wave, (state) => state.side === 'left' ? state.pressure : 0);
  const waveRightOpacity = useTransform(wave, (state) => state.side === 'right' ? state.pressure : 0);
  const waveTopOpacity = useTransform(wave, (state) => state.side === 'top' ? state.pressure : 0);
  const waveBottomOpacity = useTransform(wave, (state) => state.side === 'bottom' ? state.pressure : 0);

  return (
    <motion.div
      className="dev-wall-slot"
      style={{ x: cellX, y: cellY, width: tileW, height: tileH }}
    >
      <motion.div
        className="dev-wall-ripple-body"
      >
        <DevTile
          wallpaper={wp}
          device={device}
          index={index}
          isFeatured={isFeatured}
          onHover={onHover}
          imageClipPath={imageClipPath}
          waveLeftOpacity={waveLeftOpacity}
          waveRightOpacity={waveRightOpacity}
          waveTopOpacity={waveTopOpacity}
          waveBottomOpacity={waveBottomOpacity}
        />
      </motion.div>
    </motion.div>
  );
}

function DevTile({
  wallpaper: w, device, index, isFeatured, onHover,
  imageClipPath,
  waveLeftOpacity, waveRightOpacity, waveTopOpacity, waveBottomOpacity,
}: {
  wallpaper: Wallpaper;
  device: DeviceProfile;
  index: number;
  isFeatured: boolean;
  onHover: (idx: number) => void;
  imageClipPath?: MotionValue<string>;
  waveLeftOpacity?: MotionValue<number>;
  waveRightOpacity?: MotionValue<number>;
  waveTopOpacity?: MotionValue<number>;
  waveBottomOpacity?: MotionValue<number>;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const aspect = `${device.width} / ${device.height}`;
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };
  // Tag chips: resolution band + video / mac-dynamic / AI flags.
  // Same vocabulary as the salon WallpaperCard so the tile reads
  // consistent across surfaces.
  const isVideo = (w.file_type || '').startsWith('video/');
  const resPx = Math.max(w.width || 0, w.height || 0);
  const resLabel = resPx >= 7680 ? '8K'
    : resPx >= 3840 ? '4K'
    : resPx >= 2560 ? '2K'
    : resPx >= 1920 ? '1080P'
    : resPx >= 1280 ? '720P'
    : '';
  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      className={`dev-spec-card${isFeatured ? ' is-featured' : ''}`}
      // Cap the stagger delay. The unbounded `index * 30ms` was
      // delaying paginated tiles by literal seconds (tile #275 →
      // 8.25s of opacity-0 from cd-frame-in's `both` fill), so
      // newly-arrived tiles looked invisible after the pending
      // skeleton vanished. Cap at 16 tiles' worth → max 480ms.
      style={{ animationDelay: `${Math.min(index, 16) * 30}ms` }}
      onMouseEnter={() => onHover(index)}
    >
      <motion.div
        className="dev-spec-card-screen"
        style={{ aspectRatio: aspect }}
      >
        <motion.div
          className="dev-spec-card-image-shell"
          style={{ clipPath: imageClipPath }}
        >
          <img
            src={w.preview_url || w.thumb_url}
            alt={w.title || `Wallpaper ${w.id}`}
            loading="lazy"
            className="dev-spec-card-img"
            style={{ backgroundColor: w.dominant_color || undefined }}
          />
        </motion.div>
        <motion.span className="dev-spec-card-wave is-left" style={{ opacity: waveLeftOpacity }} aria-hidden />
        <motion.span className="dev-spec-card-wave is-right" style={{ opacity: waveRightOpacity }} aria-hidden />
        <motion.span className="dev-spec-card-wave is-top" style={{ opacity: waveTopOpacity }} aria-hidden />
        <motion.span className="dev-spec-card-wave is-bottom" style={{ opacity: waveBottomOpacity }} aria-hidden />
        {/* Top-left chip strip — resolution + video / mac-dynamic /
            AI badges. Same component vocabulary as the salon
            WallpaperCard. Positioned absolutely on top of the
            preview image so they read at a glance. */}
        {(resLabel || isVideo || w.is_dynamic || w.is_ai_generated) && (
          <div className="absolute top-2.5 left-2.5 z-[3] flex gap-1 flex-wrap max-w-[calc(100%-20px)]">
            {resLabel && <span className="tile-chip">{resLabel}</span>}
            {(isVideo || w.is_dynamic) && (
              <span className="tile-chip">
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z" /></svg>
                Live
              </span>
            )}
            {w.is_ai_generated && (
              <span className="tile-chip is-ai">
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z" /></svg>
                AI
              </span>
            )}
          </div>
        )}
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
      </motion.div>
    </Link>
  );
}

function PreviewLockOverlay({ platform }: { platform: DeviceProfile['platform'] }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 30000);
    return () => clearInterval(id);
  }, []);
  const time = now.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });
  const date = now.toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
  const topAnchor = platform === 'phone' ? '14%' : platform === 'tablet' ? '20%' : '32%';
  return (
    <div className="dev-overlay-lock" style={{ paddingTop: topAnchor }} aria-hidden>
      <div className="dev-overlay-lock-time">{time}</div>
      <div className="dev-overlay-lock-date">{date}</div>
    </div>
  );
}

function PreviewHomeOverlay({ platform }: { platform: DeviceProfile['platform'] }) {
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
