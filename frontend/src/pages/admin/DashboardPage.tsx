import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import * as admin from '../../api/admin';
import { Card, PageHeader, Spinner, StatCard, fmtNumber, fmtDate, fmtBytes } from './components';
import type { AdminOverview, AdminSeries, AdminTops, DailyPoint, StorageResp, LLMCostResp } from '../../api/admin';

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

function fmtUSD(n: number): string {
  // Anthropic costs run from sub-cent to single-dollar per day. Always
  // show 2 decimals so "$0.01" doesn't render as "$0".
  return `$${n.toFixed(2)}`;
}

function LLMCostCard({ data }: { data: LLMCostResp | null }) {
  if (!data) {
    return (
      <div className="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 px-5 py-4">
        <Spinner />
      </div>
    );
  }
  const s = data.summary!;
  // Single-color sparkline of the last 30 days. Stretches to card width
  // so spend spikes are visually proportional regardless of magnitude.
  const max = Math.max(0.0001, ...s.daily.map((d) => d.usd));
  const w = 600;
  const h = 50;
  const padX = 4;
  const innerW = w - padX * 2;
  const innerH = h - 8;
  const xAt = (i: number) =>
    padX + (s.daily.length <= 1 ? innerW / 2 : (i / (s.daily.length - 1)) * innerW);
  const yAt = (v: number) => 4 + innerH - (v / max) * innerH;
  const polyline = s.daily.map((d, i) => `${xAt(i)},${yAt(d.usd)}`).join(' ');

  const purposeTotal = (s.by_purpose ?? []).reduce((a, b) => a + b.usd, 0);

  return (
    <div className="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 px-5 py-4">
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 items-center">
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide">今天</div>
          <div className="text-2xl font-semibold mt-1.5 text-emerald-600 dark:text-emerald-400">{fmtUSD(s.today_usd)}</div>
        </div>
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide">过去 7 天</div>
          <div className="text-2xl font-semibold mt-1.5">{fmtUSD(s.last_7d_usd)}</div>
        </div>
        <div>
          <div className="text-xs text-slate-500 uppercase tracking-wide">过去 30 天</div>
          <div className="text-2xl font-semibold mt-1.5">{fmtUSD(s.last_30d_usd)}</div>
          <div className="text-[11px] text-slate-400 mt-0.5">
            {(s.total_calls ?? 0).toLocaleString()} 次调用 · 充值额减此值 ≈ 剩余
          </div>
        </div>
        <div className="overflow-hidden">
          <div className="text-xs text-slate-500 uppercase tracking-wide mb-1">30d sparkline</div>
          <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="none">
            <polyline points={polyline} fill="none" stroke="#a855f7" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
      </div>
      {/* Per-purpose breakdown — shows which CLI / hook is burning the
          budget. autotag is image-heavy and almost always the biggest
          line item; weekly_theme is a once-a-week tiny call. */}
      {(s.by_purpose ?? []).length > 0 && (
        <div className="mt-4 pt-4 border-t border-slate-100 dark:border-slate-800">
          <div className="text-[11px] text-slate-400 uppercase tracking-wide mb-2">按用途 · 30 天</div>
          <div className="space-y-1.5">
            {(s.by_purpose ?? []).map((p) => {
              const pct = purposeTotal > 0 ? (p.usd / purposeTotal) * 100 : 0;
              return (
                <div key={p.label} className="text-xs">
                  <div className="flex items-baseline justify-between mb-0.5">
                    <span className="font-mono text-slate-600 dark:text-slate-300">{p.label}</span>
                    <span className="text-slate-500">
                      <span className="font-semibold">{fmtUSD(p.usd)}</span>
                      <span className="text-slate-400 ml-2">{p.count.toLocaleString()} 次</span>
                    </span>
                  </div>
                  <div className="h-1 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden">
                    <div className="h-full bg-purple-500" style={{ width: `${pct}%` }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
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
  const [llmCost, setLLMCost] = useState<LLMCostResp | null>(null);
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

  useEffect(() => {
    // LLM cost is independently best-effort — when ANTHROPIC_ADMIN_API_KEY
    // isn't set the endpoint returns a 503 carrying a "configured: false"
    // payload, which the card renders as a setup hint. Catching here keeps
    // a 503 from spawning a global toast.
    admin.getLLMCost()
      .then((r) => setLLMCost(r.data.data))
      .catch((e) => setLLMCost(e?.response?.data?.data ?? { configured: false }));
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
        {/* Low-disk banner: once the host's free space drops below 2 GiB
            we surface a loud red strip at the top of the dashboard, since
            a near-full disk silently breaks Postgres writes and worker
            image processing before any other indicator gets unhappy. */}
        {storage?.disk && storage.disk.free_bytes < 2 * 1024 ** 3 && (
          <div className="rounded-lg border border-rose-500/40 bg-rose-50 dark:bg-rose-950/40 text-rose-700 dark:text-rose-200 px-4 py-3 flex items-center gap-3">
            <span className="text-xl leading-none">⚠️</span>
            <div className="text-sm">
              <div className="font-semibold">服务器磁盘空间不足</div>
              <div className="text-xs mt-0.5 opacity-90">
                根分区可用 <span className="font-mono">{fmtBytes(storage.disk.free_bytes)}</span> /
                总 <span className="font-mono">{fmtBytes(storage.disk.total_bytes)}</span>
                （已用 {((storage.disk.used_bytes / storage.disk.total_bytes) * 100).toFixed(1)}%）
                — 立刻清理 Docker 缓存 / 旧镜像 / 日志，否则数据库写入和图片处理将很快失败。
              </div>
            </div>
          </div>
        )}
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

            {/* Anthropic Claude API 消费。Admin API 不提供"余额"端点，只有累计花费 —
                所以这里展示 today / 7d / 30d 的实际 USD 支出，你拿"上次充值额" 减去
                这个累计就大致知道剩余。1 小时本地缓存，避免频繁 Admin API 调用。 */}
            <div className="text-xs uppercase tracking-wider text-slate-400 mt-2 mb-1">LLM 消费 · Claude API</div>
            <LLMCostCard data={llmCost} />

            {/* 运营指标。基于 analytics_events 的滚动窗口活跃，加 7 天上传/下载，加 D30 留存。 */}
            <div className="text-xs uppercase tracking-wider text-slate-400 mt-2 mb-1">运营指标 · Growth</div>
            <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-4">
              <StatCard
                label="日活 DAU"
                value={fmtNumber(overview.dau)}
                hint="过去 24 小时活跃用户数"
                tone="info"
              />
              <StatCard
                label="周活 WAU"
                value={fmtNumber(overview.wau)}
                hint="过去 7 天活跃用户数"
              />
              <StatCard
                label="月活 MAU"
                value={fmtNumber(overview.mau)}
                hint="过去 30 天活跃用户数"
              />
              <StatCard
                label="粘性 DAU/MAU"
                value={overview.mau > 0 ? `${(overview.stickiness_ratio * 100).toFixed(1)}%` : '—'}
                hint="20%+ 视为健康"
                tone={overview.stickiness_ratio >= 0.2 ? 'good' : overview.stickiness_ratio >= 0.1 ? 'warn' : 'mute'}
              />
              <StatCard
                label="本周新增上传"
                value={fmtNumber(overview.uploads_last_7_days)}
                hint="过去 7 天新增发布壁纸"
                tone="good"
              />
              <StatCard
                label="本周下载次数"
                value={fmtNumber(overview.downloads_last_7_days)}
                hint="过去 7 天 user_downloads 记录"
              />
              <StatCard
                label="本周新增用户"
                value={fmtNumber(overview.user_new_last_7_days)}
                hint="过去 7 天注册"
              />
              <StatCard
                label="30 天留存"
                value={
                  overview.retention_d30_cohort > 0
                    ? `${((overview.retention_d30_active / overview.retention_d30_cohort) * 100).toFixed(0)}%`
                    : '—'
                }
                hint={
                  overview.retention_d30_cohort > 0
                    ? `${overview.retention_d30_active} / ${overview.retention_d30_cohort} 月前用户本周仍活跃`
                    : '当前还没有满 30 天的注册用户'
                }
                tone={
                  overview.retention_d30_cohort === 0
                    ? 'mute'
                    : overview.retention_d30_active / overview.retention_d30_cohort >= 0.2
                      ? 'good'
                      : 'warn'
                }
              />
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
              {/* Host disk: rendered alongside MinIO usage because the
                  two compete for the same physical bytes — MinIO bytes
                  are a *subset* of disk-used bytes, plus Postgres,
                  build cache, journal logs, etc. */}
              {storage.disk && (() => {
                const d = storage.disk;
                const usedPct = (d.used_bytes / d.total_bytes) * 100;
                const low = d.free_bytes < 2 * 1024 ** 3;
                const barColor = low ? 'bg-rose-500'
                  : usedPct > 80 ? 'bg-amber-500'
                  : 'bg-emerald-500';
                return (
                  <div className="pt-3 border-t border-slate-100 dark:border-slate-800 space-y-2">
                    <div className="flex justify-between text-xs">
                      <span className="text-slate-500">服务器磁盘（根分区）</span>
                      <span className={low ? 'text-rose-600 font-semibold' : 'text-slate-500'}>
                        可用 <span className="font-mono">{fmtBytes(d.free_bytes)}</span>
                        {' / '}
                        总 <span className="font-mono">{fmtBytes(d.total_bytes)}</span>
                      </span>
                    </div>
                    <div className="h-2 w-full rounded-full overflow-hidden bg-slate-100 dark:bg-slate-800">
                      <div className={barColor} style={{ width: `${usedPct}%`, height: '100%' }} />
                    </div>
                    <div className="text-[10px] text-slate-400">
                      已用 {usedPct.toFixed(1)}%
                      {low && <span className="ml-2 text-rose-600 font-semibold">⚠️ 低于 2 GB 阈值</span>}
                    </div>
                  </div>
                );
              })()}
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
