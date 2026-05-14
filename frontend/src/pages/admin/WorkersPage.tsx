import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import type { WorkerJob, WorkerSummaryRow } from '../../api/admin';
import {
  Card,
  PageHeader,
  Spinner,
  Empty,
  StatusBadge,
  fmtDate,
  StatCard,
} from './components';

const WORKER_LABEL: Record<string, string> = {
  image: '图片处理 (image)',
  stats: '统计聚合 (stats)',
  phash: '感知哈希 (phash)',
};

const STATUS_TONE: Record<string, 'good' | 'warn' | 'bad' | 'mute' | 'info'> = {
  running: 'warn',
  done: 'good',
  failed: 'bad',
  skipped: 'mute',
};

function fmtDuration(ms: number): string {
  if (!ms || ms <= 0) return '-';
  if (ms < 1000) return `${ms} ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)} s`;
  return `${(ms / 60_000).toFixed(1)} min`;
}

export default function WorkersPage() {
  const [summary, setSummary] = useState<WorkerSummaryRow[]>([]);
  const [jobs, setJobs] = useState<WorkerJob[]>([]);
  const [worker, setWorker] = useState('');
  const [status, setStatus] = useState('');
  const [loading, setLoading] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);

  const fetchAll = useCallback(() => {
    setLoading(true);
    Promise.all([
      admin.getWorkerSummary(),
      admin.getWorkerJobs({ worker: worker || undefined, status: status || undefined, limit: 100 }),
    ])
      .then(([s, j]) => {
        setSummary(s.data.data.summary || []);
        setJobs(j.data.data.items || []);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [worker, status]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  // Auto-refresh every 5 seconds so the admin sees worker jobs progress live.
  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(fetchAll, 5000);
    return () => clearInterval(id);
  }, [autoRefresh, fetchAll]);

  return (
    <>
      <PageHeader
        title="Worker 监控"
        subtitle="每 5 秒自动刷新；图片处理 / 统计聚合的任务流水"
        action={
          <label className="text-sm flex items-center gap-2">
            <input type="checkbox" checked={autoRefresh} onChange={(e) => setAutoRefresh(e.target.checked)} />
            自动刷新
            <button onClick={fetchAll} className="ml-3 px-3 py-1 text-xs border border-slate-200 dark:border-slate-700 rounded hover:bg-slate-100 dark:hover:bg-slate-800">立即刷新</button>
          </label>
        }
      />
      <div className="px-8 pb-8 space-y-5">
        {summary.length === 0 && !loading && <Empty>暂未记录任何 worker 任务</Empty>}
        {summary.length > 0 && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {summary.map((s) => (
              <Card key={s.worker} title={WORKER_LABEL[s.worker] || s.worker}>
                <div className="grid grid-cols-2 gap-3 p-4">
                  <StatCard label="正在运行" value={s.running} tone={s.running > 0 ? 'warn' : 'mute'} />
                  <StatCard label="近 1 小时完成" value={s.done_last_hour} tone="good" />
                  <StatCard label="近 24 小时失败" value={s.failed_last_day} tone={s.failed_last_day > 0 ? 'bad' : 'mute'} />
                  <StatCard label="近 24h 平均耗时" value={fmtDuration(Math.round(s.avg_ms_last_day))} />
                </div>
              </Card>
            ))}
          </div>
        )}

        <Card
          title="最近任务流水（最近 100 条）"
          action={
            <div className="flex gap-2 text-xs">
              <select value={worker} onChange={(e) => setWorker(e.target.value)} className="px-2 py-1 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
                <option value="">全部 worker</option>
                <option value="image">image</option>
                <option value="stats">stats</option>
                <option value="phash">phash</option>
              </select>
              <select value={status} onChange={(e) => setStatus(e.target.value)} className="px-2 py-1 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
                <option value="">全部状态</option>
                <option value="running">运行中</option>
                <option value="done">已完成</option>
                <option value="failed">失败</option>
                <option value="skipped">跳过</option>
              </select>
            </div>
          }
        >
          {loading && jobs.length === 0 ? <Spinner /> : jobs.length === 0 ? <Empty>无任务</Empty> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs uppercase tracking-wide">
                  <tr>
                    <th className="text-left px-4 py-2 font-medium">#</th>
                    <th className="text-left px-4 py-2 font-medium">Worker</th>
                    <th className="text-left px-4 py-2 font-medium">引用</th>
                    <th className="text-left px-4 py-2 font-medium">状态</th>
                    <th className="text-left px-4 py-2 font-medium">开始</th>
                    <th className="text-left px-4 py-2 font-medium">结束</th>
                    <th className="text-right px-4 py-2 font-medium">耗时</th>
                    <th className="text-left px-4 py-2 font-medium">输出 / 错误</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {jobs.map((j) => (
                    <tr key={j.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30 align-top">
                      <td className="px-4 py-2 text-slate-400 text-xs">{j.id}</td>
                      <td className="px-4 py-2 text-xs">{j.worker}<div className="text-slate-400">{j.topic}</div></td>
                      <td className="px-4 py-2 text-xs text-slate-500">{j.ref_id || '-'}</td>
                      <td className="px-4 py-2"><StatusBadge label={j.status} tone={STATUS_TONE[j.status] || 'mute'} /></td>
                      <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(j.started_at)}</td>
                      <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{j.finished_at ? fmtDate(j.finished_at) : '-'}</td>
                      <td className="px-4 py-2 text-xs text-right text-slate-500 whitespace-nowrap">{fmtDuration(j.duration_ms)}</td>
                      <td className="px-4 py-2 text-xs text-slate-500 max-w-md">
                        <div className="whitespace-pre-wrap break-words font-mono text-[11px] text-slate-500 dark:text-slate-400">{j.message || '-'}</div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      </div>
    </>
  );
}
