import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import { Card, PageHeader, Spinner, StatCard, fmtNumber, fmtDate, fmtBytes } from './components';
import type { AdminOverview, AdminSeries, AdminTops, DailyPoint, StorageResp } from '../../api/admin';

function StorageBar({ usage }: { usage: import('../../api/admin').BucketUsage }) {
  const total = Math.max(1, usage.total_bytes);
  const segments = [
    { color: 'bg-purple-500',  v: usage.originals_bytes },
    { color: 'bg-sky-500',     v: usage.variants_bytes },
    { color: 'bg-emerald-500', v: usage.previews_bytes },
    { color: 'bg-amber-500',   v: usage.thumbs_bytes },
    { color: 'bg-rose-500',    v: usage.frames_bytes },
    { color: 'bg-slate-400',   v: usage.other_bytes },
  ];
  return (
    <div className="h-3 w-full rounded-full overflow-hidden bg-slate-100 dark:bg-slate-800 flex">
      {segments.map((s, i) => (
        <div key={i} className={s.color} style={{ width: `${(s.v / total) * 100}%` }} />
      ))}
    </div>
  );
}

function StorageSegment({
  color, label, bytes, count, total,
}: { color: string; label: string; bytes: number; count: number; total: number }) {
  const pct = total > 0 ? (bytes / total) * 100 : 0;
  return (
    <div>
      <div className="flex items-center gap-1.5 text-xs text-slate-500">
        <span className={`w-2.5 h-2.5 rounded-full ${color}`} />
        {label}
      </div>
      <div className="text-lg font-semibold mt-0.5">{fmtBytes(bytes)}</div>
      <div className="text-xs text-slate-400">{count.toLocaleString()} 个 · {pct.toFixed(1)}%</div>
    </div>
  );
}

function BarChart({ data, label, color = '#a855f7' }: { data: DailyPoint[]; label: string; color?: string }) {
  if (!data || data.length === 0) {
    return <div className="text-xs text-slate-400 px-5 py-6">暂无数据</div>;
  }
  const max = Math.max(1, ...data.map((d) => d.count));
  const w = 800;
  const h = 140;
  const padX = 8;
  const innerW = w - padX * 2;
  const barW = innerW / data.length;
  return (
    <div className="px-5 pb-5">
      <div className="flex items-center justify-between mb-2">
        <span className="text-sm font-medium">{label}</span>
        <span className="text-xs text-slate-400">最近 {data.length} 天 · 峰值 {max}</span>
      </div>
      <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="none">
        {data.map((d, i) => {
          const barH = (d.count / max) * (h - 20);
          return (
            <g key={d.day}>
              <rect
                x={padX + i * barW + 1}
                y={h - barH - 2}
                width={Math.max(2, barW - 2)}
                height={Math.max(1, barH)}
                fill={color}
                opacity={0.85}
              >
                <title>{d.day}: {d.count}</title>
              </rect>
            </g>
          );
        })}
      </svg>
      <div className="flex justify-between text-[10px] text-slate-400 mt-1">
        <span>{data[0]?.day}</span>
        <span>{data[data.length - 1]?.day}</span>
      </div>
    </div>
  );
}

export default function DashboardPage() {
  const [overview, setOverview] = useState<AdminOverview | null>(null);
  const [series, setSeries] = useState<AdminSeries | null>(null);
  const [tops, setTops] = useState<AdminTops | null>(null);
  const [storage, setStorage] = useState<StorageResp | null>(null);
  const [storageLoading, setStorageLoading] = useState(true);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState('');

  useEffect(() => {
    setLoading(true);
    Promise.all([admin.getOverview(), admin.getSeries(30), admin.getTops('views', 8)])
      .then(([o, s, t]) => {
        setOverview(o.data.data);
        setSeries(s.data.data);
        setTops(t.data.data);
      })
      .catch((e) => setErr(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    // Loaded separately because the first call scans the bucket; we don't
    // want to block the dashboard's other widgets behind it.
    setStorageLoading(true);
    admin.getStorage(false)
      .then((r) => setStorage(r.data.data))
      .catch((e) => toast.error(e?.response?.data?.message || '加载存储统计失败'))
      .finally(() => setStorageLoading(false));
  }, []);

  const refreshStorage = () => {
    setStorageLoading(true);
    admin.getStorage(true)
      .then((r) => { setStorage(r.data.data); toast.success('已刷新'); })
      .catch((e) => toast.error(e?.response?.data?.message || '刷新失败'))
      .finally(() => setStorageLoading(false));
  };

  return (
    <>
      <PageHeader title="总览" subtitle={`更新时间 ${fmtDate(new Date().toISOString())}`} />
      <div className="px-8 pb-12 space-y-6">
        {loading && <Spinner />}
        {err && <div className="text-rose-500 text-sm">{err}</div>}
        {overview && (
          <>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="用户总数" value={fmtNumber(overview.user_total)} hint={`管理员 ${overview.user_admins} · 今日新增 ${overview.user_new_today}`} tone="info" />
              <StatCard label="发布壁纸" value={fmtNumber(overview.wallpaper_total)} hint={`今日 ${overview.wallpaper_today} · 处理中 ${overview.wallpaper_pending}`} tone="good" />
              <StatCard label="合集数" value={fmtNumber(overview.collection_total)} />
              <StatCard label="待处理举报" value={overview.report_open} tone={overview.report_open > 0 ? 'bad' : 'good'} hint={`累计已处理 ${overview.report_resolved}`} />
              <StatCard label="累计浏览" value={fmtNumber(overview.total_views)} />
              <StatCard label="累计下载" value={fmtNumber(overview.total_downloads)} />
              <StatCard label="累计点赞" value={fmtNumber(overview.total_likes)} />
              <StatCard label="累计收藏" value={fmtNumber(overview.total_favorites)} />
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <StatCard label="重复壁纸（pHash 命中）" value={fmtNumber(overview.wallpaper_duplicate)} tone="warn" />
              <StatCard label="处理失败" value={fmtNumber(overview.wallpaper_failed)} tone={overview.wallpaper_failed > 0 ? 'bad' : 'mute'} />
              <StatCard label="已下架" value={fmtNumber(overview.wallpaper_removed)} tone="mute" />
              <StatCard label="金币流通量" value={fmtNumber(overview.total_coins_circled)} />
            </div>
          </>
        )}

        <Card
          title="存储占用 (MinIO)"
          action={
            <div className="flex items-center gap-3 text-xs text-slate-400">
              {storage && (
                <span>
                  更新于 {fmtDate(storage.refreshed)}
                  {storage.cached ? ' · 缓存' : ' · 实时'}
                </span>
              )}
              <button
                onClick={refreshStorage}
                disabled={storageLoading}
                className="px-2.5 py-1 rounded border border-slate-200 dark:border-slate-700 hover:bg-slate-100 dark:hover:bg-slate-800 disabled:opacity-50"
              >
                {storageLoading ? '扫描中…' : '刷新'}
              </button>
            </div>
          }
        >
          {storageLoading && !storage ? (
            <Spinner />
          ) : !storage ? (
            <div className="px-5 py-6 text-sm text-slate-400">无数据</div>
          ) : (
            <div className="p-5 space-y-4">
              <StorageBar usage={storage.usage} />
              <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 text-sm">
                <StorageSegment color="bg-purple-500"  label="原图"   bytes={storage.usage.originals_bytes} count={storage.usage.originals_count} total={storage.usage.total_bytes} />
                <StorageSegment color="bg-sky-500"     label="设备适配" bytes={storage.usage.variants_bytes}  count={storage.usage.variants_count}  total={storage.usage.total_bytes} />
                <StorageSegment color="bg-emerald-500" label="预览图"  bytes={storage.usage.previews_bytes}  count={storage.usage.previews_count}  total={storage.usage.total_bytes} />
                <StorageSegment color="bg-amber-500"   label="缩略图"  bytes={storage.usage.thumbs_bytes}    count={storage.usage.thumbs_count}    total={storage.usage.total_bytes} />
                <StorageSegment color="bg-rose-500"    label="动态帧"  bytes={storage.usage.frames_bytes}    count={storage.usage.frames_count}    total={storage.usage.total_bytes} />
                <StorageSegment color="bg-slate-400"   label="其他"    bytes={storage.usage.other_bytes}     count={storage.usage.other_count}     total={storage.usage.total_bytes} />
              </div>
              <div className="flex justify-between text-sm pt-3 border-t border-slate-100 dark:border-slate-800">
                <span className="text-slate-500">总计 {storage.usage.total_count.toLocaleString()} 个对象</span>
                <span className="font-semibold">{fmtBytes(storage.usage.total_bytes)}</span>
              </div>
            </div>
          )}
        </Card>

        {series && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <Card title="新增用户（30 天）"><BarChart data={series.users} label="users" color="#0ea5e9" /></Card>
            <Card title="新增壁纸（30 天）"><BarChart data={series.wallpapers} label="wallpapers" color="#a855f7" /></Card>
            <Card title="访问事件（30 天）"><BarChart data={series.events} label="events" color="#22c55e" /></Card>
          </div>
        )}

        {tops && (
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <div className="lg:col-span-2">
              <Card title="浏览量 Top">
                <ul className="divide-y divide-slate-100 dark:divide-slate-800">
                  {tops.top.map((w) => (
                    <li key={w.id} className="flex items-center gap-3 px-4 py-2">
                      <div className="w-12 h-9 rounded bg-slate-100 dark:bg-slate-800 overflow-hidden flex-shrink-0">
                        {w.thumb_url && <img src={w.thumb_url} alt="" className="w-full h-full object-cover" />}
                      </div>
                      <Link to={`/wallpaper/${w.slug}`} className="flex-1 text-sm truncate hover:underline">{w.title || `#${w.id}`}</Link>
                      <div className="text-xs text-slate-400 w-16 text-right">{fmtNumber(w.view_count)} 浏览</div>
                      <div className="text-xs text-slate-400 w-16 text-right">{fmtNumber(w.like_count)} 赞</div>
                      <div className="text-xs text-slate-400 w-16 text-right">{fmtNumber(w.download_count)} 下载</div>
                    </li>
                  ))}
                  {tops.top.length === 0 && <li className="py-6 text-center text-xs text-slate-400">无数据</li>}
                </ul>
              </Card>
            </div>
            <Card title="分类分布">
              <ul className="divide-y divide-slate-100 dark:divide-slate-800">
                {tops.categories.map((c) => (
                  <li key={c.category_id} className="flex items-center justify-between px-4 py-2 text-sm">
                    <span>{c.name}</span>
                    <span className="text-slate-500">{c.count}</span>
                  </li>
                ))}
                {tops.categories.length === 0 && <li className="py-6 text-center text-xs text-slate-400">无数据</li>}
              </ul>
            </Card>
          </div>
        )}
      </div>
    </>
  );
}
