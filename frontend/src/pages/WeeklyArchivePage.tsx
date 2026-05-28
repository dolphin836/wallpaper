import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineArrowRight } from 'react-icons/ai';
import { getWeeklyArchive, type WeeklyArchiveEntry } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';

const MONTH_ABBR = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];

// ISO week → date of the Friday in that week (weeklies drop on Fridays).
// UTC internally to dodge DST + timezone slippage at midnight.
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
  return `${MONTH_ABBR[d.getUTCMonth()]} ${String(d.getUTCDate()).padStart(2,'0')}`;
}

export default function WeeklyArchivePage() {
  const [rows, setRows] = useState<WeeklyArchiveEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [selectedIdx, setSelectedIdx] = useState(0); // 0 = most recent

  useEffect(() => {
    getWeeklyArchive(100)
      .then((r) => { setRows(r.data.data || []); setError(false); })
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, []);

  const selected = rows[selectedIdx];

  // Cover paint state — single src straight from cover_url. The
  // archive endpoint already picks the right wallpaper (admin hero
  // first, fallback to first published). The list page used to
  // re-fetch byWeek and progressively upgrade to original_url; that
  // produced a visible image swap when the data sources disagreed.
  // Now the list page renders cover_url and only cover_url —
  // upgrade to the full original happens on the detail page.
  const [coverLoaded, setCoverLoaded] = useState(false);
  useEffect(() => {
    setCoverLoaded(false);
  }, [selected?.year, selected?.week]);

  return (
    <div className="w-weekly-archive min-h-full">
      <div className="w-weekly-mesh" aria-hidden />
      <PageMeta
        title="Past Weekly Drops"
        description="Every past Weekly Drop on Wallpaper Exchange — 10 hand-picked wallpapers per ISO week, archived for browsing."
      />
      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-10">
        <header className="mb-12">
          <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">The Archive</div>
          <h1 className="display text-[clamp(34px,4vw,52px)] leading-[1.05] mt-2 text-ink">
            <em>Every</em> Friday, a new ten.
          </h1>
          <p className="text-ink-2 mt-3 max-w-2xl text-[14px] leading-relaxed">
            We publish ten wallpapers each ISO week. Once a piece lands in a drop, it never
            returns. Pick an issue from the timeline.
          </p>
        </header>

        {loading ? (
          <div className="w-archive-grid">
            <div className="w-timeline-skeleton">
              {Array.from({ length: 6 }).map((_, i) => (
                <div key={i} className="w-timeline-row skeleton-card" style={{ height: 36 }} />
              ))}
            </div>
            <div className="w-archive-cover skeleton-card" style={{ aspectRatio: '16/10' }} />
          </div>
        ) : error ? (
          <ErrorState />
        ) : rows.length === 0 ? (
          <div className="rounded-xl border border-hair bg-paper p-8 text-center text-ink-2 max-w-xl">
            No weekly drops have been published yet.
          </div>
        ) : (
          <div className="w-archive-grid">
            <ol className="w-timeline">
              {rows.map((r, i) => {
                const d = isoWeekFriday(r.year, r.week);
                const isSelected = i === selectedIdx;
                return (
                  <li key={`${r.year}-${r.week}`}>
                    <button
                      type="button"
                      onClick={() => setSelectedIdx(i)}
                      className={`w-timeline-row${isSelected ? ' is-selected' : ''}`}
                      aria-pressed={isSelected}
                    >
                      <span className="w-timeline-dot" aria-hidden />
                      <span className="w-timeline-issue">№ {String(r.week).padStart(2, '0')}</span>
                      <span className="w-timeline-date">{fmtDate(d)} · {r.year}</span>
                    </button>
                  </li>
                );
              })}
            </ol>

            <div className="w-archive-panel">
              {selected && (
                <Link
                  to={`/weekly-picks/${selected.year}/${selected.week}`}
                  className="w-archive-cover-link"
                >
                  <figure className="w-archive-cover">
                    {selected.cover_url && (
                      <img
                        key={`${selected.year}-${selected.week}`}
                        src={selected.cover_url}
                        alt=""
                        className={coverLoaded ? 'is-loaded' : ''}
                        onLoad={() => setCoverLoaded(true)}
                        onError={() => setCoverLoaded(true)}
                      />
                    )}
                    <div className="w-archive-cover-shade" aria-hidden />
                    <figcaption className="w-archive-cover-stamp">
                      <span className="w-stamp-kicker">ISSUE</span>
                      <span className="w-stamp-issue">№ {String(selected.week).padStart(2, '0')}</span>
                      <span className="w-stamp-meta">
                        {fmtDate(isoWeekFriday(selected.year, selected.week))} {selected.year} · {selected.count} PICKS
                      </span>
                    </figcaption>
                  </figure>
                  <div className="w-archive-cta">
                    <span>View all {selected.count} picks</span>
                    <AiOutlineArrowRight size={14} />
                  </div>
                </Link>
              )}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
