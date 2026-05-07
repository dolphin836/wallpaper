import { useMemo, useRef, useState, useEffect } from 'react';
import justifiedLayout from 'justified-layout';
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

const BOX_SPACING = 16;
const STAGGER_MS = 40;

interface Props {
  wallpapers: Wallpaper[];
  showStatus?: boolean;
  viewMode?: ViewMode;
  sizeMode?: SizeMode;
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

const GRID_COLS: Record<SizeMode, string> = {
  lg: 'grid-cols-2 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4',
  md: 'grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6',
  sm: 'grid-cols-4 sm:grid-cols-6 md:grid-cols-8 lg:grid-cols-10',
};

function GridLayout({ wallpapers, showStatus, sizeMode }: { wallpapers: Wallpaper[]; showStatus?: boolean; sizeMode: SizeMode }) {
  return (
    <div className={`grid ${GRID_COLS[sizeMode]} gap-4`}>
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

interface LayoutBox {
  width: number;
  height: number;
  left: number;
  top: number;
}

function JustifiedView({ wallpapers, showStatus, targetHeight }: { wallpapers: Wallpaper[]; showStatus?: boolean; targetHeight: number }) {
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
            fillHeight
            animDelay={i * STAGGER_MS}
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

export default function WallpaperGrid({ wallpapers, showStatus, viewMode = 'justified', sizeMode = 'md' }: Props) {
  if (wallpapers.length === 0) {
    return <EmptyState message="No wallpapers found." />;
  }

  const height = SIZE_HEIGHTS[sizeMode];

  switch (viewMode) {
    case 'grid':
      return <GridLayout wallpapers={wallpapers} showStatus={showStatus} sizeMode={sizeMode} />;
    default:
      return <JustifiedView wallpapers={wallpapers} showStatus={showStatus} targetHeight={height} />;
  }
}
