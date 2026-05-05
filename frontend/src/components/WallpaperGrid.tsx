import { useMemo } from 'react';
import type { Wallpaper } from '../types';
import WallpaperCard from './WallpaperCard';
import EmptyState from './EmptyState';

export type ViewMode = 'justified' | 'grid';
export type SizeMode = 'lg' | 'md' | 'sm';

export const SIZE_HEIGHTS: Record<SizeMode, number> = {
  lg: 520,
  md: 260,
  sm: 100,
};

interface Props {
  wallpapers: Wallpaper[];
  showStatus?: boolean;
  viewMode?: ViewMode;
  sizeMode?: SizeMode;
}

interface JustifiedRow {
  items: Wallpaper[];
  height: number;
  partial?: boolean;
}

const STAGGER_MS = 40;

function buildJustifiedRows(wallpapers: Wallpaper[], containerWidth: number, targetHeight: number): JustifiedRow[] {
  const rows: JustifiedRow[] = [];
  let currentRow: Wallpaper[] = [];
  let currentWidth = 0;
  const gap = 6;

  for (const w of wallpapers) {
    const ratio = w.width > 0 && w.height > 0 ? w.width / w.height : 4 / 3;
    const itemWidth = targetHeight * ratio;
    currentRow.push(w);
    currentWidth += itemWidth + (currentRow.length > 1 ? gap : 0);

    if (currentWidth >= containerWidth) {
      const totalGap = (currentRow.length - 1) * gap;
      const scale = (containerWidth - totalGap) / (currentWidth - totalGap);
      rows.push({ items: currentRow, height: targetHeight * scale });
      currentRow = [];
      currentWidth = 0;
    }
  }

  if (currentRow.length > 0) {
    const fillRatio = currentWidth / containerWidth;
    if (fillRatio >= 0.7) {
      rows.push({ items: currentRow, height: targetHeight, partial: true });
    }
  }

  return rows;
}

const GRID_COLS: Record<SizeMode, string> = {
  lg: 'grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4',
  md: 'grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6',
  sm: 'grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10',
};

function GridLayout({ wallpapers, showStatus, sizeMode }: { wallpapers: Wallpaper[]; showStatus?: boolean; sizeMode: SizeMode }) {
  return (
    <div className={`grid ${GRID_COLS[sizeMode]} gap-1.5`}>
      {wallpapers.map((w, i) => (
        <WallpaperCard
          key={w.id}
          wallpaper={w}
          showStatus={showStatus}
          fixedAspect
          animDelay={i * STAGGER_MS}
        />
      ))}
    </div>
  );
}

function JustifiedLayout({ wallpapers, showStatus, targetHeight }: { wallpapers: Wallpaper[]; showStatus?: boolean; targetHeight: number }) {
  const rows = useMemo(() => {
    const width = typeof window !== 'undefined' ? Math.min(window.innerWidth - 32, 1280) : 1280;
    return buildJustifiedRows(wallpapers, width, targetHeight);
  }, [wallpapers, targetHeight]);

  let idx = 0;
  return (
    <div className="flex flex-col gap-1.5">
      {rows.map((row, ri) => (
        <div key={ri} className="flex gap-1.5" style={{ height: row.height }}>
          {row.items.map((w) => {
            const ratio = w.width > 0 && w.height > 0 ? w.width / w.height : 4 / 3;
            const delay = idx++ * STAGGER_MS;
            return (
              <WallpaperCard
                key={w.id}
                wallpaper={w}
                showStatus={showStatus}
                style={{ width: row.height * ratio, flexShrink: 0, flexGrow: row.partial ? 0 : 1 }}
                fillHeight
                animDelay={delay}
              />
            );
          })}
        </div>
      ))}
    </div>
  );
}

export default function WallpaperGrid({ wallpapers, showStatus, viewMode = 'justified', sizeMode = 'md' }: Props) {
  if (wallpapers.length === 0) {
    return <EmptyState message="No wallpapers found." />;
  }

  const height = SIZE_HEIGHTS[sizeMode];

  switch (viewMode) {
    case 'grid':
      return <GridLayout wallpapers={wallpapers} showStatus={showStatus} sizeMode={sizeMode} />;
    default:
      return <JustifiedLayout wallpapers={wallpapers} showStatus={showStatus} targetHeight={height} />;
  }
}
