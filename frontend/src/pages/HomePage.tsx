import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { getWeeklyCurrent, getWallpapers, getCollections, type WeeklyCurrent } from '../api';
import type { Wallpaper, Collection } from '../types';
import PageMeta from '../components/PageMeta';

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

  // Independent rows — failure of one section shouldn't blank the page.
  const [aiItems, setAiItems] = useState<Wallpaper[]>([]);
  const [aiLoading, setAiLoading] = useState(true);
  const [videoItems, setVideoItems] = useState<Wallpaper[]>([]);
  const [videoLoading, setVideoLoading] = useState(true);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [collectionsLoading, setCollectionsLoading] = useState(true);

  useEffect(() => {
    getWeeklyCurrent()
      .then((r) => setData(r.data.data))
      .catch(() => { /* keep skeletons hidden — section just won't render */ })
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

  // Drive the page's mesh background from the hero's palette. Effect runs
  // on the root container so the CSS variables stay scoped to .h3-home
  // (no document-wide leak).
  const rootRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    if (!hero || !rootRef.current) return;
    const parts = (hero.color_palette || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length < 3) return;
    rootRef.current.style.setProperty('--h3-c1', parts[parts.length - 2] || parts[0]);
    rootRef.current.style.setProperty('--h3-c2', parts[1] || parts[0]);
    rootRef.current.style.setProperty('--h3-c3', parts[parts.length - 1] || parts[2]);
  }, [hero]);

  const showWeekly = !loading && hero;
  const showRestWeekly = !loading && restPicks.length > 0;
  const showAI = !aiLoading && aiItems.length > 0;
  const showVideo = !videoLoading && videoItems.length > 0;
  const showCollections = !collectionsLoading && collections.length > 0;

  return (
    <div ref={rootRef} className="h3-home">
      <PageMeta
        title="Home"
        description="The weekly drop on Wallpaper Exchange — 10 hand-picked wallpapers plus the latest AI, video and themed collections, refreshed every Friday."
      />
      <div className="h3-home-mesh" aria-hidden />

      <main className="h3-home-main px-6 sm:px-10 lg:px-14 py-10 max-w-[1600px] mx-auto">
        {/* ───── Hero ───── */}
        {loading && (
          <div className="h3-tile h3-video skeleton-card" style={{ aspectRatio: '16 / 9' }} />
        )}
        {showWeekly && hero && <HeroCard hero={hero} week={data!.week} year={data!.year} />}

        {/* ───── This week's picks (rest of slate) ───── */}
        {showRestWeekly && (
          <section className="h3-row">
            <div className="h3-row-head">
              <div>
                <div className="h3-sub">Curation · Week {data!.week}</div>
                <h2><em>This week's</em> picks.</h2>
              </div>
              <Link to={`/weekly-picks/${data!.year}/${data!.week}`} className="h3-more">View all weekly →</Link>
            </div>
            <div className="grid gap-4 grid-cols-2 sm:grid-cols-3 lg:grid-cols-5">
              {restPicks.map((w) => <WallpaperTile key={w.id} w={w} variant="weekly" />)}
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
              {aiItems.slice(0, 5).map((w) => <WallpaperTile key={w.id} w={w} variant="ai" />)}
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
              {videoItems.slice(0, 4).map((w) => <WallpaperTile key={w.id} w={w} variant="video" />)}
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
              {collections.slice(0, 4).map((c) => <CollectionTile key={c.id} c={c} />)}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}

/* ─────────── Hero — 16:9 floating card with progressive image upgrade ─────────── */
function HeroCard({ hero, week, year }: { hero: Wallpaper; week: number; year: number }) {
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
    <Link to={`/wallpaper/${hero.slug || hero.id}`} className="h3-hero block">
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

/* ─────────── Tile (weekly / ai / video) ─────────── */
function WallpaperTile({ w, variant }: { w: Wallpaper; variant: 'weekly' | 'ai' | 'video' }) {
  const [loaded, setLoaded] = useState(false);
  // Video preview-clip autoplay on hover. preview_video_url is the
  // 480p/CRF30/muted clip generated by the transcode worker; falls back
  // to just the poster image when absent (older videos).
  const [playing, setPlaying] = useState(false);
  const vidRef = useRef<HTMLVideoElement | null>(null);
  useEffect(() => {
    if (!playing) return;
    vidRef.current?.play().catch(() => { /* autoplay blocked */ });
  }, [playing]);

  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      className={`h3-tile h3-${variant}${playing ? ' h3-playing' : ''}`}
      onMouseEnter={variant === 'video' && w.preview_video_url ? () => setPlaying(true) : undefined}
      onMouseLeave={variant === 'video' && w.preview_video_url ? () => setPlaying(false) : undefined}
    >
      <img
        src={w.preview_url || w.thumb_url}
        alt={w.title || `Wallpaper ${w.id}`}
        loading="lazy"
        className={loaded ? 'h3-loaded' : ''}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
        style={{ backgroundColor: w.dominant_color || undefined }}
      />
      {variant === 'ai' && <span className="h3-foil" aria-hidden />}
      {variant === 'video' && w.preview_video_url && playing && (
        <video
          ref={vidRef}
          src={w.preview_video_url}
          muted
          loop
          playsInline
          preload="none"
        />
      )}
      {variant === 'video' && (
        <div className="h3-play">
          <svg viewBox="0 0 24 24" aria-hidden><polygon points="6,4 6,20 20,12" /></svg>
        </div>
      )}
      <ResChip wallpaper={w} />
    </Link>
  );
}

/* ─────────── Collection tile (stacked paper) ─────────── */
function CollectionTile({ c }: { c: Collection }) {
  const [loaded, setLoaded] = useState(false);
  return (
    <Link to={`/collections/${c.slug || c.id}`} className="h3-tile-collection block">
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

/* ─────────── Helpers ─────────── */
function ResChip({ wallpaper }: { wallpaper: Wallpaper }) {
  const max = Math.max(wallpaper.width || 0, wallpaper.height || 0);
  let label: string | null = null;
  if (max >= 7680) label = '8K';
  else if (max >= 3840) label = '4K';
  else if (max >= 2560) label = '2K';
  else if (max >= 1920) label = 'HD';
  if (!label) return null;
  return <span className="h3-res-chip">{label}</span>;
}

function fmtMB(b?: number) { return ((b || 0) / 1024 / 1024).toFixed(1) + ' MB'; }
