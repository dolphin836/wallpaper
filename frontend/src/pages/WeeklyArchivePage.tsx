import { useEffect, useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import { AiOutlineArrowRight } from 'react-icons/ai';
import { getWeeklyArchive, getWeeklyByWeek, type WeeklyArchiveEntry } from '../api';
import type { WeeklyPicked } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';

const MONTH_ABBR = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
const WEEKLY_STRIP_SIZE = 9;
const WEEKLY_RACK_GAP = 28;

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

function weeklyRackSkeletonCount() {
  if (typeof window === 'undefined') return 36;

  const horizontalPadding = window.innerWidth >= 640 ? 80 : 48;
  const contentWidth = Math.max(1, Math.min(window.innerWidth, 1600) - horizontalPadding);
  const minCardWidth = Math.min(300, contentWidth);
  const columns = Math.max(1, Math.floor((contentWidth + WEEKLY_RACK_GAP) / (minCardWidth + WEEKLY_RACK_GAP)));
  const cardWidth = (contentWidth - WEEKLY_RACK_GAP * (columns - 1)) / columns;
  const rowHeight = cardWidth * 10 / 16;
  const rows = Math.ceil((window.innerHeight * 2 + WEEKLY_RACK_GAP) / (rowHeight + WEEKLY_RACK_GAP));
  return columns * Math.max(1, rows);
}

function WeeklyStripSkeleton() {
  return (
    <div className="w2-strip mt-3.5" aria-hidden>
      {Array.from({ length: WEEKLY_STRIP_SIZE }).map((_, i) => (
        <div key={i} className="w2-strip-thumb skeleton-card" />
      ))}
    </div>
  );
}

function WeeklyArchiveSkeleton() {
  const rackCardCount = weeklyRackSkeletonCount();

  return (
    <>
      <section aria-hidden>
        <div className="wx-card skeleton-card" style={{ aspectRatio: '21/9' }} />
        <WeeklyStripSkeleton />
      </section>
      <section className="mt-14" aria-hidden>
        <div className="skeleton-card mb-4 h-[10px] w-28 rounded" />
        <div className="w2-rack">
          {Array.from({ length: rackCardCount }).map((_, i) => (
            <div key={i} className="wx-card skeleton-card" style={{ aspectRatio: '16/10' }} />
          ))}
        </div>
      </section>
    </>
  );
}

/**
 * Weekly archive v2 — the "magazine rack", mirroring the Mac client:
 * no timeline pane. The latest issue opens the page as a full-width
 * 21:9 spread with a strip of its slate; every past issue sits below
 * as a 16:10 cover card in a full-width adaptive grid.
 */
export default function WeeklyArchivePage() {
  const { t } = useTranslation('browse');
  const location = useLocation();
  const [rows, setRows] = useState<WeeklyArchiveEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  // Latest issue's slate for the spread strip.
  const [latestPicksResult, setLatestPicksResult] = useState<{ issueKey: string; picks: WeeklyPicked[] }>({
    issueKey: '',
    picks: [],
  });

  useEffect(() => {
    getWeeklyArchive(100)
      .then((r) => { setRows(r.data.data || []); setError(false); })
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, []);

  const latest = rows[0];
  const past = rows.slice(1);
  const latestIssueKey = latest ? `${latest.year}-${latest.week}` : '';
  const latestYear = latest?.year;
  const latestWeek = latest?.week;
  const latestPalette = latest?.color_palette;
  const latestDominant = latest?.dominant_color;
  const latestAccent = latest?.accent_color;
  const latestPicks = latestPicksResult.issueKey === latestIssueKey ? latestPicksResult.picks : [];
  const latestPicksLoading = Boolean(latestIssueKey && latestPicksResult.issueKey !== latestIssueKey);

  useEffect(() => {
    if (!latestYear || !latestWeek) return;
    let cancelled = false;
    const issueKey = `${latestYear}-${latestWeek}`;
    getWeeklyByWeek(latestYear, latestWeek)
      .then((r) => {
        if (!cancelled) setLatestPicksResult({ issueKey, picks: r.data.data.picks || [] });
      })
      .catch(() => {
        if (!cancelled) setLatestPicksResult({ issueKey, picks: [] });
      });
    return () => {
      cancelled = true;
    };
  }, [latestYear, latestWeek]);

  // Tint the page mesh from the latest issue.
  const rootRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const root = rootRef.current;
    if (!root || !latestIssueKey) return;
    const parts = (latestPalette || '').split(',').map((s) => s.trim()).filter(Boolean);
    const tint = latestDominant || latestAccent;
    if (parts.length >= 3) {
      root.style.setProperty('--w-c1', parts[0]);
      root.style.setProperty('--w-c2', parts[Math.floor(parts.length / 2)]);
      root.style.setProperty('--w-c3', parts[parts.length - 1]);
    } else if (tint) {
      root.style.setProperty('--w-c1', tint);
      root.style.setProperty('--w-c2', tint);
      root.style.setProperty('--w-c3', tint);
    }
  }, [latestIssueKey, latestPalette, latestDominant, latestAccent]);

  const heroPick = latestPicks.find((p) => p.is_hero) || latestPicks[0];
  const strip = latestPicks.filter((p) => p.id !== heroPick?.id);

  return (
    <div ref={rootRef} className="w-weekly-archive min-h-full">
      <div className="w-weekly-mesh" aria-hidden />
      <PageMeta
        title={t('weekly.archiveMetaTitle')}
        description={t('weekly.archiveMetaDescription')}
      />
      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 py-10">
        <header className="mb-10">
          <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">{t('weekly.archiveKicker')}</div>
          <h1 className="display text-[clamp(34px,4vw,52px)] leading-[1.05] mt-2 text-ink">
            <Trans i18nKey="weekly.archiveHeading" ns="browse" components={[<em key="0" />]} />
          </h1>
          <p className="text-ink-2 mt-3 max-w-2xl text-[14px] leading-relaxed">
            {t('weekly.archiveIntro')}
          </p>
        </header>

        {loading ? (
          <WeeklyArchiveSkeleton />
        ) : error ? (
          <ErrorState />
        ) : rows.length === 0 ? (
          <EmptyState
            title={t('weekly.emptyTitle')}
            message={t('weekly.emptyMessage')}
          />
        ) : (
          <>
            {/* ── Latest issue spread ── */}
            {latest && (
              <section>
                <Link to={`/weekly-picks/${latest.year}/${latest.week}`} className="wx-card block w2-cover" style={{ aspectRatio: '21/9' }}>
                  {latest.cover_url && (
                    <img src={latest.cover_url} alt="" loading="eager" decoding="async" fetchPriority="high" />
                  )}
                  <div className="wx-card-scrim" />
                  <div className="w2-stamp">
                    <span className="w-stamp-kicker">{t('weekly.stampKicker')}</span>
                    <span className="w2-stamp-week display">{t('weekly.weekTitle', { num: latest.week })}</span>
                    <span className="w-stamp-meta">
                      {t('weekly.stampMeta', {
                        date: fmtDate(isoWeekFriday(latest.year, latest.week)),
                        year: latest.year,
                        num: latest.count,
                      })}
                    </span>
                  </div>
                  <span className="w2-cover-cta glass glass-pill glass-bounce">
                    {t('weekly.viewAllPicks', { num: latest.count })}
                    <AiOutlineArrowRight size={13} />
                  </span>
                </Link>

                {latestPicksLoading ? (
                  <WeeklyStripSkeleton />
                ) : strip.length > 0 && (
                  <div className="w2-strip mt-3.5">
                    {strip.map((p) => (
                      <Link
                        key={p.id}
                        to={`/wallpaper/${p.slug || p.id}`}
                        state={{ background: location }}
                        className="w2-strip-thumb"
                        style={{ backgroundColor: p.dominant_color || undefined }}
                      >
                        <img src={p.thumb_url} alt={p.title || ''} loading="lazy" decoding="async" />
                      </Link>
                    ))}
                  </div>
                )}
              </section>
            )}

            {/* ── Past issues rack ── */}
            {past.length > 0 && (
              <section className="mt-14">
                <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted mb-4">{t('weekly.archiveKicker')}</div>
                <div className="w2-rack">
                  {past.map((r) => (
                    <Link
                      key={`${r.year}-${r.week}`}
                      to={`/weekly-picks/${r.year}/${r.week}`}
                      className="wx-card block w2-cover"
                      style={{ aspectRatio: '16/10', backgroundColor: r.dominant_color || undefined }}
                    >
                      {r.cover_url && <img src={r.cover_url} alt="" loading="lazy" decoding="async" />}
                      <div className="wx-card-scrim" />
                      <div className="w2-stamp is-compact">
                        <span className="w2-stamp-week display">{t('weekly.weekTitle', { num: r.week })}</span>
                        <span className="w-stamp-meta">
                          {t('weekly.stampMeta', {
                            date: fmtDate(isoWeekFriday(r.year, r.week)),
                            year: r.year,
                            num: r.count,
                          })}
                        </span>
                      </div>
                    </Link>
                  ))}
                </div>
              </section>
            )}
          </>
        )}
      </main>
    </div>
  );
}
