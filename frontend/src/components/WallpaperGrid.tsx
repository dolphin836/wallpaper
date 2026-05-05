import { useMemo } from 'react';
import type { Wallpaper } from '../types';
import WallpaperCard from './WallpaperCard';
import EmptyState from './EmptyState';

export type ViewMode = 'waterfall' | 'grid' | 'justified';

interface Props {
  wallpapers: Wallpaper[];
  showStatus?: boolean;
  viewMode?: ViewMode;
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

function WaterfallLayout({ wallpapers, showStatus }: { wallpapers: Wallpaper[]; showStatus?: boolean }) {
  return (
    <div className="columns-1 sm:columns-2 md:columns-3 lg:columns-4 gap-5 space-y-5">
      {wallpapers.map((w, i) => (
        <div key={w.id} className="break-inside-avoid">
          <WallpaperCard wallpaper={w} showStatus={showStatus} animDelay={i * STAGGER_MS} />
        </div>
      ))}
    </div>
  );
}

function GridLayout({ wallpapers, showStatus }: { wallpapers: Wallpaper[]; showStatus?: boolean }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4">
      {wallpapers.map((w, i) => (
        <WallpaperCard key={w.id} wallpaper={w} showStatus={showStatus} fixedAspect animDelay={i * STAGGER_MS} />
      ))}
    </div>
  );
}

function JustifiedLayout({ wallpapers, showStatus }: { wallpapers: Wallpaper[]; showStatus?: boolean }) {
  const rows = useMemo(() => {
    const width = typeof window !== 'undefined' ? Math.min(window.innerWidth - 32, 1280) : 1280;
    return buildJustifiedRows(wallpapers, width, 240);
  }, [wallpapers]);

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

export default function WallpaperGrid({ wallpapers, showStatus, viewMode = 'waterfall' }: Props) {
  if (wallpapers.length === 0) {
    return <EmptyState message="No wallpapers found." />;
  }

  switch (viewMode) {
    case 'grid':
      return <GridLayout wallpapers={wallpapers} showStatus={showStatus} />;
    case 'justified':
      return <JustifiedLayout wallpapers={wallpapers} showStatus={showStatus} />;
    default:
      return <WaterfallLayout wallpapers={wallpapers} showStatus={showStatus} />;
  }
}
