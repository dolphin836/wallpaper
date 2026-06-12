import { useMemo, useRef, useState, useEffect } from 'react';
import { useTranslation } from 'react-i18next';
import justifiedLayout from 'justified-layout';
import type { Wallpaper } from '../types';
import WallpaperCard from './WallpaperCard';
import EmptyState from './EmptyState';

export type ViewMode = 'salon' | 'justified' | 'grid';
export type SizeMode = 'lg' | 'md' | 'sm';

export const SIZE_HEIGHTS: Record<SizeMode, number> = {
  lg: 520,
  md: 260,
  sm: 100,
};

// Salon row height driven by the size toggle. Smaller values = more tiles
// per page, more density; larger = poster-wall feel. Tuned to land in the
// same ballpark as the SIZE_HEIGHTS values used by the justified view so
// the page footprint per scroll is roughly comparable across modes.
export const SALON_ROW_BY_SIZE: Record<SizeMode, number> = {
  sm: 110,
  md: 150,
  lg: 200,
};

// 10-tile repeating mosaic across an 11-column grid. Items use `span`
// rather than absolute lines so the grid auto-flow algorithm packs them
// into the next available block. Pattern lengths add up to 27 column-slots
// across 6 grid rows, repeating cleanly — visually it gives the salon-wall
// asymmetry without leaving big gaps.
const SALON_PATTERN: Array<{ colSpan: number; rowSpan: number }> = [
  { colSpan: 4, rowSpan: 2 }, // wide hero
  { colSpan: 3, rowSpan: 3 }, // tall column
  { colSpan: 4, rowSpan: 2 }, // wide right
  { colSpan: 3, rowSpan: 2 }, // medium tall
  { colSpan: 5, rowSpan: 1 }, // letterbox
  { colSpan: 3, rowSpan: 2 }, // medium
  { colSpan: 4, rowSpan: 1 }, // short wide
  { colSpan: 4, rowSpan: 2 }, // mid hero
  { colSpan: 3, rowSpan: 1 }, // sm
  { colSpan: 4, rowSpan: 1 }, // wide short
];

function salonSpanFor(i: number) {
  return SALON_PATTERN[i % SALON_PATTERN.length];
}

const BOX_SPACING = 16;
const STAGGER_MS = 40;
const MAX_STAGGER_ITEMS = 15;

function staggerDelay(index: number, staggerFrom: number): number {
  if (index < staggerFrom) return 0;
  const rel = index - staggerFrom;
  if (rel >= MAX_STAGGER_ITEMS) return 0;
  return rel * STAGGER_MS;
}

interface Props {
  wallpapers: Wallpaper[];
  showStatus?: boolean;
  viewMode?: ViewMode;
  sizeMode?: SizeMode;
  staggerFrom?: number;
  disableModal?: boolean;
}

function useContainerWidth(ref: React.RefObject<HTMLDivElement | null>) {
  const [width, setWidth] = useState(0);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width ?? 0;
      if (w > 0) setWidth(w);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [ref]);
  return width;
}

// Matches GRID_BREAKPOINT_COLS in DiscoverPage. Tuned so Grid LG reads
// closer to Justified LG (was reading as Justified MD because tiles were
// one tier smaller across the board).
const GRID_COLS: Record<SizeMode, string> = {
  lg: 'grid-cols-1 sm:grid-cols-2 md:grid-cols-2 lg:grid-cols-3',
  md: 'grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5',
  sm: 'grid-cols-3 sm:grid-cols-4 md:grid-cols-6 lg:grid-cols-8',
};

function GridLayout({ wallpapers, showStatus, sizeMode, staggerFrom = 0, disableModal }: { wallpapers: Wallpaper[]; showStatus?: boolean; sizeMode: SizeMode; staggerFrom?: number; disableModal?: boolean }) {
  // Uses the salon (editorial) tile variant so cards share the rounded-
  // chrome + hover-lift look used by the home page's weekly grid. Each
  // cell gets an aspect-ratio host box because the salon card is
  // absolutely-positioned and needs a sized parent.
  return (
    <div className={`grid ${GRID_COLS[sizeMode]} gap-4`}>
      {wallpapers.map((w, i) => (
        <div key={w.id} className="relative aspect-[3/2]">
          <WallpaperCard
            wallpaper={w}
            showStatus={showStatus}
            layout="salon"
            fillHeight
            animDelay={staggerDelay(i, staggerFrom)}
            disableModal={disableModal}
          />
        </div>
      ))}
    </div>
  );
}

interface LayoutBox {
  width: number;
  height: number;
  left: number;
  top: number;
}

function JustifiedView({ wallpapers, showStatus, targetHeight, staggerFrom = 0, disableModal }: { wallpapers: Wallpaper[]; showStatus?: boolean; targetHeight: number; staggerFrom?: number; disableModal?: boolean }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const containerWidth = useContainerWidth(containerRef);

  const { boxes, containerHeight } = useMemo(() => {
    if (containerWidth <= 0) return { boxes: [] as LayoutBox[], containerHeight: 0 };

    const ratios = wallpapers.map((w) =>
      w.width > 0 && w.height > 0 ? w.width / w.height : 4 / 3,
    );

    const result = justifiedLayout(ratios, {
      containerWidth,
      containerPadding: 0,
      boxSpacing: BOX_SPACING,
      targetRowHeight: targetHeight,
      showWidows: true,
      forceAspectRatio: false,
    });

    return {
      boxes: result.boxes as LayoutBox[],
      containerHeight: result.containerHeight as number,
    };
  }, [wallpapers, containerWidth, targetHeight]);

  return (
    <div ref={containerRef} className="relative w-full" style={{ height: containerHeight || undefined }}>
      {boxes.map((box, i) => {
        const w = wallpapers[i];
        if (!w) return null;
        return (
          <WallpaperCard
            key={w.id}
            wallpaper={w}
            showStatus={showStatus}
            layout="salon"
            fillHeight
            animDelay={staggerDelay(i, staggerFrom)}
            disableModal={disableModal}
            style={{
              position: 'absolute',
              left: box.left,
              top: box.top,
              width: box.width,
              height: box.height,
            }}
          />
        );
      })}
    </div>
  );
}

function SalonLayout({ wallpapers, sizeMode, staggerFrom = 0, disableModal }: { wallpapers: Wallpaper[]; sizeMode: SizeMode; staggerFrom?: number; disableModal?: boolean }) {
  const rowH = SALON_ROW_BY_SIZE[sizeMode];
  return (
    <div
      // grid-auto-flow: dense lets the engine fill holes left behind by
      // tall tiles with later items that fit, so the wall never has
      // suspicious column gaps even when the pattern wraps onto a new row.
      style={{
        display: 'grid',
        gridTemplateColumns: 'repeat(11, 1fr)',
        gridAutoRows: `${rowH}px`,
        gridAutoFlow: 'dense',
        gap: 8,
      }}
    >
      {wallpapers.map((w, i) => {
        const span = salonSpanFor(i);
        return (
          <div
            key={w.id}
            style={{
              gridColumn: `span ${span.colSpan}`,
              gridRow: `span ${span.rowSpan}`,
              position: 'relative',
            }}
          >
            <WallpaperCard
              wallpaper={w}
              layout="salon"
              fillHeight
              animDelay={staggerDelay(i, staggerFrom)}
              disableModal={disableModal}
            />
          </div>
        );
      })}
    </div>
  );
}

export default function WallpaperGrid({ wallpapers, showStatus, viewMode = 'justified', sizeMode = 'md', staggerFrom = 0, disableModal }: Props) {
  const { t } = useTranslation('browse');
  if (wallpapers.length === 0) {
    return (
      <EmptyState
        title={t('grid.emptyTitle')}
        message={t('grid.emptyMessage')}
      />
    );
  }

  const height = SIZE_HEIGHTS[sizeMode];

  switch (viewMode) {
    case 'salon':
      return <SalonLayout wallpapers={wallpapers} sizeMode={sizeMode} staggerFrom={staggerFrom} disableModal={disableModal} />;
    case 'grid':
      return <GridLayout wallpapers={wallpapers} showStatus={showStatus} sizeMode={sizeMode} staggerFrom={staggerFrom} disableModal={disableModal} />;
    default:
      return <JustifiedView wallpapers={wallpapers} showStatus={showStatus} targetHeight={height} staggerFrom={staggerFrom} disableModal={disableModal} />;
  }
}
