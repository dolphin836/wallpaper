import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getWeeklyArchive, type WeeklyArchiveEntry } from '../api';
import PageMeta from '../components/PageMeta';

export default function WeeklyArchivePage() {
  const [rows, setRows] = useState<WeeklyArchiveEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    getWeeklyArchive(100)
      .then((r) => setRows(r.data.data || []))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="bg-paper-2 min-h-full">
      <PageMeta
        title="Past Weekly Drops"
        description="Every past Weekly Drop on Wallpaper Exchange — 10 hand-picked wallpapers per ISO week, archived for browsing."
      />
      <main className="px-6 sm:px-10 lg:px-16 py-10 max-w-[1400px] mx-auto">
        <div className="mb-8">
          <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">Archive</div>
          <h1 className="display text-[34px] sm:text-[40px] leading-tight mt-1">Past Weekly Drops</h1>
          <p className="text-ink-2 mt-2 max-w-2xl">
            Every Friday we publish a fresh slate of 10 wallpapers. Once a wallpaper makes the
            list, it never appears in another drop. Browse what's come before.
          </p>
        </div>

        {loading ? (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
            {Array.from({ length: 10 }).map((_, i) => (
              <div key={i} className="aspect-[4/3] border border-hair rounded bg-paper-3 skeleton-card" />
            ))}
          </div>
        ) : rows.length === 0 ? (
          <div className="rounded-lg border border-hair bg-paper p-8 text-center text-ink-2">
            No weekly drops have been published yet.
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-4">
            {rows.map((r) => (
              <Link
                key={`${r.year}-${r.week}`}
                to={`/weekly-picks/${r.year}/${r.week}`}
                className="group block aspect-[4/3] relative overflow-hidden border border-hair rounded bg-paper-3 no-underline"
              >
                {r.cover_url && (
                  <img
                    src={r.cover_url}
                    alt=""
                    loading="lazy"
                    className="absolute inset-0 w-full h-full object-cover transition-transform duration-700 group-hover:scale-105"
                  />
                )}
                <div className="absolute inset-0 bg-gradient-to-t from-black/70 via-black/0 to-black/0" />
                <div className="absolute bottom-2 left-3 right-3 text-paper">
                  <div className="mono text-[10px] tracking-[0.14em] uppercase opacity-90">
                    {r.year} · Week {String(r.week).padStart(2, '0')}
                  </div>
                  <div className="display text-[16px] leading-tight mt-0.5">
                    {r.count} picks
                  </div>
                </div>
              </Link>
            ))}
          </div>
        )}
      </main>
    </div>
  );
}
