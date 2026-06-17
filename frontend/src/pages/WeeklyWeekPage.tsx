import { useCallback, useEffect, useRef, useState } from 'react';
import { useParams, useLocation, Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { AiOutlineArrowLeft } from 'react-icons/ai';
import { getWeeklyByWeek, type WeeklyPicked } from '../api';
import type { Wallpaper } from '../types';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import WallpaperTile, { ResChip } from '../components/WallpaperTile';

const MONTH_ABBR = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

function isoWeekFriday(year: number, week: number): Date {
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4Dow = jan4.getUTCDay() || 7;
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - jan4Dow + 1);
  const friday = new Date(week1Monday);
  friday.setUTCDate(week1Monday.getUTCDate() + (week - 1) * 7 + 4);
  return friday;
}
function fmtDate(d: Date) {
  return `${MONTH_ABBR[d.getUTCMonth()]} ${String(d.getUTCDate()).padStart(2,'0')}, ${d.getUTCFullYear()}`;
}
function fmtMB(b?: number) { return ((b || 0) / 1024 / 1024).toFixed(1) + ' MB'; }

// Hero card — mirrors HomePage's HeroCard exactly so the home weekly
// hero and the detail-page hero feel like the same artifact. Progressive
// load: preview_url first (fast first paint), then background-fetch
// original_url and swap once decoded; preview stays if original never
// arrives. Click opens the wallpaper detail as a modal overlay (same
// pattern as the tiles below) instead of a hard navigate.
function WeeklyHero({ hero, week, year }: { hero: WeeklyPicked; week: number; year: number }) {
  const { t } = useTranslation('browse');
  const location = useLocation();
  const [src, setSrc] = useState(hero.thumb_url || hero.preview_url || hero.original_url);
  const [loaded, setLoaded] = useState(false);
  const [upgrading, setUpgrading] = useState(false);
  useEffect(() => {
    let alive = true;
    const baseSrc = hero.thumb_url || hero.preview_url || hero.original_url;
    const previewSrc = hero.preview_url && hero.preview_url !== baseSrc ? hero.preview_url : '';
    const originalSrc = hero.original_url && hero.original_url !== (previewSrc || baseSrc) ? hero.original_url : '';

    setSrc(baseSrc);
    setLoaded(false);

    const queue = [previewSrc, originalSrc].filter(Boolean);
    setUpgrading(queue.length > 0);

    const loadNext = (index: number) => {
      const next = queue[index];
      if (!next) {
        if (alive) setUpgrading(false);
        return;
      }
      const image = new Image();
      image.onload = () => {
        if (!alive) return;
        setLoaded(false);
        setSrc(next);
        loadNext(index + 1);
      };
      image.onerror = () => loadNext(index + 1);
      image.src = next;
    };
    loadNext(0);

    return () => {
      alive = false;
    };
  }, [hero.id, hero.preview_url, hero.thumb_url, hero.original_url]);

  return (
    <Link
      to={`/wallpaper/${hero.slug || hero.id}`}
      state={{ background: location, initialWallpaper: hero as Wallpaper }}
      className="h3-hero block"
    >
      <img
        src={src}
        alt={hero.title || t('hero.weekHeroAlt', { week })}
        className={loaded ? 'h3-loaded' : ''}
        onLoad={() => setLoaded(true)}
        onError={() => setLoaded(true)}
        style={{ backgroundColor: hero.dominant_color || undefined }}
      />
      {(!loaded || upgrading) && <span className="card-loading-beam" aria-hidden />}
      <ResChip wallpaper={hero} />
      <div className="h3-hero-overlay">
        <div className="flex-1 min-w-0">
          <div className="h3-kicker">{t('hero.kicker', { week, year })}</div>
          <div className="h3-meta">{hero.width}×{hero.height} · {fmtMB(hero.file_size)}</div>
        </div>
        <button
          className="h3-cta"
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); /* navigation handles trade flow */ }}
        >
          <span className="h3-coin" /> {t('hero.tradeForOne')}
        </button>
      </div>
    </Link>
  );
}

export default function WeeklyWeekPage() {
  const { t } = useTranslation('browse');
  const { year, week } = useParams<{ year: string; week: string }>();
  const [rows, setRows] = useState<WeeklyPicked[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [error, setError] = useState(false);

  // Mesh palette is driven by the hero by default, swapped on tile
  // hover to that tile's palette/dominant — same pattern as the
  // home page. Setting --w-c1/c2/c3 on the page root keeps the
  // effect bounded to this page (no leak into other surfaces).
  const rootRef = useRef<HTMLDivElement | null>(null);
  const heroPaletteRef = useRef<string | undefined>(undefined);
  const heroDominantRef = useRef<string | undefined>(undefined);

  const applyPalette = useCallback((palette: string | undefined | null, dominant?: string) => {
    const root = rootRef.current;
    if (!root) return;
    if (!palette && !dominant) {
      root.style.removeProperty('--w-c1');
      root.style.removeProperty('--w-c2');
      root.style.removeProperty('--w-c3');
      return;
    }
    const parts = (palette || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length >= 3) {
      root.style.setProperty('--w-c1', parts[0]);
      root.style.setProperty('--w-c2', parts[Math.floor(parts.length / 2)]);
      root.style.setProperty('--w-c3', parts[parts.length - 1]);
      return;
    }
    // Fallback to dominant_color when the wallpaper has no extracted
    // palette (video / older uploads). One colour gets stretched across
    // all three radials.
    if (dominant) {
      root.style.setProperty('--w-c1', dominant);
      root.style.setProperty('--w-c2', dominant);
      root.style.setProperty('--w-c3', dominant);
    }
  }, []);

  useEffect(() => {
    const y = Number(year);
    const w = Number(week);
    if (!y || !w) return;
    setLoading(true);
    setNotFound(false);
    setError(false);
    getWeeklyByWeek(y, w)
      .then((r) => setRows(r.data.data?.picks || []))
      .catch((e) => {
        if (e?.response?.status === 404) setNotFound(true);
        else setError(true);
      })
      .finally(() => setLoading(false));
  }, [year, week]);

  const hero = rows.find((r) => r.is_hero) || rows[0];

  // Cache the hero's palette so hover-out reverts to it (instead of
  // snapping back to the warm brand default).
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

  const date = year && week ? isoWeekFriday(Number(year), Number(week)) : null;
  const dateStr = date ? fmtDate(date) : '';
  const weekNum = week ? Number(week) : 0;

  return (
    <div ref={rootRef} className="w-weekly-detail min-h-full">
      <div className="w-weekly-mesh" aria-hidden />
      <PageMeta
        title={t('weekly.weekMetaTitle', { week, year })}
        description={t('weekly.weekMetaDescription', { week, year })}
      />
      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-8">
        <Link to="/weekly-picks" className="w-backlink">
          <AiOutlineArrowLeft size={11} />
          <span>{t('weekly.allIssues')}</span>
        </Link>

        {/* Simplified header — just 'Week N' with the date as a small
            mono caption. No ISSUE pill, no № masthead — the hero
            overlay below already carries 'Curation · Week N · YYYY'. */}
        <header className="w-detail-head-simple">
          <h1 className="w-detail-week">{t('weekly.weekHeading', { week: weekNum })}</h1>
          {dateStr && <div className="w-detail-week-meta">{dateStr}</div>}
        </header>

        {loading ? (
          <>
            <div
              className="h3-hero skeleton-card"
              style={{ aspectRatio: '16/9', marginBottom: 48 }}
              aria-hidden
            />
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
              {Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="h3-tile h3-weekly skeleton-card" />
              ))}
            </div>
          </>
        ) : error ? (
          <ErrorState />
        ) : notFound ? (
          <div className="rounded-xl border border-hair bg-paper p-8 text-center text-ink-2 max-w-xl">
            {t('weekly.noDropForWeek')}
          </div>
        ) : (
          <>
            {hero && (
              <div className="mb-12">
                <WeeklyHero hero={hero} week={weekNum} year={Number(year)} />
              </div>
            )}

            {/* All 10 picks rendered as the same 4:5 weekly tile as
                the home page (5 per row on desktop). The hero appears
                again here — intentional: the cover hero up top is the
                'masthead' of the issue, the grid is the actual slate
                you can browse. */}
            {rows.length > 0 && (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
                {rows.map((p) => (
                  <WallpaperTile key={p.id} w={p} variant="weekly" onHover={handleTileHover} />
                ))}
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}
