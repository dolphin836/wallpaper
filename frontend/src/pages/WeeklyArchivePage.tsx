import { useEffect, useState, useRef } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineArrowRight } from 'react-icons/ai';
import { getWeeklyArchive, getWeeklyByWeek, type WeeklyArchiveEntry, type WeeklyPicked } from '../api';
import PageMeta from '../components/PageMeta';

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
  const [selectedIdx, setSelectedIdx] = useState(0); // 0 = most recent

  // Per-week hero cache. The archive endpoint only returns a cover
  // URL (preview-sized at best). To match the home-page hero's
  // resolution we fetch the week's picks lazily on selection, find the
  // is_hero pick, and use its original_url to upgrade the cover.
  const [heroCache, setHeroCache] = useState<Record<string, WeeklyPicked | null>>({});

  useEffect(() => {
    getWeeklyArchive(100)
      .then((r) => setRows(r.data.data || []))
      .finally(() => setLoading(false));
  }, []);

  const selected = rows[selectedIdx];
  const cacheKey = selected ? `${selected.year}-${selected.week}` : '';
  const heroPick = cacheKey ? heroCache[cacheKey] : null;

  // Lazy-fetch the hero pick for the selected week (cached).
  useEffect(() => {
    if (!selected || cacheKey in heroCache) return;
    let cancelled = false;
    getWeeklyByWeek(selected.year, selected.week)
      .then((r) => {
        if (cancelled) return;
        const picks = r.data.data?.picks || [];
        const hero = picks.find((p) => p.is_hero) || picks[0] || null;
        setHeroCache((prev) => ({ ...prev, [cacheKey]: hero }));
      })
      .catch(() => {
        if (cancelled) return;
        // Mark as null so we don't keep retrying — preview cover stays.
        setHeroCache((prev) => ({ ...prev, [cacheKey]: null }));
      });
    return () => { cancelled = true; };
  }, [selected, cacheKey, heroCache]);

  // Progressive cover image: start with archive cover_url (now backed
  // by preview_url server-side), then swap to the hero's original_url
  // once it's both available in the cache AND decoded by the browser.
  //
  // Race protection: when the user clicks through the timeline fast,
  // week A's pre-decode (new Image().onload) can still fire after the
  // user has already switched to week B. Without a guard, that
  // onload would setCoverSrc(A.original_url) and overwrite the
  // freshly-painted B.cover_url, producing a brief 'wrong image'
  // flash. We bump a version ref on every week change and the
  // onload only commits if it still matches.
  const [coverSrc, setCoverSrc] = useState<string>('');
  const [coverLoaded, setCoverLoaded] = useState(false);
  const versionRef = useRef(0);
  useEffect(() => {
    if (!selected) return;
    versionRef.current += 1;
    setCoverSrc(selected.cover_url || '');
    setCoverLoaded(false);
  }, [selected?.year, selected?.week]);
  useEffect(() => {
    if (!selected || !heroPick?.original_url) return;
    if (heroPick.original_url === selected.cover_url) return;
    if (coverSrc === heroPick.original_url) return;
    const myVersion = versionRef.current;
    const upgrade = new Image();
    upgrade.onload = () => {
      if (versionRef.current !== myVersion) return; // stale — user moved on
      setCoverSrc(heroPick.original_url);
    };
    upgrade.src = heroPick.original_url;
  }, [selected, heroPick?.original_url, coverSrc]);

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
                    {coverSrc && (
                      <img
                        src={coverSrc}
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
