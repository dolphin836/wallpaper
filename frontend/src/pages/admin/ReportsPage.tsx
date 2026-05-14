import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import type { AdminReportRow } from '../../api/admin';
import {
  Card,
  PageHeader,
  Spinner,
  Empty,
  Pagination,
  fmtDate,
  StatusBadge,
  REPORT_STATUS,
  WALLPAPER_STATUS,
} from './components';

const REASON_LABEL: Record<string, string> = {
  nsfw: '不适当内容',
  copyright: '版权问题',
  spam: '垃圾信息',
  low_quality: '质量过低',
  other: '其他',
};

export default function ReportsPage() {
  const [items, setItems] = useState<AdminReportRow[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [status, setStatus] = useState<number | -1>(0); // default to open
  const [loading, setLoading] = useState(false);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin.listAdminReports({ page, limit, status: status >= 0 ? status : undefined })
      .then((r) => {
        setItems(r.data.data.items);
        setTotal(r.data.data.total);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, status]);

  useEffect(() => { fetchList(); }, [fetchList]);

  const resolve = (id: number, newStatus: number, removeWallpaper: boolean, resolveAll = true) => {
    admin.resolveAdminReport(id, {
      status: newStatus,
      remove_wallpaper: removeWallpaper,
      resolve_all_for_target: resolveAll,
    }).then(() => {
      toast.success('已更新');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  return (
    <>
      <PageHeader title="举报处理" subtitle={`共 ${total} 条`} />
      <div className="px-8 pb-8 space-y-4">
        <Card>
          <div className="px-5 py-3 flex flex-wrap gap-3 items-center text-sm">
            <select value={status} onChange={(e) => { setStatus(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={-1}>全部</option>
              <option value={0}>待处理</option>
              <option value={1}>已处理</option>
              <option value={2}>已驳回</option>
            </select>
          </div>

          {loading ? <Spinner /> : items.length === 0 ? <Empty>没有举报记录</Empty> : (
            <ul className="divide-y divide-slate-100 dark:divide-slate-800">
              {items.map((r) => {
                const st = REPORT_STATUS[r.status] ?? { label: String(r.status), tone: 'mute' as const };
                const wpSt = WALLPAPER_STATUS[r.wallpaper_status];
                return (
                  <li key={r.id} className="px-5 py-4 flex gap-4">
                    <div className="w-20 h-14 rounded bg-slate-100 dark:bg-slate-800 overflow-hidden flex-shrink-0">
                      {r.wallpaper_thumb && <img src={r.wallpaper_thumb} alt="" className="w-full h-full object-cover" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <StatusBadge label={REASON_LABEL[r.reason] || r.reason} tone="bad" />
                        <StatusBadge label={st.label} tone={st.tone} />
                        {wpSt && <StatusBadge label={`壁纸 · ${wpSt.label}`} tone={wpSt.tone} />}
                        <span className="text-xs text-slate-400">{fmtDate(r.created_at)}</span>
                      </div>
                      <Link to={`/wallpaper/${r.wallpaper_slug}`} className="block font-medium mt-1.5 truncate hover:underline">
                        {r.wallpaper_title || `#${r.wallpaper_id}`}
                      </Link>
                      {r.note && <p className="text-sm text-slate-500 mt-1">备注：{r.note}</p>}
                      <p className="text-xs text-slate-400 mt-1">举报人：@{r.reporter_username || `#${r.reporter_user_id}`}</p>
                    </div>
                    {r.status === 0 && (
                      <div className="flex flex-col gap-1.5 items-end self-center text-xs">
                        <button onClick={() => resolve(r.id, 1, true)} className="px-3 py-1 rounded bg-rose-50 text-rose-600 hover:bg-rose-100 dark:bg-rose-900/30 dark:text-rose-300">下架并标记已处理</button>
                        <button onClick={() => resolve(r.id, 1, false)} className="px-3 py-1 rounded bg-emerald-50 text-emerald-600 hover:bg-emerald-100 dark:bg-emerald-900/30 dark:text-emerald-300">仅标记已处理</button>
                        <button onClick={() => resolve(r.id, 2, false, false)} className="px-3 py-1 rounded bg-slate-100 text-slate-600 hover:bg-slate-200 dark:bg-slate-800 dark:text-slate-300">驳回</button>
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </Card>
      </div>
    </>
  );
}
