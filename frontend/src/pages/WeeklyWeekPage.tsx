import { useEffect, useState } from 'react';
import { useParams, useLocation, Link } from 'react-router-dom';
import { AiOutlineArrowLeft } from 'react-icons/ai';
import { getWeeklyByWeek, type WeeklyPicked } from '../api';
import type { Wallpaper } from '../types';
import PageMeta from '../components/PageMeta';
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
  const location = useLocation();
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
      state={{ background: location, initialWallpaper: hero as Wallpaper }}
      className="h3-hero block"
    >
      <img
        src={src}
        alt={hero.title || `Week ${week} hero`}
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
          onClick={(e) => { e.preventDefault(); e.stopPropagation(); /* navigation handles trade flow */ }}
        >
          <span className="h3-coin" /> Trade for 1
        </button>
      </div>
    </Link>
  );
}

export default function WeeklyWeekPage() {
  const { year, week } = useParams<{ year: string; week: string }>();
  const [rows, setRows] = useState<WeeklyPicked[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    const y = Number(year);
    const w = Number(week);
    if (!y || !w) return;
    setLoading(true);
    setNotFound(false);
    getWeeklyByWeek(y, w)
      .then((r) => setRows(r.data.data?.picks || []))
      .catch((e) => {
        if (e?.response?.status === 404) setNotFound(true);
      })
      .finally(() => setLoading(false));
  }, [year, week]);

  const hero = rows.find((r) => r.is_hero) || rows[0];

  const date = year && week ? isoWeekFriday(Number(year), Number(week)) : null;
  const dateStr = date ? fmtDate(date) : '';
  const weekNum = week ? Number(week) : 0;

  return (
    <div className="w-weekly-detail min-h-full">
      <div className="w-weekly-mesh" aria-hidden />
      <PageMeta
        title={`Week ${week} · ${year}`}
        description={`The ${year} week ${week} Weekly Drop on Wallpaper Exchange — 10 hand-picked wallpapers from that week.`}
      />
      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-8">
        <Link to="/weekly-picks" className="w-backlink">
          <AiOutlineArrowLeft size={11} />
          <span>All weekly issues</span>
        </Link>

        {/* Simplified header — just 'Week N' with the date as a small
            mono caption. No ISSUE pill, no № masthead — the hero
            overlay below already carries 'Curation · Week N · YYYY'. */}
        <header className="w-detail-head-simple">
          <h1 className="w-detail-week">Week {weekNum}</h1>
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
        ) : notFound ? (
          <div className="rounded-xl border border-hair bg-paper p-8 text-center text-ink-2 max-w-xl">
            No weekly drop for that week.
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
                  <WallpaperTile key={p.id} w={p} variant="weekly" />
                ))}
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}
