import { useEffect, useState, useCallback, useRef } from 'react';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import type { AdminWeekSummary, AdminWeeklyPick, AdminWallpaperRow } from '../../api/admin';
import { Card, PageHeader, Spinner, Empty } from './components';

const PAGE_SIZE = 24;

function currentISOWeek() {
  const d = new Date();
  const date = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((date.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return { year: date.getUTCFullYear(), week };
}

/**
 * Manual Weekly Picks management.
 *
 * This page is the source of truth for creating and editing a weekly slate.
 * Admins choose the target ISO week, add published wallpapers, set the hero,
 * reorder locally, then save the full ordered slate in one request.
 */
export default function WeeklyPicksPage() {
  const now = currentISOWeek();
  const [weeks, setWeeks] = useState<AdminWeekSummary[]>([]);
  const [weeksLoading, setWeeksLoading] = useState(false);
  const [selected, setSelected] = useState<{ year: number; week: number } | null>(null);
  const [yearInput, setYearInput] = useState(String(now.year));
  const [weekInput, setWeekInput] = useState(String(now.week));
  const [picks, setPicks] = useState<AdminWeeklyPick[]>([]);
  const [picksLoading, setPicksLoading] = useState(false);
  const [busyId, setBusyId] = useState<number | null>(null);
  const [saving, setSaving] = useState(false);
  const [showAdd, setShowAdd] = useState(false);

  const fetchWeeks = useCallback(() => {
    setWeeksLoading(true);
    admin.adminListWeeklyPickWeeks()
      .then((r) => {
        const list = r.data.data || [];
        setWeeks(list);
        if (!selected && list.length > 0) {
          setSelected({ year: list[0].year, week: list[0].week });
          setYearInput(String(list[0].year));
          setWeekInput(String(list[0].week));
        }
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载周列表失败'))
      .finally(() => setWeeksLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchPicks = useCallback((year: number, week: number) => {
    setPicksLoading(true);
    setPicks([]);
    admin.adminGetWeeklyPickWeek(year, week)
      .then((r) => setPicks((r.data.data.picks || []).sort((a, b) => a.sort_order - b.sort_order)))
      .catch((e) => toast.error(e?.response?.data?.message || '加载推荐失败'))
      .finally(() => setPicksLoading(false));
  }, []);

  useEffect(() => { fetchWeeks(); }, [fetchWeeks]);
  useEffect(() => {
    if (selected) fetchPicks(selected.year, selected.week);
  }, [selected, fetchPicks]);

  const openWeek = () => {
    const year = Number(yearInput);
    const week = Number(weekInput);
    if (!Number.isInteger(year) || !Number.isInteger(week) || year <= 0 || week < 1 || week > 53) {
      toast.error('请输入有效的 ISO 年份和周数');
      return;
    }
    setSelected({ year, week });
  };

  const selectWeek = (w: AdminWeekSummary) => {
    setSelected({ year: w.year, week: w.week });
    setYearInput(String(w.year));
    setWeekInput(String(w.week));
  };

  const setHero = (p: AdminWeeklyPick) => {
    if (!selected || p.is_hero || busyId !== null) return;
    setBusyId(p.id);
    admin.adminSetWeeklyPickHero(selected.year, selected.week, p.id)
      .then(() => {
        setPicks((rows) => rows.map((r) => ({ ...r, is_hero: r.id === p.id })));
        fetchWeeks();
        toast.success('Hero 已更新');
      })
      .catch((e) => toast.error(e?.response?.data?.message || '设置 hero 失败'))
      .finally(() => setBusyId(null));
  };

  const removePick = (p: AdminWeeklyPick) => {
    if (!selected || busyId !== null) return;
    if (!confirm(`从 ${selected.year} W${selected.week} 移除这张壁纸？`)) return;
    setBusyId(p.id);
    admin.adminRemoveWeeklyPick(selected.year, selected.week, p.id)
      .then(() => {
        fetchPicks(selected.year, selected.week);
        fetchWeeks();
        toast.success('已移除');
      })
      .catch((e) => toast.error(e?.response?.data?.message || '移除失败'))
      .finally(() => setBusyId(null));
  };

  const addPick = (wallpaperId: number) => {
    if (!selected) return;
    admin.adminAddWeeklyPick(selected.year, selected.week, wallpaperId)
      .then(() => {
        fetchPicks(selected.year, selected.week);
        fetchWeeks();
        setShowAdd(false);
        toast.success('已添加');
      })
      .catch((e) => toast.error(e?.response?.data?.message || '添加失败'));
  };

  const movePick = (index: number, dir: -1 | 1) => {
    setPicks((rows) => {
      const next = [...rows];
      const target = index + dir;
      if (target < 0 || target >= next.length) return rows;
      [next[index], next[target]] = [next[target], next[index]];
      return next.map((p, i) => ({ ...p, sort_order: i }));
    });
  };

  const saveSlate = () => {
    if (!selected || picks.length === 0 || saving) return;
    if (picks.length !== 10 && !confirm(`当前是 ${picks.length} 张，不是 10 张。仍然保存这一期？`)) return;
    const hero = picks.find((p) => p.is_hero) || picks[0];
    setSaving(true);
    admin.adminSaveWeeklyPickWeek(selected.year, selected.week, picks.map((p) => p.id), hero.id)
      .then(() => {
        toast.success('每周推荐已保存');
        fetchPicks(selected.year, selected.week);
        fetchWeeks();
      })
      .catch((e) => toast.error(e?.response?.data?.message || '保存失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div>
      <PageHeader
        title="每周推荐"
        subtitle="手动创建和维护每一期推荐。建议每期 10 张，Hero 会用于首页大图。"
      />
      <div className="px-8 pb-8 grid grid-cols-12 gap-4">
        <div className="col-span-4 space-y-4">
          <Card title="打开 / 新建一期">
            <div className="p-4 space-y-3">
              <div className="grid grid-cols-2 gap-2">
                <label className="text-xs text-slate-500">
                  年份
                  <input
                    value={yearInput}
                    onChange={(e) => setYearInput(e.target.value)}
                    className="mt-1 w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950 text-sm"
                  />
                </label>
                <label className="text-xs text-slate-500">
                  ISO 周
                  <input
                    value={weekInput}
                    onChange={(e) => setWeekInput(e.target.value)}
                    className="mt-1 w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950 text-sm"
                  />
                </label>
              </div>
              <button
                onClick={openWeek}
                className="w-full px-3 py-2 rounded-lg text-sm font-medium bg-slate-900 text-white dark:bg-white dark:text-slate-900 hover:opacity-90"
              >
                打开这一期
              </button>
              <p className="text-xs text-slate-400 leading-relaxed">
                如果这一期还不存在，右侧会显示空白状态，添加第一张壁纸后自动创建。
              </p>
            </div>
          </Card>

          <Card>
            <div className="px-3 py-2 border-b border-slate-200 dark:border-slate-800 text-[11px] uppercase tracking-wider text-slate-500">
              已创建 · {weeks.length}
            </div>
            <div className="max-h-[58vh] overflow-y-auto">
              {weeksLoading && weeks.length === 0 ? <Spinner />
                : weeks.length === 0 ? <Empty>还没有每周推荐。用上方表单创建第一期。</Empty>
                : weeks.map((w) => {
                    const isActive = selected && selected.year === w.year && selected.week === w.week;
                    return (
                      <button
                        key={`${w.year}-${w.week}`}
                        onClick={() => selectWeek(w)}
                        className={`w-full text-left px-3 py-2.5 flex items-center gap-3 border-b border-slate-100 dark:border-slate-800 transition-colors ${
                          isActive ? 'bg-purple-50 dark:bg-purple-500/10' : 'hover:bg-slate-50 dark:hover:bg-slate-800/60'
                        }`}
                      >
                        {w.hero_thumb
                          ? <img src={w.hero_thumb} alt="" className="w-10 h-10 rounded object-cover flex-shrink-0" />
                          : <div className="w-10 h-10 rounded bg-slate-100 dark:bg-slate-800 flex-shrink-0" />}
                        <div className="min-w-0 flex-1">
                          <div className="text-[13px] font-medium truncate">
                            {w.year} · W{String(w.week).padStart(2, '0')}
                          </div>
                          <div className="text-[11px] text-slate-500 truncate">
                            {w.count} 张{w.hero_title ? ` · ${w.hero_title}` : ''}
                          </div>
                        </div>
                      </button>
                    );
                  })}
            </div>
          </Card>
        </div>

        <div className="col-span-8">
          <Card>
            {!selected ? (
              <Empty>选择或创建一个周数后开始编辑。</Empty>
            ) : (
              <>
                <div className="px-4 py-3 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between gap-3">
                  <div>
                    <div className="text-[15px] font-semibold">
                      {selected.year} · W{String(selected.week).padStart(2, '0')}
                    </div>
                    <div className="text-[11px] text-slate-500 mt-0.5">
                      {picks.length} 张 · 点击图片设为 Hero · 上下按钮调整顺序
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setShowAdd(true)}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-medium border border-slate-200 dark:border-slate-700 hover:bg-slate-50 dark:hover:bg-slate-800"
                    >
                      ＋ 添加壁纸
                    </button>
                    <button
                      onClick={saveSlate}
                      disabled={saving || picks.length === 0}
                      className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-[12px] font-medium bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-50"
                    >
                      {saving ? '保存中…' : '保存这一期'}
                    </button>
                  </div>
                </div>
                <div className="p-4">
                  {picksLoading ? <Spinner />
                    : picks.length === 0 ? <Empty>这一期还没有壁纸，点击右上角“添加壁纸”。</Empty>
                    : (
                      <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-3">
                        {picks.map((p, index) => (
                          <div
                            key={p.id}
                            className={`group relative aspect-[4/5] overflow-hidden rounded-lg border-2 transition-all ${
                              p.is_hero ? 'border-purple-500 ring-2 ring-purple-500/30' : 'border-slate-200 dark:border-slate-700'
                            } ${busyId === p.id ? 'opacity-60' : ''}`}
                          >
                            <button
                              onClick={() => setHero(p)}
                              disabled={busyId !== null || p.is_hero}
                              className={`absolute inset-0 w-full h-full text-left ${p.is_hero ? 'cursor-default' : 'cursor-pointer hover:opacity-90'}`}
                              title={p.is_hero ? '当前 Hero' : '设为 Hero'}
                            >
                              <img
                                src={p.thumb_url || p.preview_url}
                                alt={p.title || `Wallpaper ${p.id}`}
                                className="absolute inset-0 w-full h-full object-cover"
                              />
                            </button>
                            <div className="absolute top-1.5 right-1.5 z-10 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <button
                                onClick={(e) => { e.stopPropagation(); movePick(index, -1); }}
                                disabled={index === 0}
                                className="w-6 h-6 rounded-full bg-black/55 hover:bg-black/75 text-white text-xs disabled:opacity-30"
                                title="上移"
                              >↑</button>
                              <button
                                onClick={(e) => { e.stopPropagation(); movePick(index, 1); }}
                                disabled={index === picks.length - 1}
                                className="w-6 h-6 rounded-full bg-black/55 hover:bg-black/75 text-white text-xs disabled:opacity-30"
                                title="下移"
                              >↓</button>
                              <button
                                onClick={(e) => { e.stopPropagation(); removePick(p); }}
                                disabled={busyId !== null}
                                className="w-6 h-6 rounded-full bg-black/55 hover:bg-rose-500 text-white text-sm leading-none disabled:opacity-30"
                                title="移除"
                              >×</button>
                            </div>
                            <div className="absolute inset-x-0 bottom-0 px-2 py-1.5 bg-gradient-to-t from-black/75 to-transparent flex items-end justify-between gap-2 pointer-events-none">
                              <span className="text-[10px] font-mono uppercase tracking-wider text-white/85">
                                #{String(index + 1).padStart(2, '0')}
                              </span>
                              {p.is_hero && (
                                <span className="text-[10px] font-mono uppercase tracking-wider font-bold text-white bg-purple-500 px-1.5 py-0.5 rounded">
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
          onPick={addPick}
          onClose={() => setShowAdd(false)}
        />
      )}
    </div>
  );
}

export function AddWallpaperModal({
  existingIds,
  onPick,
  onClose,
  qualityFilter = 'weekly_eligible',
}: {
  existingIds: number[];
  onPick: (id: number, wallpaper?: AdminWallpaperRow) => void;
  onClose: () => void;
  qualityFilter?: string;
}) {
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
      status: 1,
      quality_flag: qualityFilter || undefined,
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
      .catch((e) => toast.error(e?.response?.data?.message || '搜索失败'))
      .finally(() => {
        if (requestSeqRef.current !== seq) return;
        setLoading(false);
        setLoadingMore(false);
      });
  }, [qualityFilter]);

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

  useEffect(() => {
    const fn = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', fn);
    return () => window.removeEventListener('keydown', fn);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-[80] flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
      onClick={(e) => { e.stopPropagation(); onClose(); }}
    >
      <div
        className="w-full max-w-3xl max-h-[calc(100vh-2rem)] bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-xl shadow-2xl flex flex-col overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-4 py-3 border-b border-slate-200 dark:border-slate-800 flex items-center gap-3 flex-shrink-0">
          <input
            type="text"
            autoFocus
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索标题，留空显示最新已发布"
            className="flex-1 px-3 py-2 text-[14px] bg-slate-50 dark:bg-slate-950 border border-slate-200 dark:border-slate-700 rounded-lg outline-none focus:border-purple-500"
          />
          <button onClick={onClose} className="px-3 py-2 text-[13px] text-slate-500 hover:text-slate-900 dark:hover:text-white transition-colors">
            关闭
          </button>
        </div>
        <div
          className="p-4 min-h-0 flex-1 overflow-y-auto overscroll-contain"
          onScroll={(e) => {
            const el = e.currentTarget;
            if (el.scrollHeight - el.scrollTop - el.clientHeight < 260) loadMore();
          }}
        >
          {loading && results.length === 0 ? <Spinner />
            : results.length === 0 ? <Empty>没有找到可选壁纸。</Empty>
            : (
              <>
                <div className="grid grid-cols-3 sm:grid-cols-4 gap-3">
                  {results.map((w) => {
                    const inSlate = existing.has(w.id);
                    return (
                      <button
                        key={w.id}
                        disabled={inSlate}
                        onClick={() => onPick(w.id, w)}
                        className={`group relative aspect-[4/5] overflow-hidden rounded-lg border-2 transition-all ${
                          inSlate
                            ? 'border-slate-200 dark:border-slate-700 opacity-40 cursor-not-allowed'
                            : 'border-slate-200 dark:border-slate-700 hover:border-purple-500 cursor-pointer'
                        }`}
                        title={inSlate ? '已在当前列表中' : w.title || `Wallpaper ${w.id}`}
                      >
                        <img src={w.thumb_url || w.preview_url} alt="" className="absolute inset-0 w-full h-full object-cover" />
                        {inSlate && (
                          <div className="absolute inset-0 flex items-center justify-center bg-black/50">
                            <span className="text-[10px] font-mono uppercase tracking-wider font-bold text-white bg-black/60 px-2 py-0.5 rounded">
                              已添加
                            </span>
                          </div>
                        )}
                        <div className="absolute inset-x-0 bottom-0 px-2 py-1 bg-gradient-to-t from-black/70 to-transparent">
                          <span className="text-[10px] text-white/85 truncate block">
                            #{w.id} · {w.width}×{w.height}
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
                      className="px-4 py-2 rounded-full border border-slate-200 dark:border-slate-700 text-[12px] font-medium text-slate-500 hover:text-slate-900 dark:hover:text-white hover:border-purple-500 transition-colors"
                    >
                      加载更多
                    </button>
                  ) : (
                    <span className="text-[11px] font-mono uppercase tracking-wider text-slate-400">
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
