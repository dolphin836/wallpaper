import { useEffect, useState, useCallback, useRef } from 'react';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import type { AdminWeekSummary, AdminWeeklyPick, AdminWallpaperRow } from '../../api/admin';
import { Card, PageHeader, Spinner, Empty } from './components';

/**
 * Weekly Picks management. Three operations on each week's slate:
 *   • Set hero (click any tile)
 *   • Remove pick (× button on tile, confirm)
 *   • Add pick (toolbar "+" opens a search modal)
 *
 * Server enforces "exactly one hero per week" via a partial unique index
 * and "no duplicate (year, week, wallpaper_id)" via the existing UNIQUE
 * constraint, so the UI doesn't have to do those checks.
 */
export default function WeeklyPicksPage() {
  const [weeks, setWeeks] = useState<AdminWeekSummary[]>([]);
  const [weeksLoading, setWeeksLoading] = useState(false);
  const [selected, setSelected] = useState<{ year: number; week: number } | null>(null);
  const [picks, setPicks] = useState<AdminWeeklyPick[]>([]);
  const [picksLoading, setPicksLoading] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [showAdd, setShowAdd] = useState(false);

  const fetchWeeks = useCallback(() => {
    setWeeksLoading(true);
    admin.adminListWeeklyPickWeeks()
      .then((r) => {
        const list = r.data.data || [];
        setWeeks(list);
        if (!selected && list.length > 0) {
          setSelected({ year: list[0].year, week: list[0].week });
        }
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to load weeks'))
      .finally(() => setWeeksLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchPicks = useCallback((year: number, week: number) => {
    setPicksLoading(true);
    setPicks([]);
    admin.adminGetWeeklyPickWeek(year, week)
      .then((r) => setPicks(r.data.data.picks || []))
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to load picks'))
      .finally(() => setPicksLoading(false));
  }, []);

  useEffect(() => { fetchWeeks(); }, [fetchWeeks]);
  useEffect(() => {
    if (selected) fetchPicks(selected.year, selected.week);
  }, [selected, fetchPicks]);

  const setHero = (p: AdminWeeklyPick) => {
    if (!selected || p.is_hero || busyId !== null) return;
    setBusyId(p.id);
    admin.adminSetWeeklyPickHero(selected.year, selected.week, p.id)
      .then(() => {
        setPicks((rows) => rows.map((r) => ({ ...r, is_hero: r.id === p.id })));
        fetchWeeks();
        toast.success('Hero updated');
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to set hero'))
      .finally(() => setBusyId(null));
  };

  const removePick = (p: AdminWeeklyPick) => {
    if (!selected || busyId !== null) return;
    if (!confirm(`Remove this wallpaper from Week ${selected.week}?`)) return;
    setBusyId(p.id);
    admin.adminRemoveWeeklyPick(selected.year, selected.week, p.id)
      .then(() => {
        // Refresh both the picks list and the weeks index (hero may have
        // auto-promoted to another tile if the removed one was hero).
        fetchPicks(selected.year, selected.week);
        fetchWeeks();
        toast.success('Removed');
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to remove'))
      .finally(() => setBusyId(null));
  };

  const addPick = (wallpaperId: number) => {
    if (!selected) return;
    admin.adminAddWeeklyPick(selected.year, selected.week, wallpaperId)
      .then(() => {
        fetchPicks(selected.year, selected.week);
        fetchWeeks();
        setShowAdd(false);
        toast.success('Added');
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to add'));
  };

  return (
    <div>
      <PageHeader
        title="Weekly Picks"
        subtitle="Curate this week's slate. Click any tile to set it as the hero; × removes; + adds."
      />
      <div className="grid grid-cols-12 gap-4">
        {/* Left: weeks index */}
        <div className="col-span-4">
          <Card>
            <div className="px-3 py-2 border-b border-hair text-[11px] uppercase tracking-wider text-muted">
              All weeks · {weeks.length}
            </div>
            <div className="max-h-[70vh] overflow-y-auto">
              {weeksLoading && weeks.length === 0 ? <Spinner />
                : weeks.length === 0 ? <Empty>No weekly slates yet. Generate one with weekly-drop.</Empty>
                : weeks.map((w) => {
                    const isActive = selected && selected.year === w.year && selected.week === w.week;
                    return (
                      <button
                        key={`${w.year}-${w.week}`}
                        onClick={() => setSelected({ year: w.year, week: w.week })}
                        className={`w-full text-left px-3 py-2.5 flex items-center gap-3 border-b border-hair-soft transition-colors ${
                          isActive ? 'bg-paper-2' : 'hover:bg-paper-2/60'
                        }`}
                      >
                        {w.hero_thumb
                          ? <img src={w.hero_thumb} alt="" className="w-10 h-10 rounded object-cover flex-shrink-0" />
                          : <div className="w-10 h-10 rounded bg-paper-3 flex-shrink-0" />}
                        <div className="min-w-0 flex-1">
                          <div className="text-[13px] font-medium text-ink truncate">
                            Week {w.week} · {w.year}
                          </div>
                          <div className="text-[11px] text-muted truncate">
                            {w.count} picks{w.hero_title ? ` · ${w.hero_title}` : ''}
                          </div>
                        </div>
                      </button>
                    );
                  })}
            </div>
          </Card>
        </div>

        {/* Right: picks of selected week */}
        <div className="col-span-8">
          <Card>
            {!selected ? (
              <Empty>Pick a week on the left to see its slate.</Empty>
            ) : (
              <>
                <div className="px-4 py-2.5 border-b border-hair flex items-center justify-between gap-3">
                  <div>
                    <div className="text-[15px] font-semibold text-ink">
                      Week {selected.week} · {selected.year}
                    </div>
                    <div className="text-[11px] text-muted mt-0.5">
                      {picks.length} picks · click tile = set hero · × removes · + adds
                    </div>
                  </div>
                  <button
                    onClick={() => setShowAdd(true)}
                    className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-medium bg-ink text-paper hover:bg-ink-2 transition-colors"
                  >
                    <span className="text-[14px] leading-none">＋</span>
                    <span>Add wallpaper</span>
                  </button>
                </div>
                <div className="p-4">
                  {picksLoading ? <Spinner />
                    : picks.length === 0 ? <Empty>No picks for this week. Use "+ Add wallpaper" above.</Empty>
                    : (
                      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                        {picks.map((p) => (
                          <div
                            key={p.id}
                            className={`group relative aspect-[4/5] overflow-hidden rounded-lg border-2 transition-all ${
                              p.is_hero
                                ? 'border-accent ring-2 ring-accent/40'
                                : 'border-hair'
                            } ${busyId === p.id ? 'opacity-60' : ''}`}
                          >
                            {/* Click-anywhere-but-the-X-button to set hero. */}
                            <button
                              onClick={() => setHero(p)}
                              disabled={busyId !== null || p.is_hero}
                              className={`absolute inset-0 w-full h-full text-left ${
                                p.is_hero ? 'cursor-default' : 'cursor-pointer hover:opacity-90'
                              }`}
                              title={p.is_hero ? 'Current hero' : 'Click to set as hero'}
                            >
                              <img
                                src={p.thumb_url || p.preview_url}
                                alt={p.title || `Wallpaper ${p.id}`}
                                className="absolute inset-0 w-full h-full object-cover"
                              />
                            </button>
                            {/* Remove button — small × top-right, only visible on hover. */}
                            <button
                              onClick={(e) => { e.stopPropagation(); removePick(p); }}
                              disabled={busyId !== null}
                              title="Remove from week"
                              className="absolute top-1.5 right-1.5 z-10 w-6 h-6 flex items-center justify-center rounded-full bg-black/55 hover:bg-red-500 text-white text-[14px] leading-none opacity-0 group-hover:opacity-100 transition-opacity disabled:opacity-30"
                            >
                              ×
                            </button>
                            {/* Bottom strip — sort_order + hero chip */}
                            <div className="absolute inset-x-0 bottom-0 px-2 py-1.5 bg-gradient-to-t from-black/70 to-transparent flex items-end justify-between gap-2 pointer-events-none">
                              <span className="text-[10px] mono uppercase tracking-wider text-white/85">
                                №{String(p.sort_order + 1).padStart(2, '0')}
                              </span>
                              {p.is_hero && (
                                <span className="text-[10px] mono uppercase tracking-wider font-bold text-white bg-accent px-1.5 py-0.5 rounded">
                                  HERO
                                </span>
                              )}
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                </div>
              </>
            )}
          </Card>
        </div>
      </div>

      {showAdd && selected && (
        <AddWallpaperModal
          existingIds={picks.map((p) => p.id)}
          onPick={(id) => addPick(id)}
          onClose={() => setShowAdd(false)}
        />
      )}
    </div>
  );
}

/**
 * Modal: search published wallpapers and click one to add to the current
 * week. Hides wallpapers already in the slate to avoid the 409 duplicate
 * error. Debounced search; first render auto-fetches a recent page so
 * admin sees something even before typing.
 */
function AddWallpaperModal({
  existingIds, onPick, onClose,
}: {
  existingIds: number[];
  onPick: (id: number) => void;
  onClose: () => void;
}) {
  const PAGE_SIZE = 24;
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<AdminWallpaperRow[]>([]);
  const [page, setPage] = useState(0);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const debounceRef = useRef<number | undefined>(undefined);
  const requestSeqRef = useRef(0);
  const existing = new Set(existingIds);

  const fetchPage = useCallback((q: string, nextPage: number, mode: 'replace' | 'append') => {
    const seq = requestSeqRef.current + 1;
    requestSeqRef.current = seq;
    if (mode === 'replace') {
      setLoading(true);
      setLoadingMore(false);
    } else {
      setLoadingMore(true);
    }
    admin.listAdminWallpapers({
      page: nextPage,
      search: q || undefined,
      status: 1,    // Published only; failed quality flags are filtered out below.
      quality_flag: 'weekly_eligible',
      limit: PAGE_SIZE,
      sort: 'newest',
    })
      .then((r) => {
        if (requestSeqRef.current !== seq) return;
        const data = r.data.data;
        const items = data.items || [];
        setPage(data.page || nextPage);
        setTotal(data.total || 0);
        setResults((prev) => {
          if (mode === 'replace') return items;
          const seen = new Set(prev.map((item) => item.id));
          return [...prev, ...items.filter((item) => !seen.has(item.id))];
        });
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Search failed'))
      .finally(() => {
        if (requestSeqRef.current !== seq) return;
        setLoading(false);
        setLoadingMore(false);
      });
  }, []);

  const loadMore = useCallback(() => {
    if (loading || loadingMore) return;
    if (total > 0 && results.length >= total) return;
    fetchPage(query.trim(), page + 1, 'append');
  }, [fetchPage, loading, loadingMore, page, query, results.length, total]);

  useEffect(() => {
    if (debounceRef.current) window.clearTimeout(debounceRef.current);
    debounceRef.current = window.setTimeout(() => fetchPage(query.trim(), 1, 'replace'), 280);
    return () => { if (debounceRef.current) window.clearTimeout(debounceRef.current); };
  }, [fetchPage, query]);

  // ESC closes
  useEffect(() => {
    const fn = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', fn);
    return () => window.removeEventListener('keydown', fn);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="w-full max-w-3xl max-h-[calc(100vh-2rem)] bg-paper border border-hair rounded-xl shadow-2xl flex flex-col overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-4 py-3 border-b border-hair flex items-center gap-3 flex-shrink-0">
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search title…  (empty = newest published)"
            className="flex-1 px-3 py-2 text-[14px] bg-paper-2 border border-hair rounded-lg outline-none focus:border-ink-2"
          />
          <button onClick={onClose} className="px-3 py-2 text-[13px] text-muted hover:text-ink transition-colors">
            Cancel
          </button>
        </div>
        <div
          className="p-4 min-h-0 flex-1 overflow-y-auto overscroll-contain"
          onScroll={(e) => {
            const el = e.currentTarget;
            if (el.scrollHeight - el.scrollTop - el.clientHeight < 260) {
              loadMore();
            }
          }}
        >
          {loading && results.length === 0 ? <Spinner />
            : results.length === 0 ? <Empty>No wallpapers match.</Empty>
            : (
              <>
                <div className="grid grid-cols-3 sm:grid-cols-4 gap-3">
                  {results.map((w) => {
                    const inSlate = existing.has(w.id);
                    return (
                      <button
                        key={w.id}
                        disabled={inSlate}
                        onClick={() => onPick(w.id)}
                        className={`group relative aspect-[4/5] overflow-hidden rounded-lg border-2 transition-all ${
                          inSlate
                            ? 'border-hair opacity-40 cursor-not-allowed'
                            : 'border-hair hover:border-ink cursor-pointer'
                        }`}
                        title={inSlate ? 'Already in this week' : w.title || `Wallpaper ${w.id}`}
                      >
                        <img
                          src={w.thumb_url || w.preview_url}
                          alt=""
                          className="absolute inset-0 w-full h-full object-cover"
                        />
                        {inSlate && (
                          <div className="absolute inset-0 flex items-center justify-center bg-black/50">
                            <span className="text-[10px] mono uppercase tracking-wider font-bold text-white bg-black/60 px-2 py-0.5 rounded">
                              In slate
                            </span>
                          </div>
                        )}
                        <div className="absolute inset-x-0 bottom-0 px-2 py-1 bg-gradient-to-t from-black/70 to-transparent">
                          <span className="text-[10px] text-white/85 truncate block">
                            №{w.id} · {w.width}×{w.height}
                          </span>
                        </div>
                      </button>
                    );
                  })}
                </div>
                <div className="py-4 text-center">
                  {loadingMore ? (
                    <Spinner />
                  ) : total > 0 && results.length < total ? (
                    <button
                      type="button"
                      onClick={loadMore}
                      className="px-4 py-2 rounded-full border border-hair text-[12px] font-medium text-muted hover:text-ink hover:border-ink transition-colors"
                    >
                      Load more
                    </button>
                  ) : (
                    <span className="text-[11px] mono uppercase tracking-wider text-muted">
                      End · {results.length} wallpapers
                    </span>
                  )}
                </div>
              </>
            )}
        </div>
      </div>
    </div>
  );
}
