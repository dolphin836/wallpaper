import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { AiOutlineArrowLeft } from 'react-icons/ai';
import { getWeeklyByWeek, type WeeklyPicked } from '../api';
import PageMeta from '../components/PageMeta';
import WallpaperCard from '../components/WallpaperCard';

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
  const rest = rows.filter((r) => r.id !== hero?.id);

  const date = year && week ? isoWeekFriday(Number(year), Number(week)) : null;
  const dateStr = date ? fmtDate(date) : '';

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

        <header className="w-detail-head">
          <div className="w-detail-kicker">ISSUE</div>
          <div className="w-detail-issue">№ {String(week).padStart(2, '0')}</div>
          <div className="w-detail-meta">
            {dateStr ? `${dateStr} · ` : ''}10 picks
          </div>
        </header>

        {loading ? (
          <>
            <div className="w-detail-hero skeleton-card" style={{ aspectRatio: '21/9' }} />
            <div className="w-detail-grid">
              {Array.from({ length: 9 }).map((_, i) => (
                <div key={i} className="tile-cell skeleton-card aspect-[3/2]" />
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
              <Link
                to={`/wallpaper/${hero.slug || hero.id}`}
                className="w-detail-hero-link"
              >
                <figure className="w-detail-hero">
                  <img
                    src={hero.preview_url || hero.original_url || hero.thumb_url}
                    alt={hero.title || `Week ${week} hero`}
                    loading="eager"
                  />
                  <figcaption className="w-detail-hero-stamp">
                    <span className="w-detail-pickno">№ 01 / 10</span>
                    <span className="w-detail-pickkind">The hero</span>
                  </figcaption>
                </figure>
              </Link>
            )}

            {rest.length > 0 && (
              <div className="w-detail-grid">
                {rest.slice(0, 9).map((p, i) => (
                  <div key={p.id} className="w-detail-cell">
                    <div className="relative aspect-[3/2]">
                      <WallpaperCard
                        wallpaper={p}
                        layout="salon"
                        fillHeight
                        animDelay={i * 40}
                      />
                    </div>
                    <span className="w-detail-cell-no">№ {String(i + 2).padStart(2, '0')}</span>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}
