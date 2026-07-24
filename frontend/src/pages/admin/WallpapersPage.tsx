import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import type { AdminWallpaperRow, AdminWallpaperTrafficRow, AdminWallpaperTrafficSummary } from '../../api/admin';
import type { Category } from '../../types';
import { useCategories } from '../../hooks/useCategories';
import {
  Card,
  PageHeader,
  Spinner,
  StatusBadge,
  Empty,
  Pagination,
  fmtDate,
  fmtNumber,
  WALLPAPER_STATUS,
} from './components';

const CLIENT_NAMES: Record<string, string> = {
  web: 'Web',
  mac: 'macOS',
  android: 'Android',
  ios: 'iOS',
  windows: 'Windows',
  chrome: 'Chrome 插件',
  unknown: 'Unknown',
};

const EVENT_NAMES: Record<string, string> = {
  view: '浏览',
  like: '喜欢',
  favorite: '收藏',
  download: '下载',
};

type WallpaperTypeFilter = '' | 'ai' | 'heic' | 'video' | 'image';

function clientLabel(value?: string): string {
  if (!value) return '—';
  return CLIENT_NAMES[value.toLowerCase()] || value;
}

export default function WallpapersPage() {
  const [items, setItems] = useState<AdminWallpaperRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<number | -1>(-1);
  const [categoryFilter, setCategoryFilter] = useState<number>(0);
  const [wallpaperTypeFilter, setWallpaperTypeFilter] = useState<WallpaperTypeFilter>('');
  // '' = no filter, 'flagged' / 'unassessed' = synthetic buckets,
  // anything else = exact match on quality_flag column.
  const [qualityFilter, setQualityFilter] = useState<string>('');
  const [sort, setSort] = useState<string>('newest');
  const [loading, setLoading] = useState(false);
  const { categories } = useCategories();
  const [editing, setEditing] = useState<AdminWallpaperRow | null>(null);
  const [trafficTarget, setTrafficTarget] = useState<AdminWallpaperRow | null>(null);
  const [selected, setSelected] = useState<Set<number>>(new Set());
  const [batchBusy, setBatchBusy] = useState(false);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin
      .listAdminWallpapers({
        page,
        limit,
        search: search || undefined,
        status: statusFilter >= 0 ? statusFilter : undefined,
        category_id: categoryFilter || undefined,
        wallpaper_type: wallpaperTypeFilter || undefined,
        quality_flag: qualityFilter || undefined,
        sort,
      })
      .then((r) => {
        setItems(r.data.data.items);
        setTotal(r.data.data.total);
        setSelected(new Set());
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, search, statusFilter, categoryFilter, wallpaperTypeFilter, qualityFilter, sort]);

  useEffect(() => { fetchList(); }, [fetchList]);

  // ── batch selection ──────────────────────────────────────────────
  const toggleSelect = (id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };
  const allSelected = items.length > 0 && items.every((w) => selected.has(w.id));
  const toggleSelectAll = () => {
    setSelected(allSelected ? new Set() : new Set(items.map((w) => w.id)));
  };

  // Each batch action only applies to rows whose status allows it; the
  // toolbar sends just the eligible subset so the backend never has to
  // reject ids that were merely caught by select-all.
  const selectedRows = items.filter((w) => selected.has(w.id));
  const eligible = {
    delete: selectedRows.filter((w) => w.status === 1),
    hard_delete: selectedRows.filter((w) => w.status === 3 || w.status === 4 || w.status === 6),
    approve_review: selectedRows.filter((w) => w.status === 5),
    reject_review: selectedRows.filter((w) => w.status === 5),
  };

  const doBatch = (action: admin.AdminBatchAction, rows: AdminWallpaperRow[], reason?: string) => {
    setBatchBusy(true);
    admin.batchAdminWallpapers(rows.map((w) => w.id), action, reason)
      .then((r) => {
        const { succeeded, failed } = r.data.data;
        if (failed.length === 0) {
          toast.success(`已完成 ${succeeded.length} 张`);
        } else {
          toast.error(`完成 ${succeeded.length} 张，失败 ${failed.length} 张（详见控制台）`);
          console.warn('batch failures:', failed);
        }
        fetchList();
      })
      .catch((e) => toast.error(e?.response?.data?.message || '批量操作失败'))
      .finally(() => setBatchBusy(false));
  };

  const runBatch = (action: admin.AdminBatchAction, rows: AdminWallpaperRow[], confirmMsg: string) => {
    if (rows.length === 0 || batchBusy) return;
    if (!confirm(confirmMsg)) return;
    doBatch(action, rows);
  };

  // prompt doubles as the confirmation here — cancelling it aborts.
  const onBatchReject = () => {
    const rows = eligible.reject_review;
    if (rows.length === 0 || batchBusy) return;
    const reason = window.prompt(`拒绝原因（会显示给上传者，应用到全部 ${rows.length} 张）：`, '');
    if (reason === null) return;
    doBatch('reject_review', rows, reason);
  };

  const onDelete = (id: number) => {
    if (!confirm('确认下架这张壁纸吗？（status -> 已下架，软删）')) return;
    admin.deleteAdminWallpaper(id).then(() => {
      toast.success('已下架');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  const onHardDelete = (id: number, status: number) => {
    const extra = status === 3
      ? '注意：该壁纸曾经发布过，可能仍有用户收藏/点赞过它——所有这些关联记录都会一并清除。'
      : '';
    if (!confirm(`永久删除这张壁纸？此操作不可恢复，会同时删除数据库记录和 MinIO 原图文件。${extra}`)) return;
    admin.hardDeleteAdminWallpaper(id).then(() => {
      toast.success('已永久删除');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '删除失败'));
  };

  const onChangeStatus = (id: number, status: number) => {
    admin.updateAdminWallpaper(id, { status }).then(() => {
      toast.success('状态已更新');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '更新失败'));
  };

  const onReprocess = (id: number) => {
    if (!confirm('重新处理这张壁纸？将重置为"处理中"并重新发送给 image worker。')) return;
    admin.reprocessAdminWallpaper(id).then(() => {
      toast.success('已重新入队，刷新后查看状态');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '重处理失败'));
  };

  const onApproveQuality = (id: number) => {
    if (!confirm('将此壁纸标记为正常质量？将清除 quality flag 并重新生成设备变体。')) return;
    admin.approveAdminWallpaperQuality(id).then(() => {
      toast.success('已批准，正在重新生成变体');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '批准失败'));
  };

  // Review-queue actions exposed inline on the main wallpapers list
  // for pending_review rows, so admins don't have to bounce over to
  // /admin/review-queue when they're already filtering or searching
  // here. Same backend endpoints — just a different surface.
  const onApproveReview = (id: number) => {
    if (!confirm('通过审核并公开发布这张壁纸？')) return;
    admin.approveAdminReview(id).then(() => {
      toast.success('已通过审核');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '通过失败'));
  };

  const onRejectReview = (id: number) => {
    const reason = window.prompt('拒绝原因（会显示给上传者）：', '');
    if (reason === null) return;
    admin.rejectAdminReview(id, reason).then(() => {
      toast.success('已拒绝');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '拒绝失败'));
  };

  return (
    <>
      <PageHeader title="壁纸管理" subtitle={`共 ${total} 张`} />
      <div className="px-8 pb-8 space-y-4">
        <Card>
          <div className="px-5 py-3 flex flex-wrap gap-3 items-center text-sm">
            <input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              placeholder="搜索标题 / 描述 / 上传者"
              className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 w-72"
            />
            <select value={statusFilter} onChange={(e) => { setStatusFilter(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={-1}>全部状态</option>
              <option value={0}>处理中</option>
              <option value={1}>已发布</option>
              <option value={2}>处理失败</option>
              <option value={3}>已下架</option>
              <option value={4}>重复</option>
              <option value={5}>待审核</option>
              <option value={6}>已拒绝</option>
            </select>
            <select value={categoryFilter} onChange={(e) => { setCategoryFilter(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={0}>全部分类</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
            <select
              value={wallpaperTypeFilter}
              onChange={(e) => { setWallpaperTypeFilter(e.target.value as WallpaperTypeFilter); setPage(1); }}
              aria-label="壁纸类型"
              className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900"
            >
              <option value="">全部类型</option>
              <option value="ai">AI</option>
              <option value="heic">HEIC</option>
              <option value="video">Video</option>
              <option value="image">图片</option>
            </select>
            <select value={qualityFilter} onChange={(e) => { setQualityFilter(e.target.value); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="">全部质量</option>
              <option value="flagged">⚑ 已标记（待审核）</option>
              <option value="ok">通过</option>
              <option value="unassessed">未评估</option>
              <option value="low_aesthetic">低美感</option>
              <option value="watermark">水印</option>
              <option value="text_overlay">叠加文字</option>
              <option value="ai_slop">AI 残次</option>
              <option value="blurry">模糊</option>
            </select>
            <select value={sort} onChange={(e) => setSort(e.target.value)} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value="newest">最新</option>
              <option value="views">浏览最多</option>
              <option value="likes">点赞最多</option>
              <option value="downloads">下载最多</option>
            </select>
          </div>

          {selected.size > 0 && (
            <div className="px-5 py-2.5 flex flex-wrap items-center gap-3 text-sm border-t border-slate-100 dark:border-slate-800 bg-purple-50/60 dark:bg-purple-950/20">
              <span className="text-slate-600 dark:text-slate-300 font-medium">已选 {selected.size} 张</span>
              <button
                disabled={batchBusy || eligible.delete.length === 0}
                onClick={() => runBatch('delete', eligible.delete, `确认批量下架 ${eligible.delete.length} 张已发布壁纸？（软删，可恢复）`)}
                className="px-2.5 py-1 rounded text-xs border border-rose-200 dark:border-rose-900 text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-950 disabled:opacity-40 disabled:cursor-not-allowed"
              >批量下架（{eligible.delete.length}）</button>
              <button
                disabled={batchBusy || eligible.hard_delete.length === 0}
                onClick={() => runBatch('hard_delete', eligible.hard_delete, `永久删除 ${eligible.hard_delete.length} 张壁纸？此操作不可恢复，会同时删除数据库记录和 MinIO 文件。`)}
                className="px-2.5 py-1 rounded text-xs border border-rose-300 dark:border-rose-800 bg-rose-600 text-white hover:bg-rose-700 disabled:opacity-40 disabled:cursor-not-allowed"
              >批量永久删除（{eligible.hard_delete.length}）</button>
              <button
                disabled={batchBusy || eligible.approve_review.length === 0}
                onClick={() => runBatch('approve_review', eligible.approve_review, `确认批量通过 ${eligible.approve_review.length} 张待审核壁纸并公开发布？`)}
                className="px-2.5 py-1 rounded text-xs border border-emerald-200 dark:border-emerald-900 text-emerald-600 hover:bg-emerald-50 dark:hover:bg-emerald-950 disabled:opacity-40 disabled:cursor-not-allowed"
              >批量通过（{eligible.approve_review.length}）</button>
              <button
                disabled={batchBusy || eligible.reject_review.length === 0}
                onClick={onBatchReject}
                className="px-2.5 py-1 rounded text-xs border border-amber-200 dark:border-amber-900 text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-950 disabled:opacity-40 disabled:cursor-not-allowed"
              >批量拒绝（{eligible.reject_review.length}）</button>
              <button
                onClick={() => setSelected(new Set())}
                className="ml-auto px-2.5 py-1 rounded text-xs text-slate-500 hover:bg-slate-100 dark:hover:bg-slate-800"
              >清除选择</button>
            </div>
          )}

          {loading ? <Spinner /> : items.length === 0 ? <Empty>无符合条件的壁纸</Empty> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs uppercase tracking-wide">
                  <tr>
                    <th className="px-4 py-2 w-8">
                      <input
                        type="checkbox"
                        checked={allSelected}
                        onChange={toggleSelectAll}
                        className="accent-purple-600 cursor-pointer"
                        title="全选当前页"
                      />
                    </th>
                    <th className="text-left px-4 py-2 font-medium">封面</th>
                    <th className="text-left px-4 py-2 font-medium">标题 / 上传者</th>
                    <th className="text-left px-4 py-2 font-medium">分类</th>
                    <th className="text-left px-4 py-2 font-medium">状态</th>
                    <th className="text-right px-4 py-2 font-medium">数据</th>
                    <th className="text-left px-4 py-2 font-medium">上传时间</th>
                    <th className="text-right px-4 py-2 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {items.map((w) => {
                    const st = WALLPAPER_STATUS[w.status] ?? { label: String(w.status), tone: 'mute' as const };
                    return (
                      <tr key={w.id} className={`hover:bg-slate-50 dark:hover:bg-slate-800/30 ${selected.has(w.id) ? 'bg-purple-50/50 dark:bg-purple-950/20' : ''}`}>
                        <td className="px-4 py-2 w-8">
                          <input
                            type="checkbox"
                            checked={selected.has(w.id)}
                            onChange={() => toggleSelect(w.id)}
                            className="accent-purple-600 cursor-pointer"
                          />
                        </td>
                        <td className="px-4 py-2 w-20">
                          <div className="w-16 h-12 rounded bg-slate-100 dark:bg-slate-800 overflow-hidden">
                            {w.thumb_url && <img src={w.thumb_url} alt="" className="w-full h-full object-cover" />}
                          </div>
                        </td>
                        <td className="px-4 py-2 max-w-xs">
                          <div className="flex items-center gap-2">
                            <Link to={`/wallpaper/${w.slug}`} className="font-medium truncate hover:underline">{w.title || `#${w.id}`}</Link>
                            {w.quality_flag && w.quality_flag !== 'ok' && (
                              <span
                                title={w.quality_notes || w.quality_flag}
                                className="flex-shrink-0 inline-flex items-center px-1.5 py-0.5 text-[10px] rounded border border-rose-300 bg-rose-50 text-rose-700 dark:bg-rose-950 dark:border-rose-800 dark:text-rose-300 whitespace-nowrap"
                              >
                                ⚑ {w.quality_flag.replace('_', ' ')}
                              </span>
                            )}
                          </div>
                          <div className="text-xs text-slate-400 truncate">@{w.uploader_username || '?'} · {w.width}×{w.height}{w.is_dynamic ? ` · ${w.dynamic_type}` : ''}</div>
                        </td>
                        <td className="px-4 py-2 text-slate-500">{w.category_name || '-'}</td>
                        <td className="px-4 py-2"><StatusBadge label={st.label} tone={st.tone} /></td>
                        <td className="px-4 py-2 text-right text-xs text-slate-500 whitespace-nowrap">
                          <div>{fmtNumber(w.view_count)} 浏览</div>
                          <div>{fmtNumber(w.like_count)} 赞 · {fmtNumber(w.download_count)} 下载</div>
                        </td>
	                        <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(w.created_at)}</td>
	                        <td className="px-4 py-2 text-right whitespace-nowrap">
	                          <button onClick={() => setTrafficTarget(w)} className="text-xs text-sky-600 hover:underline mr-3">流量详情</button>
	                          <button onClick={() => setEditing(w)} className="text-xs text-purple-600 hover:underline mr-3">编辑</button>
                          {/* Reprocess: re-queue the wallpaper through the
                              image worker. Available for failed (2) and
                              stuck processing (0) rows. */}
                          {(w.status === 0 || w.status === 2) && (
                            <button onClick={() => onReprocess(w.id)} className="text-xs text-amber-600 hover:underline mr-3">重新处理</button>
                          )}
                          {w.quality_flag && w.quality_flag !== 'ok' && w.status === 1 && (
                            <button onClick={() => onApproveQuality(w.id)} className="text-xs text-emerald-600 hover:underline mr-3">标为正常</button>
                          )}
                          {w.status === 1 && (
                            <button onClick={() => onDelete(w.id)} className="text-xs text-rose-500 hover:underline">下架</button>
                          )}
                          {w.status === 3 && (
                            <>
                              <button onClick={() => onChangeStatus(w.id, 1)} className="text-xs text-emerald-600 hover:underline mr-3">恢复</button>
                              <button onClick={() => onHardDelete(w.id, w.status)} className="text-xs font-medium text-rose-600 hover:underline">永久删除</button>
                            </>
                          )}
                          {w.status === 4 && (
                            <button onClick={() => onHardDelete(w.id, w.status)} className="text-xs font-medium text-rose-600 hover:underline">永久删除</button>
                          )}
                          {w.status === 5 && (
                            <>
                              <button onClick={() => onApproveReview(w.id)} className="text-xs font-medium text-emerald-600 hover:underline mr-3">通过</button>
                              <button onClick={() => onRejectReview(w.id)} className="text-xs font-medium text-rose-600 hover:underline">拒绝</button>
                            </>
                          )}
                          {w.status === 6 && (
                            <button onClick={() => onHardDelete(w.id, w.status)} className="text-xs font-medium text-rose-600 hover:underline">永久删除</button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </Card>
      </div>

      {editing && (
        <EditModal
          wallpaper={editing}
          categories={categories}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); fetchList(); }}
        />
      )}
      {trafficTarget && (
        <TrafficModal wallpaper={trafficTarget} onClose={() => setTrafficTarget(null)} />
      )}
    </>
  );
}

function TrafficModal({ wallpaper, onClose }: { wallpaper: AdminWallpaperRow; onClose: () => void }) {
  const [eventType, setEventType] = useState('');
  const [page, setPage] = useState(1);
  const [items, setItems] = useState<AdminWallpaperTrafficRow[]>([]);
  const [summary, setSummary] = useState<AdminWallpaperTrafficSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const limit = 50;

  const summaryMap = summary.reduce<Record<string, number>>((acc, item) => {
    acc[item.event_type] = item.count;
    return acc;
  }, {});

  useEffect(() => {
    let alive = true;
    setLoading(true);
    admin.getAdminWallpaperTraffic(wallpaper.id, {
      page,
      limit,
      event_type: eventType || undefined,
    })
      .then((r) => {
        if (!alive) return;
        setItems(r.data.data.items ?? []);
        setTotal(r.data.data.total);
        setSummary(r.data.data.summary ?? []);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载流量详情失败'))
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [wallpaper.id, page, eventType]);

  const switchType = (next: string) => {
    setEventType(next);
    setPage(1);
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-5xl max-h-[86vh] overflow-hidden shadow-2xl flex flex-col">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <div>
            <h3 className="font-semibold">流量详情 · #{wallpaper.id}</h3>
            <p className="text-xs text-slate-500 mt-0.5 truncate max-w-2xl">{wallpaper.title || wallpaper.slug}</p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700 dark:hover:text-slate-200">×</button>
        </div>

        <div className="px-5 py-3 flex flex-wrap gap-2 border-b border-slate-100 dark:border-slate-800">
          {[['', '全部'], ['view', '浏览'], ['like', '喜欢'], ['favorite', '收藏'], ['download', '下载']].map(([key, label]) => (
            <button
              key={key || 'all'}
              onClick={() => switchType(key)}
              className={`px-3 py-1.5 rounded-full text-xs border ${
                eventType === key
                  ? 'bg-slate-900 text-white border-slate-900 dark:bg-slate-100 dark:text-slate-900 dark:border-slate-100'
                  : 'border-slate-200 dark:border-slate-700 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800'
              }`}
            >
              {label}
              {key ? <span className="ml-1 opacity-70">{fmtNumber(summaryMap[key] || 0)}</span> : null}
            </button>
          ))}
        </div>

        <div className="overflow-auto flex-1">
          {loading ? <Spinner /> : items.length === 0 ? <Empty>暂无记录</Empty> : (
            <table className="w-full text-sm">
              <thead className="sticky top-0 bg-slate-50 dark:bg-slate-800 text-slate-500 text-xs uppercase tracking-wide">
                <tr>
                  <th className="text-left px-5 py-2 font-medium">事件</th>
                  <th className="text-left px-5 py-2 font-medium">用户 / IP</th>
                  <th className="text-left px-5 py-2 font-medium">客户端</th>
                  <th className="text-left px-5 py-2 font-medium">时间</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                {items.map((row) => (
                  <tr key={row.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
                    <td className="px-5 py-2">
                      <span className="inline-flex px-2 py-0.5 rounded-full bg-slate-100 dark:bg-slate-800 text-xs">
                        {EVENT_NAMES[row.event_type] || row.event_type}
                      </span>
                    </td>
                    <td className="px-5 py-2">
                      {row.user_id > 0 ? (
                        <>
                          <div className="font-medium">{row.nickname || row.username || `#${row.user_id}`}</div>
                          <div className="text-xs text-slate-400">@{row.username || '?'} · #{row.user_id}</div>
                        </>
                      ) : (
                        <>
                          <div className="font-medium">匿名访客</div>
                          <div className="text-xs text-slate-400">{row.ip || '无 IP'}</div>
                        </>
                      )}
                    </td>
                    <td className="px-5 py-2 text-slate-600 dark:text-slate-300">{clientLabel(row.client)}</td>
                    <td className="px-5 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(row.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex items-center justify-between text-xs text-slate-500">
          <span>共 {fmtNumber(total)} 条记录</span>
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </div>
      </div>
    </div>
  );
}

function EditModal({
  wallpaper,
  categories,
  onClose,
  onSaved,
}: {
  wallpaper: AdminWallpaperRow;
  categories: Category[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [title, setTitle] = useState(wallpaper.title);
  const [description, setDescription] = useState(wallpaper.description);
  const [categoryId, setCategoryId] = useState(wallpaper.category_id);
  const [status, setStatus] = useState(wallpaper.status);
  const [saving, setSaving] = useState(false);

  const save = () => {
    setSaving(true);
    admin
      .updateAdminWallpaper(wallpaper.id, { title, description, category_id: categoryId, status })
      .then(() => { toast.success('已保存'); onSaved(); })
      .catch((e) => toast.error(e?.response?.data?.message || '保存失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-lg overflow-hidden">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <h3 className="font-semibold">编辑壁纸 #{wallpaper.id}</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700">×</button>
        </div>
        <div className="p-5 space-y-3">
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">标题</div>
            <input value={title} onChange={(e) => setTitle(e.target.value)} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">描述</div>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950" />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <label className="block text-sm">
              <div className="text-slate-500 mb-1">分类</div>
              <select value={categoryId} onChange={(e) => setCategoryId(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                <option value={0}>未分类</option>
                {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select>
            </label>
            <label className="block text-sm">
              <div className="text-slate-500 mb-1">状态</div>
              <select value={status} onChange={(e) => setStatus(Number(e.target.value))} className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950">
                <option value={0}>处理中</option>
                <option value={1}>已发布</option>
                <option value={2}>处理失败</option>
                <option value={3}>已下架</option>
                <option value={4}>重复</option>
              </select>
            </label>
          </div>
        </div>
        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex justify-end gap-2">
          <button onClick={onClose} className="px-4 py-1.5 rounded text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800">取消</button>
          <button onClick={save} disabled={saving} className="px-4 py-1.5 rounded text-sm bg-purple-600 hover:bg-purple-700 text-white disabled:opacity-60">保存</button>
        </div>
      </div>
    </div>
  );
}
