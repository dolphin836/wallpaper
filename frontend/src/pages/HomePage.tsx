import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getWeeklyCurrent, getWallpapers, getCollections, type WeeklyCurrent } from '../api';
import type { Wallpaper, Collection } from '../types';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import WallpaperTile, { ResChip } from '../components/WallpaperTile';

/**
 * Home v3 — Liquid Surface skin. The page mounts an animated mesh
 * background whose three blob colors come from the active hero
 * wallpaper's palette; four content rows below each carry a distinct
 * tile aesthetic (weekly portrait, AI foil, video widescreen with
 * hover-autoplay, collection stacked-paper). Mirrors /v3-home.html
 * but inside the SPA / production Layout shell.
 */
export default function HomePage() {
  const [data, setData] = useState<WeeklyCurrent | null>(null);
  const [loading, setLoading] = useState(true);
  // Top-level error: the weekly fetch is the page's spine; if it
  // failed (likely a 502 / server outage), every secondary row also
  // probably failed. Show the shared ErrorState instead of a blank
  // skeleton sea.
  const [weeklyError, setWeeklyError] = useState(false);

  // Independent rows — failure of one section shouldn't blank the page.
  const [aiItems, setAiItems] = useState<Wallpaper[]>([]);
  const [aiLoading, setAiLoading] = useState(true);
  const [videoItems, setVideoItems] = useState<Wallpaper[]>([]);
  const [videoLoading, setVideoLoading] = useState(true);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [collectionsLoading, setCollectionsLoading] = useState(true);

  useEffect(() => {
    getWeeklyCurrent()
      .then((r) => { setData(r.data.data); setWeeklyError(false); })
      .catch(() => setWeeklyError(true))
      .finally(() => setLoading(false));
  }, []);
  useEffect(() => {
    getWallpapers({ ai_only: true, limit: 10, sort: 'newest' })
      .then((r) => setAiItems(r.data.data.items))
      .catch(() => setAiItems([]))
      .finally(() => setAiLoading(false));
  }, []);
  useEffect(() => {
    getWallpapers({ video_only: true, limit: 10, sort: 'newest' })
      .then((r) => setVideoItems(r.data.data.items))
      .catch(() => setVideoItems([]))
      .finally(() => setVideoLoading(false));
  }, []);
  useEffect(() => {
    getCollections({ limit: 8 })
      .then((r) => setCollections(r.data.data.items || []))
      .catch(() => setCollections([]))
      .finally(() => setCollectionsLoading(false));
  }, []);

  // Hero = pick flagged is_hero (admin-controlled). Fall back to first
  // pick by sort_order so legacy slates predating the column still work.
  const hero = data?.picks?.find((p) => p.is_hero) || data?.picks?.[0] || null;
  // Rest of the slate excludes the hero by id (admin may have promoted a
  // non-first pick — slicing by index would dupe the hero into the grid).
  const restPicks = (data?.picks || []).filter((p) => p.id !== hero?.id).slice(0, 5);

  // Drive the page's mesh background from a wallpaper's palette. Effect
  // runs on the root container so CSS variables stay scoped to .h3-home.
  // Picks indices 0 / mid / last from the palette — palettes are typically
  // ordered dark→light, so these three give the most visible contrast in
  // the mesh. (The previous "last-2 / 1 / last" pick clustered to similar
  // tones, making the background read as a flat tint.)
  const rootRef = useRef<HTMLDivElement | null>(null);
  const applyPalette = useCallback((palette: string | undefined | null, dominant?: string) => {
    if (!rootRef.current) return;
    if (!palette && !dominant) {
      rootRef.current.style.removeProperty('--h3-c1');
      rootRef.current.style.removeProperty('--h3-c2');
      rootRef.current.style.removeProperty('--h3-c3');
      return;
    }
    const parts = (palette || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length >= 3) {
      rootRef.current.style.setProperty('--h3-c1', parts[0]);
      rootRef.current.style.setProperty('--h3-c2', parts[Math.floor(parts.length / 2)]);
      rootRef.current.style.setProperty('--h3-c3', parts[parts.length - 1]);
      return;
    }
    // Fallback when palette is short/empty (e.g. video wallpapers — the
    // transcode worker doesn't extract a palette, just a dominant color).
    // Use the dominant_color for all three blobs so the mesh still tints
    // toward the hovered wallpaper instead of staying static.
    if (dominant) {
      rootRef.current.style.setProperty('--h3-c1', dominant);
      rootRef.current.style.setProperty('--h3-c2', dominant);
      rootRef.current.style.setProperty('--h3-c3', dominant);
    }
  }, []);
  // Hero palette = default. When user hovers a wallpaper tile, the mesh
  // briefly switches to that wallpaper's palette; on leave we restore
  // the hero's palette via this ref.
  const heroPaletteRef = useRef<string | undefined>(undefined);
  const heroDominantRef = useRef<string | undefined>(undefined);
  useEffect(() => {
    heroPaletteRef.current = hero?.color_palette;
    heroDominantRef.current = hero?.dominant_color;
    applyPalette(hero?.color_palette, hero?.dominant_color);
  }, [hero, applyPalette]);
  const handleTileHover = useCallback(
    (palette: string | undefined, dominant?: string) => {
      if (palette || dominant) {
        applyPalette(palette, dominant);
      } else {
        applyPalette(heroPaletteRef.current, heroDominantRef.current);
      }
    },
    [applyPalette],
  );

  // Section visibility: show during initial loading (with skeleton tiles)
  // so the page renders at ~final height from the very first paint — that
  // way you can scroll to the bottom while data is still streaming in and
  // the page doesn't pop content into existence (the previous logic
  // produced a hero-only frame, document height = ~500px, scroll bottom
  // unreachable until everything loaded).
  const showWeeklyRest = loading || restPicks.length > 0;
  const showAI = aiLoading || aiItems.length > 0;
  const showVideo = videoLoading || videoItems.length > 0;
  const showCollections = collectionsLoading || collections.length > 0;

  return (
    <div ref={rootRef} className="h3-home">
      <PageMeta
        title="Home"
        description="The weekly drop on Wallpaper Exchange — 10 hand-picked wallpapers plus the latest AI, video and themed collections, refreshed every Friday."
      />
      <div className="h3-home-mesh" aria-hidden />

      <main className="h3-home-main px-6 sm:px-10 lg:px-14 py-10 max-w-[1600px] mx-auto">
        {/* If the weekly spine failed AND no secondary row arrived,
            the server's down — show the shared error state instead of
            an empty page of skeletons. */}
        {weeklyError && !data && aiItems.length === 0 && videoItems.length === 0 && collections.length === 0 ? (
          <ErrorState />
        ) : (
          <>
        {/* ───── Hero ───── */}
        {loading
          ? <div className="h3-tile skeleton-card" style={{ aspectRatio: '16 / 9', borderRadius: 24 }} />
          : hero
            ? <HeroCard hero={hero} week={data!.week} year={data!.year} />
            : null}

        {/* ───── This week's picks (rest of slate) ───── */}
        {showWeeklyRest && (
          <section className="h3-row">
            <div className="h3-row-head">
              <div>
                <div className="h3-sub">Curation{data ? ` · Week ${data.week}` : ''}</div>
                <h2><em>This week's</em> picks.</h2>
              </div>
              {data && (
                <Link to="/weekly-picks" className="h3-more">View archive →</Link>
              )}
            </div>
            <div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
              {loading && restPicks.length === 0
                ? Array.from({ length: 5 }).map((_, i) => <SkeletonTile key={`wsk-${i}`} variant="weekly" />)
                : restPicks.map((w) => <WallpaperTile key={w.id} w={w} variant="weekly" onHover={handleTileHover} />)}
            </div>
          </section>
        )}

        {/* ───── AI Lab ───── */}
        {showAI && (
          <section className="h3-row">
            <div className="h3-row-head">
              <div>
                <div className="h3-sub">AI Lab · synthetic samples</div>
                <h2><em>Generated</em> this week.</h2>
              </div>
              <Link to="/discover?filter=ai" className="h3-more">All AI wallpapers →</Link>
            </div>
            <div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
              {aiLoading && aiItems.length === 0
                ? Array.from({ length: 5 }).map((_, i) => <SkeletonTile key={`ask-${i}`} variant="ai" />)
                : aiItems.slice(0, 5).map((w) => <WallpaperTile key={w.id} w={w} variant="ai" onHover={handleTileHover} />)}
            </div>
          </section>
        )}

        {/* ───── Video wallpapers ───── */}
        {showVideo && (
          <section className="h3-row">
            <div className="h3-row-head">
              <div>
                <div className="h3-sub">Motion · hover to preview</div>
                <h2><em>Video</em> wallpapers.</h2>
              </div>
              <Link to="/discover?filter=video" className="h3-more">All videos →</Link>
            </div>
            <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-4">
              {videoLoading && videoItems.length === 0
                ? Array.from({ length: 4 }).map((_, i) => <SkeletonTile key={`vsk-${i}`} variant="video" />)
                : videoItems.slice(0, 4).map((w) => <WallpaperTile key={w.id} w={w} variant="video" onHover={handleTileHover} />)}
            </div>
          </section>
        )}

        {/* ───── Themed collections ───── */}
        {showCollections && (
          <section className="h3-row">
            <div className="h3-row-head">
              <div>
                <div className="h3-sub">Editorial sets · themed bundles</div>
                <h2><em>Themed</em> collections.</h2>
              </div>
              <Link to="/collections" className="h3-more">All collections →</Link>
            </div>
            <div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4">
              {collectionsLoading && collections.length === 0
                ? Array.from({ length: 4 }).map((_, i) => <SkeletonTile key={`csk-${i}`} variant="collection" />)
                : collections.slice(0, 4).map((c) => <CollectionTile key={c.id} c={c} onHover={handleTileHover} />)}
            </div>
          </section>
        )}
          </>
        )}
      </main>
    </div>
  );
}

/* ─────────── Hero — 16:9 floating card with progressive image upgrade ─────────── */
function HeroCard({ hero, week, year }: { hero: Wallpaper; week: number; year: number }) {
  const location = useLocation();
  // Paint preview_url first (fast first frame), then background-fetch the
  // original_url (only the hero pick gets it from the server). Swap src
  // once it's decoded. If original never finishes, preview stays — best
  // possible quality given the link, without blocking first paint.
  const [src, setSrc] = useState(hero.preview_url || hero.thumb_url);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    setSrc(hero.preview_url || hero.thumb_url);
    setLoaded(false);
    if (!hero.original_url || hero.original_url === hero.preview_url) return;
    const upgrade = new Image();
    upgrade.onload = () => setSrc(hero.original_url);
    upgrade.src = hero.original_url;
  }, [hero.id, hero.preview_url, hero.thumb_url, hero.original_url]);

  return (
    <Link
      to={`/wallpaper/${hero.slug || hero.id}`}
      state={{ background: location, initialWallpaper: hero }}
      className="h3-hero block"
    >
      <img
        src={src}
        alt={hero.title || `Wallpaper ${hero.id}`}
        className={loaded ? 'h3-loaded' : ''}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
      />
      <ResChip wallpaper={hero} />
      <div className="h3-hero-overlay">
        <div className="flex-1 min-w-0">
          <div className="h3-kicker">Curation · Week {week} · {year}</div>
          <div className="h3-meta">{hero.width}×{hero.height} · {fmtMB(hero.file_size)}</div>
        </div>
        <button
          className="h3-cta"
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); /* navigate to detail handles trade */ }}
        >
          <span className="h3-coin" /> Trade for 1
        </button>
      </div>
    </Link>
  );
}

/* WallpaperTile + ResChip moved to components/WallpaperTile.tsx so
   WeeklyWeekPage can render the same editorial weekly tile (with the
   hover-revealed favorite/like/download rail + modal navigation) as
   the home page. */

/* ─────────── Collection tile (stacked paper) ─────────── */
function CollectionTile({
  c, onHover,
}: {
  c: Collection;
  onHover?: (palette: string | undefined, dominant?: string) => void;
}) {
  const [loaded, setLoaded] = useState(false);
  // Collections expose an accent_color (curator-chosen). Use it as the
  // mesh tint on hover — palettes aren't extracted for collections.
  return (
    <Link
      to={`/collections/${c.slug || c.id}`}
      className="h3-tile-collection block"
      onMouseEnter={() => onHover?.(undefined, c.accent_color)}
      onMouseLeave={() => onHover?.(undefined)}
    >
      <div className="h3-frame">
        <img
          src={c.cover_url || ''}
          alt={c.title}
          loading="lazy"
          className={loaded ? 'h3-loaded' : ''}
          onLoad={() => setLoaded(true)}
          onError={() => setLoaded(true)}
        />
        <div className="h3-gradient" />
      </div>
      <div className="h3-copy">
        <div className="h3-title">{c.title || 'Untitled set'}</div>
        <div className="h3-count">{c.wallpaper_count ?? 0} wallpapers</div>
      </div>
    </Link>
  );
}

/* ─────────── Skeleton placeholder per row variant ─────────── */
function SkeletonTile({ variant }: { variant: 'weekly' | 'ai' | 'video' | 'collection' }) {
  const ratio =
    variant === 'weekly' ? '4 / 5'
    : variant === 'video' ? '16 / 9'
    : '1 / 1';
  // Use the h3-tile chrome (rounded corners + shadow) so the skeleton
  // visually matches what's about to land in its place.
  return (
    <div
      className={variant === 'collection' ? 'h3-tile-collection skeleton-card' : `h3-tile h3-${variant} skeleton-card`}
      style={{ aspectRatio: ratio }}
    />
  );
}

/* ─────────── Helpers ─────────── */
// ResChip lives in components/WallpaperTile.tsx (shared with weekly).
function fmtMB(b?: number) { return ((b || 0) / 1024 / 1024).toFixed(1) + ' MB'; }
