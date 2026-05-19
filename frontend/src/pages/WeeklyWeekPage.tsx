import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { getWeeklyByWeek, type WeeklyPicked } from '../api';
import PageMeta from '../components/PageMeta';
import WallpaperCard from '../components/WallpaperCard';

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
    getWeeklyByWeek(y, w)
      .then((r) => setRows(r.data.data?.picks || []))
      .catch((e) => {
        if (e?.response?.status === 404) setNotFound(true);
      })
      .finally(() => setLoading(false));
  }, [year, week]);

  return (
    <div className="bg-paper-2 min-h-full">
      <PageMeta
        title={`Week ${week} · ${year}`}
        description={`The ${year} week ${week} Weekly Drop on Wallpaper Exchange — 10 hand-picked wallpapers from that week.`}
      />
      <main className="px-6 sm:px-10 lg:px-16 py-10 max-w-[1600px] mx-auto">
        <div className="mb-8">
          <Link to="/weekly-picks" className="mono text-[10px] tracking-[0.14em] uppercase text-muted hover:text-ink-2 no-underline">
            ← All weekly drops
          </Link>
          <h1 className="display text-[34px] sm:text-[40px] leading-tight mt-1">
            Week {week} · {year}
          </h1>
        </div>

        {loading ? (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            {Array.from({ length: 10 }).map((_, i) => (
              <div key={i} className="aspect-[4/3] border border-hair rounded bg-paper-3 skeleton-card" />
            ))}
          </div>
        ) : notFound ? (
          <div className="rounded-lg border border-hair bg-paper p-8 text-center text-ink-2">
            No weekly drop for that week.
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
            {rows.map((w, i) => (
              <div key={w.id} className="aspect-[4/3] relative">
                <WallpaperCard wallpaper={w} fixedAspect hideActions animDelay={i * 30} />
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
