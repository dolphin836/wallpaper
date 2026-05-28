import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import type { AdminWeekSummary, AdminWeeklyPick } from '../../api/admin';
import { Card, PageHeader, Spinner, Empty } from './components';

/**
 * Weekly Picks management. Two panes: a left index of every week that has
 * a curated slate (newest first), and a right detail pane showing the 10
 * picks for the selected week. Clicking any tile sets it as the hero —
 * the single pick whose original_url is publicly exposed and that drives
 * the home page's big top image. Server enforces "at most one hero per
 * week" via a partial unique index.
 */
export default function WeeklyPicksPage() {
  const [weeks, setWeeks] = useState<AdminWeekSummary[]>([]);
  const [weeksLoading, setWeeksLoading] = useState(false);
  const [selected, setSelected] = useState<{ year: number; week: number } | null>(null);
  const [picks, setPicks] = useState<AdminWeeklyPick[]>([]);
  const [picksLoading, setPicksLoading] = useState(false);
  const [updatingId, setUpdatingId] = useState<number | null>(null);

  const fetchWeeks = useCallback(() => {
    setWeeksLoading(true);
    admin.adminListWeeklyPickWeeks()
      .then((r) => {
        const list = r.data.data || [];
        setWeeks(list);
        // Auto-select latest week on first load if nothing is selected yet.
        if (!selected && list.length > 0) {
          setSelected({ year: list[0].year, week: list[0].week });
        }
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to load weeks'))
      .finally(() => setWeeksLoading(false));
  // selected intentionally excluded — we only auto-select on the very first load.
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
    if (!selected || p.is_hero || updatingId === p.id) return;
    setUpdatingId(p.id);
    admin.adminSetWeeklyPickHero(selected.year, selected.week, p.id)
      .then(() => {
        // Optimistically flip is_hero locally so the UI updates without a re-fetch.
        setPicks((rows) => rows.map((r) => ({ ...r, is_hero: r.id === p.id })));
        // Refresh the weeks index so the hero thumbnail on the left list updates too.
        fetchWeeks();
        toast.success('Hero updated');
      })
      .catch((e) => toast.error(e?.response?.data?.message || 'Failed to set hero'))
      .finally(() => setUpdatingId(null));
  };

  return (
    <div>
      <PageHeader
        title="Weekly Picks"
        subtitle="Curate this week's slate. The hero pick drives the home-page top image."
      />
      <div className="grid grid-cols-12 gap-4">
        {/* ─── Left: weeks index ─── */}
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

        {/* ─── Right: picks of the selected week ─── */}
        <div className="col-span-8">
          <Card>
            {!selected ? (
              <Empty>Pick a week on the left to see its slate.</Empty>
            ) : (
              <>
                <div className="px-4 py-2.5 border-b border-hair flex items-center justify-between">
                  <div>
                    <div className="text-[15px] font-semibold text-ink">
                      Week {selected.week} · {selected.year}
                    </div>
                    <div className="text-[11px] text-muted mt-0.5">
                      Click a tile to set it as the hero. Only the hero pick exposes its original_url.
                    </div>
                  </div>
                </div>
                <div className="p-4">
                  {picksLoading ? <Spinner />
                    : picks.length === 0 ? <Empty>No picks for this week.</Empty>
                    : (
                      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-3">
                        {picks.map((p) => (
                          <button
                            key={p.id}
                            onClick={() => setHero(p)}
                            disabled={updatingId !== null || p.is_hero}
                            className={`group relative aspect-[4/5] overflow-hidden rounded-lg border-2 transition-all text-left ${
                              p.is_hero
                                ? 'border-accent ring-2 ring-accent/40'
                                : 'border-hair hover:border-ink cursor-pointer'
                            } ${updatingId === p.id ? 'opacity-60' : ''}`}
                            title={p.is_hero ? 'Current hero' : 'Click to set as hero'}
                          >
                            <img
                              src={p.thumb_url || p.preview_url}
                              alt={p.title || `Wallpaper ${p.id}`}
                              className="absolute inset-0 w-full h-full object-cover"
                            />
                            <div className="absolute inset-x-0 bottom-0 px-2 py-1.5 bg-gradient-to-t from-black/70 to-transparent flex items-end justify-between gap-2">
                              <span className="text-[10px] mono uppercase tracking-wider text-white/85">
                                №{String(p.sort_order + 1).padStart(2, '0')}
                              </span>
                              {p.is_hero && (
                                <span className="text-[10px] mono uppercase tracking-wider font-bold text-white bg-accent px-1.5 py-0.5 rounded">
                                  HERO
                                </span>
                              )}
                            </div>
                          </button>
                        ))}
                      </div>
                    )}
                </div>
              </>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
