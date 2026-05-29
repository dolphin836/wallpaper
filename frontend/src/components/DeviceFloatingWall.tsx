import {
  useState, useEffect, useCallback, useMemo, useLayoutEffect, useRef,
} from 'react';
import { useLocation, Link } from 'react-router-dom';
import {
  motion, useMotionValue, useTransform, useSpring, animate,
  type MotionValue,
} from 'framer-motion';
/* Custom obstacle-aware justified packer used by 'justified' mode.
   justified-layout's library doesn't know how to lay tiles around
   a fixed rectangle, so a vanilla two-pass approach (strip next
   to obstacle + rest below) was leaving a visible gap below the
   short strip row whenever the natural row height didn't match
   the obstacle height. This packer walks rows top-down: for each
   row it decides the leftBound + available width based on whether
   the row's vertical span overlaps the obstacle, packs items
   greedily until the natural row height drops to targetRowH, and
   either commits the row or skips past the obstacle when the row
   wouldn't fit cleanly inside the remaining obstacle band. */
function obstacleAwareJustified(
  ratios: number[],
  containerW: number,
  obstacle: { w: number; h: number },
  targetRowH: number,
  gap: number,
): { positions: { left: number; top: number; w: number; h: number }[]; totalH: number } {
  const out: { left: number; top: number; w: number; h: number }[] = [];
  let y = 0;
  let idx = 0;
  while (idx < ratios.length) {
    const inObs = y < obstacle.h;
    const leftBound = inObs ? obstacle.w + gap : 0;
    const availW = containerW - leftBound;
    if (availW < 80) {
      y = obstacle.h + gap;
      continue;
    }
    let cumAspect = 0;
    let count = 0;
    while (idx + count < ratios.length) {
      cumAspect += ratios[idx + count];
      count++;
      const tentH = (availW - (count - 1) * gap) / cumAspect;
      if (tentH <= targetRowH) break;
    }
    if (count === 0) break;
    let rowH = (availW - (count - 1) * gap) / cumAspect;
    // If this row would extend past the obstacle band by more than
    // a small margin, advance to below-obstacle territory and
    // re-pack from full width on the next iteration.
    if (inObs && y + rowH > obstacle.h + 1) {
      const remaining = obstacle.h - y;
      if (rowH > remaining * 1.6) {
        y = obstacle.h + gap;
        continue;
      }
      // Otherwise stretch the row to exactly fill the band so
      // there's no empty stripe below it. Items distort slightly
      // (their visual aspect tracks rowH, not their source
      // ratio) but the wall reads as continuous.
      rowH = Math.max(60, remaining);
    }
    let x = leftBound;
    for (let i = 0; i < count; i++) {
      const w = ratios[idx + i] * rowH;
      out.push({ left: x, top: y, w, h: rowH });
      x += w + gap;
    }
    idx += count;
    y += rowH + gap;
  }
  return { positions: out, totalH: y };
}
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
 *     within the wall's rect. When the user drags it past 70% of a
 *     cell boundary, it snaps to the new cell; otherwise it springs
 *     back to where it was last parked.
 *   - As the mockup moves (drag, or one-row-at-a-time scroll-
 *     follow), each tile that overlaps its bounding box dents
 *     inward via a one-sided scale with transform-origin pinned to
 *     the far edge. No React re-renders during the interaction —
 *     framer-motion drives transforms on the DOM directly.
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

export interface DeviceFloatingWallProps {
  device: DeviceProfile;
  wallpapers: Wallpaper[];
  /** Layout style: 'grid' (uniform device-aspect cells, default) or
   *  'justified' (variable-width tiles via justified-layout with the
   *  preview pinned at top-left and a narrow strip of tiles next to
   *  it). */
  mode?: 'grid' | 'justified';
  /** Optional viewport→cols mapping for 'grid' mode. */
  colsForWidth?: (w: number) => number;
  /** Target row height for 'justified' mode (matches WallpaperGrid
   *  SIZE_HEIGHTS). Ignored in grid mode. */
  justifiedRowHeight?: number;
  /** Notify the parent when the currently-featured wallpaper
   *  changes (hover). Used by DeviceWallpapersPage to drive the
   *  page-mesh palette. */
  onFeatureChange?: (wp: Wallpaper | null) => void;
}

export default function DeviceFloatingWall({
  device,
  wallpapers,
  mode = 'grid',
  colsForWidth = DEFAULT_COLS_FOR_WIDTH,
  justifiedRowHeight = 280,
  onFeatureChange,
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
  // Grid-mode tile dimensions (uniform). Ignored in justified mode
  // but kept here so the preview size derivation in grid mode is
  // unchanged.
  const tileW = wallWidth > 0 ? (wallWidth - gap * (cols - 1)) / cols : 0;
  const rawTileH = tileW / (deviceAspect || 1.78);
  const tileH = Math.max(140, Math.min(480, rawTileH));

  const previewColSpan = 2;
  const previewRowSpan = 2;
  const { previewW, previewH } = useMemo(() => {
    if (mode === 'grid') {
      return {
        previewW: tileW * previewColSpan + gap * (previewColSpan - 1),
        previewH: tileH * previewRowSpan + gap * (previewRowSpan - 1),
      };
    }
    // Justified mode: size the preview to an *integer* number of
    // justified rows so tiles in the side strip share the same
    // exact row height as the rest of the wall (avoids the gap
    // below short strip tiles). Walk N = 1..3 picking the largest
    // that still leaves a reasonable side-strip width (~280px).
    const minStripW = 280;
    const maxPreviewW = Math.max(160, wallWidth - minStripW - gap);
    let bestN = 1;
    for (let N = 1; N <= 3; N++) {
      const h = N * justifiedRowHeight + (N - 1) * gap;
      const w = h * deviceAspect;
      if (w > maxPreviewW) break;
      bestN = N;
    }
    let previewH = bestN * justifiedRowHeight + (bestN - 1) * gap;
    let previewW = previewH * deviceAspect;
    // If even N=1 overflows the cap (very narrow wall), shrink the
    // preview proportionally and accept that strip tiles will be
    // shorter than the rest of the wall.
    if (previewW > maxPreviewW) {
      previewW = maxPreviewW;
      previewH = previewW / deviceAspect;
    }
    return { previewW, previewH };
  }, [mode, tileW, tileH, deviceAspect, justifiedRowHeight, wallWidth]);

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
  // 70% hysteresis on previewCol/RowMV below converts the
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
    if (mode === 'grid') {
      const baseY = parkedRef.current.row * (tileH + gap);
      return Math.min(maxY, Math.max(baseY, followTarget));
    }
    return Math.min(maxY, followTarget);
  }, [wallEl, mode, tileH, gap, previewH]);

  const previewCellRef = useRef({ col: 0, row: 0 });
  useEffect(() => {
    let idleTimer: number | undefined;
    const update = () => {
      if (isDraggingRef.current) return;
      previewY.set(computeFollowY());
      if (idleTimer !== undefined) window.clearTimeout(idleTimer);
      // Grid mode only — once scroll has been idle for 250ms,
      // spring previewY to the discrete-cell-aligned home so it
      // doesn't rest between rows.
      if (mode === 'grid' && tileH > 0) {
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
  }, [computeFollowY, previewY, mode, tileH, gap]);

  // Drag-end settle — only fires on isDragging or parkedCell
  // change (not on scroll); the scroll listener handles its own Y
  // updates with the idle-snap timer.
  useEffect(() => {
    if (isDragging) return;
    const targetX = mode === 'grid' ? parkedCell.col * (tileW + gap) : 0;
    const targetY = computeFollowY();
    const ax = animate(previewX, targetX, { type: 'spring', stiffness: 220, damping: 28 });
    const ay = animate(previewY, targetY, { type: 'spring', stiffness: 220, damping: 28 });
    return () => { ax.stop(); ay.stop(); };
  }, [mode, isDragging, parkedCell.col, parkedCell.row, tileW, gap, computeFollowY, previewX, previewY]);

  // 70% hysteresis snap for the running preview cell — grid mode
  // only (justified has no notion of discrete cells, preview stays
  // at home (0, 0) regardless).
  const SNAP_THRESHOLD = 0.7;
  const previewColMV = useTransform(previewX, (x) => {
    if (mode !== 'grid' || tileW <= 0) return 0;
    const cellW = tileW + gap;
    const base = Math.floor(x / cellW);
    const progress = (x - base * cellW) / cellW;
    const c = progress > SNAP_THRESHOLD ? base + 1 : base;
    return Math.max(0, Math.min(cols - previewColSpan, c));
  });
  const previewRowMV = useTransform(previewY, (y) => {
    if (mode !== 'grid' || tileH <= 0) return 0;
    const cellH = tileH + gap;
    const base = Math.floor(y / cellH);
    const progress = (y - base * cellH) / cellH;
    const r = progress > SNAP_THRESHOLD ? base + 1 : base;
    return Math.max(0, r);
  });
  const [previewCell, setPreviewCell] = useState({ col: 0, row: 0 });
  previewCellRef.current = previewCell;
  useEffect(() => {
    if (mode !== 'grid') {
      setPreviewCell({ col: 0, row: 0 });
      return;
    }
    const u1 = previewColMV.on('change', (v) => setPreviewCell((p) => p.col === v ? p : { ...p, col: v }));
    const u2 = previewRowMV.on('change', (v) => setPreviewCell((p) => p.row === v ? p : { ...p, row: v }));
    return () => { u1(); u2(); };
  }, [mode, previewColMV, previewRowMV]);

  // Tile positions — array of { left, top, w, h } per wallpaper,
  // computed per mode.
  //
  // GRID: walk row-major, skip cells inside the preview's current
  // footprint (driven by previewCell, which moves with the 70%
  // hysteresis snap).
  //
  // JUSTIFIED: two-pass justified-layout. Pass 1 fits as many
  // items as it can into a narrow strip next to the preview (width
  // = wallWidth - previewW - gap, target row height ≈ previewH/2);
  // pass 2 lays the remainder below the preview row at full width.
  // Result reads as "wallpapers naturally flow around the device
  // at top-left" instead of "preview occludes a chunk of the wall".
  const tilePositions = useMemo<{ left: number; top: number; w: number; h: number }[]>(() => {
    const n = wallpapers.length;
    if (n === 0 || wallWidth <= 0) return [];
    if (mode === 'grid') {
      if (cols <= 0 || tileW <= 0) return [];
      const out: { left: number; top: number; w: number; h: number }[] = [];
      const { col: pc, row: pr } = previewCell;
      const pcsEnd = pc + previewColSpan;
      const prsEnd = pr + previewRowSpan;
      let r = 0, c = 0;
      while (out.length < n) {
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
        if (r > n + 4) break;
      }
      return out;
    }
    // Obstacle-aware row-by-row packer — treats the preview as a
    // top-left rectangle and packs justified rows around it.
    const ratios = wallpapers.map((w) => (w.width > 0 && w.height > 0 ? w.width / w.height : 4 / 3));
    const { positions } = obstacleAwareJustified(
      ratios,
      wallWidth,
      { w: previewW, h: previewH },
      justifiedRowHeight,
      gap,
    );
    return positions;
  }, [mode, wallpapers, wallWidth, cols, tileW, tileH, gap, previewCell.col, previewCell.row, previewW, previewH, justifiedRowHeight]);

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
            // Only grid mode "parks" the preview at the discrete
            // cell the user reached; justified mode always springs
            // back to (0, 0) home.
            if (mode === 'grid') {
              setParkedCell({ col: previewCell.col, row: previewCell.row });
            }
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
            previewW={previewW}
            previewH={previewH}
          />
        );
      })}
    </div>
  );
}

/* DevWallSlot — one wallpaper tile, absolutely positioned. Owns a
   useSpring for its assigned cell + useTransforms for the live
   overlap-driven directional dent. See DeviceFloatingWall for the
   overall interaction model. */
function DevWallSlot({
  wp, device, index, isFeatured, onHover,
  targetLeft, targetTop,
  tileW, tileH,
  previewX, previewY, previewW, previewH,
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
  previewW: number;
  previewH: number;
}) {
  const cellX = useSpring(targetLeft, { stiffness: 240, damping: 28, mass: 0.6 });
  const cellY = useSpring(targetTop, { stiffness: 240, damping: 28, mass: 0.6 });
  useEffect(() => { cellX.set(targetLeft); }, [targetLeft, cellX]);
  useEffect(() => { cellY.set(targetTop); }, [targetTop, cellY]);

  const computeSquish = (cx: number, cy: number, px: number, py: number) => {
    if (tileW <= 0 || tileH <= 0) return null;
    const xOv = Math.max(0, Math.min(cx + tileW, px + previewW) - Math.max(cx, px));
    const yOv = Math.max(0, Math.min(cy + tileH, py + previewH) - Math.max(cy, py));
    if (xOv === 0 || yOv === 0) return null;
    const dx = (cx + tileW / 2) - (px + previewW / 2);
    const dy = (cy + tileH / 2) - (py + previewH / 2);
    const xRatio = Math.min(1, xOv / tileW);
    const yRatio = Math.min(1, yOv / tileH);
    const DENT_MAX = 0.20;
    let scaleX = 1;
    let scaleY = 1;
    let origin = '50% 50%';
    if (xRatio > yRatio) {
      scaleY = 1 - Math.min(DENT_MAX, yRatio * 0.7);
      const oy = dy > 0 ? '100%' : '0%';
      origin = `50% ${oy}`;
    } else {
      scaleX = 1 - Math.min(DENT_MAX, xRatio * 0.7);
      const ox = dx > 0 ? '100%' : '0%';
      origin = `${ox} 50%`;
    }
    return { scaleX, scaleY, origin };
  };

  const scaleX = useTransform([cellX, cellY, previewX, previewY], ([cx, cy, px, py]) => {
    const s = computeSquish(cx as number, cy as number, px as number, py as number);
    return s?.scaleX ?? 1;
  });
  const scaleY = useTransform([cellX, cellY, previewX, previewY], ([cx, cy, px, py]) => {
    const s = computeSquish(cx as number, cy as number, px as number, py as number);
    return s?.scaleY ?? 1;
  });
  const transformOrigin = useTransform([cellX, cellY, previewX, previewY], ([cx, cy, px, py]) => {
    const s = computeSquish(cx as number, cy as number, px as number, py as number);
    return s?.origin ?? '50% 50%';
  });

  return (
    <motion.div
      className="dev-wall-slot"
      style={{ x: cellX, y: cellY, scaleX, scaleY, transformOrigin, width: tileW, height: tileH }}
    >
      <DevTile
        wallpaper={wp}
        device={device}
        index={index}
        isFeatured={isFeatured}
        onHover={onHover}
      />
    </motion.div>
  );
}

function DevTile({
  wallpaper: w, device, index, isFeatured, onHover,
}: {
  wallpaper: Wallpaper;
  device: DeviceProfile;
  index: number;
  isFeatured: boolean;
  onHover: (idx: number) => void;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const aspect = `${device.width} / ${device.height}`;
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
