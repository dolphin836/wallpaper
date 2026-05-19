/**
 * Paper-toned skeleton placeholders shaped like the surface they're
 * replacing. All built on the existing `.skeleton-card` keyframe (in
 * index.css) which fades opacity 0.6 ↔ 1 over 1.5s.
 *
 * Use these in `loading && items.length === 0` slots — they read as
 * "content is coming" without the visual jolt of a spinner.
 */

interface Common {
  /** Stagger animation per-item so the list breathes rather than pulsing
   *  in lock-step. Pass the array index. */
  i?: number;
  className?: string;
  style?: React.CSSProperties;
}

function Box({ i = 0, className = '', style }: Common) {
  return (
    <div
      className={`skeleton-card bg-paper-3 ${className}`}
      style={{ animationDelay: `${i * 80}ms`, ...style }}
    />
  );
}

function Line({ width = '60%', i = 0 }: { width?: string | number; i?: number }) {
  return (
    <Box i={i} className="h-3 rounded-sm" style={{ width }} />
  );
}

function Circle({ size = 40, i = 0 }: { size?: number; i?: number }) {
  return (
    <Box i={i} className="rounded-full flex-shrink-0" style={{ width: size, height: size }} />
  );
}

// ─── Wallpaper grids ─────────────────────────────────────────────────

interface GridProps { count?: number; cols?: '2' | '3' | '4' }
const COLS: Record<string, string> = {
  '2': 'grid-cols-2',
  '3': 'grid-cols-2 sm:grid-cols-3',
  '4': 'grid-cols-2 sm:grid-cols-3 lg:grid-cols-4',
};

export function WallpaperGridSkeleton({ count = 8, cols = '4' }: GridProps) {
  return (
    <div className={`grid ${COLS[cols]} gap-3`}>
      {Array.from({ length: count }).map((_, i) => (
        <Box key={i} i={i} className="aspect-[3/2] border border-hair" />
      ))}
    </div>
  );
}

// ─── Collection card grid ────────────────────────────────────────────

export function CollectionGridSkeleton({ count = 8 }: { count?: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="flex flex-col gap-3">
          <Box i={i} className="aspect-[4/3] border border-hair rounded-lg" />
          <Line width="70%" i={i + 1} />
          <Line width="40%" i={i + 2} />
        </div>
      ))}
    </div>
  );
}

// ─── Uploaders list ─────────────────────────────────────────────────

export function UploaderListSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div>
      {Array.from({ length: count }).map((_, i) => (
        <div
          key={i}
          className="grid grid-cols-[68px_1fr] md:grid-cols-[68px_1fr_auto] lg:grid-cols-[68px_1fr_auto_220px] xl:grid-cols-[68px_1fr_auto_280px] gap-4 md:gap-5 lg:gap-6 items-center py-5 border-b border-hair"
        >
          <Circle size={68} i={i} />
          <div className="space-y-2 min-w-0">
            <Box i={i} className="h-5 rounded-sm" style={{ width: '40%' }} />
            <Box i={i + 1} className="h-3 rounded-sm" style={{ width: '60%' }} />
            <Box i={i + 2} className="h-3 rounded-sm" style={{ width: '80%' }} />
          </div>
          <div className="hidden md:block text-right">
            <Box i={i} className="h-3 rounded-sm w-12 ml-auto" />
            <Box i={i + 1} className="h-6 rounded-sm w-16 ml-auto mt-2" />
          </div>
          <div className="hidden lg:grid grid-cols-3 gap-1.5">
            <Box i={i} className="aspect-square border border-hair rounded" />
            <Box i={i + 1} className="aspect-square border border-hair rounded" />
            <Box i={i + 2} className="aspect-square border border-hair rounded" />
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── Profile shell ──────────────────────────────────────────────────

export function ProfileSkeleton() {
  return (
    <div className="px-6 sm:px-10 pt-7 pb-10">
      {/* Header */}
      <div className="grid grid-cols-1 lg:grid-cols-[120px_1fr_auto] gap-6 pb-6 border-b border-hair">
        <Circle size={120} />
        <div className="space-y-3">
          <Box className="h-3 rounded-sm" style={{ width: 260 }} />
          <Box className="h-10 rounded-sm" style={{ width: '40%' }} />
          <Box className="h-3 rounded-sm" style={{ width: 220 }} />
          <Box className="h-4 rounded-sm" style={{ width: '60%' }} />
        </div>
        <div className="hidden lg:block">
          <Box className="rounded-sm" style={{ width: 220, height: 110 }} />
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-7 mt-6 border-b border-hair pb-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <Box key={i} i={i} className="h-4 rounded-sm" style={{ width: 90 }} />
        ))}
      </div>

      {/* Grid */}
      <div className="mt-6">
        <Box className="h-3 rounded-sm mb-4" style={{ width: 200 }} />
        <WallpaperGridSkeleton count={8} cols="4" />
      </div>
    </div>
  );
}

// ─── Collection detail ──────────────────────────────────────────────

export function CollectionDetailSkeleton() {
  return (
    <div>
      <div className="px-6 sm:px-10 pt-5">
        <Box className="rounded-full" style={{ width: 140, height: 32 }} />
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 mt-5 border-b border-hair">
        <Box className="aspect-[3/2] border border-hair" />
        <div className="px-6 sm:px-10 lg:px-12 py-8 lg:py-10 space-y-4">
          <Box className="h-3 rounded-sm" style={{ width: 240 }} />
          <Box className="h-12 rounded-sm" style={{ width: '70%' }} />
          <Box className="h-4 rounded-sm" style={{ width: '50%' }} />
          <Box className="h-4 rounded-sm" style={{ width: '80%' }} />
        </div>
      </div>
      <div className="bg-paper-2 px-6 sm:px-10 py-7">
        <Box className="h-3 rounded-sm mb-4" style={{ width: 200 }} />
        <WallpaperGridSkeleton count={8} cols="4" />
      </div>
    </div>
  );
}
