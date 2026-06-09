import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineArrowRight } from 'react-icons/ai';
import { getWeeklyArchive, type WeeklyArchiveEntry } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';

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

  // Apply the selected issue's palette to the page-mesh CSS vars.
  // Same pattern as WeeklyWeekPage: split color_palette by comma
  // and take three stops; fall back to dominant_color when there's
  // no palette; otherwise leave the defaults. Scoped to this page
  // by setting on rootRef instead of :root.
  const rootRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    if (!selected) {
      root.style.removeProperty('--w-c1');
      root.style.removeProperty('--w-c2');
      root.style.removeProperty('--w-c3');
      return;
    }
    const parts = (selected.color_palette || '')
      .split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length >= 3) {
      root.style.setProperty('--w-c1', parts[0]);
      root.style.setProperty('--w-c2', parts[Math.floor(parts.length / 2)]);
      root.style.setProperty('--w-c3', parts[parts.length - 1]);
    } else if (selected.dominant_color) {
      root.style.setProperty('--w-c1', selected.dominant_color);
      root.style.setProperty('--w-c2', selected.dominant_color);
      root.style.setProperty('--w-c3', selected.dominant_color);
    } else if (selected.accent_color) {
      root.style.setProperty('--w-c1', selected.accent_color);
      root.style.setProperty('--w-c2', selected.accent_color);
      root.style.setProperty('--w-c3', selected.accent_color);
    } else {
      root.style.removeProperty('--w-c1');
      root.style.removeProperty('--w-c2');
      root.style.removeProperty('--w-c3');
    }
  }, [selected?.year, selected?.week, selected?.color_palette, selected?.dominant_color, selected?.accent_color]);

  return (
    <div ref={rootRef} className="w-weekly-archive min-h-full">
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
          <EmptyState
            title="No weekly drops yet."
            message="The archive will appear once the first weekly curation has been published."
          />
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
                        ref={(el) => {
                          // Cached-image edge case: when the key flip
                          // remounts the <img>, the browser can serve
                          // src from the HTTP cache so fast that the
                          // onLoad fires before React attached its
                          // listener — coverLoaded then stays false
                          // forever and the CSS opacity: 0 hides the
                          // image. Reading .complete synchronously
                          // after mount catches that case. Verified
                          // by the user as the 'first cover sometimes
                          // doesn't show on refresh' symptom.
                          if (el && el.complete && el.naturalWidth > 0) {
                            setCoverLoaded(true);
                          }
                        }}
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
