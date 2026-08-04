import { useEffect, useState, type FormEvent } from 'react';
import toast from 'react-hot-toast';
import {
  getAnalytics,
  getAnalyticsPages,
  getAnalyticsRequests,
  getAnalyticsWallpapers,
  listAdminLoginLogs,
  type AdminLoginLogRow,
  type AnalyticsAPIRequestDay,
  type AnalyticsDay,
  type AnalyticsDetailPage,
  type AnalyticsOverview,
  type AnalyticsPageViewDay,
  type AnalyticsWallpaperViewDay,
} from '../../api/admin';
import { Card, PageHeader, Pagination, Spinner, StatCard, fmtBytes, fmtDate, fmtNumber } from './components';

const COUNTRY_NAMES: Record<string, string> = {
  CN: '🇨🇳 China', US: '🇺🇸 United States', HK: '🇭🇰 Hong Kong', TW: '🇹🇼 Taiwan',
  JP: '🇯🇵 Japan', KR: '🇰🇷 South Korea', SG: '🇸🇬 Singapore', GB: '🇬🇧 United Kingdom',
  DE: '🇩🇪 Germany', FR: '🇫🇷 France', CA: '🇨🇦 Canada', AU: '🇦🇺 Australia',
  IN: '🇮🇳 India', RU: '🇷🇺 Russia', BR: '🇧🇷 Brazil', NL: '🇳🇱 Netherlands',
  IT: '🇮🇹 Italy', ES: '🇪🇸 Spain',
};

const CLIENT_NAMES: Record<string, string> = {
  web: 'Web', mac: 'macOS', android: 'Android', ios: 'iOS', windows: 'Windows',
  chrome: 'Chrome Extension', bot: 'Bot / Crawler', other: 'Other', unknown: 'Unknown',
};

const DETAIL_LIMIT = 30;
const browserTimezone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'Asia/Tokyo';

type DetailTab = 'pages' | 'wallpapers' | 'requests';
type DetailData =
  | AnalyticsDetailPage<AnalyticsPageViewDay>
  | AnalyticsDetailPage<AnalyticsWallpaperViewDay>
  | AnalyticsDetailPage<AnalyticsAPIRequestDay>;

function countryLabel(code: string): string {
  return COUNTRY_NAMES[code.toUpperCase()] || code || '—';
}

function clientLabel(value: string): string {
  return CLIENT_NAMES[value.toLowerCase()] || value || '—';
}

function exactNumber(value: number): string {
  return value.toLocaleString('zh-CN');
}

function dayLabel(value: string): string {
  return value ? value.slice(0, 10) : '—';
}

function percent(numerator: number, denominator: number): string {
  if (denominator <= 0) return '0.00%';
  return `${((numerator / denominator) * 100).toFixed(2)}%`;
}

function pageLabel(path: string): string {
  if (path === '/') return '首页';
  if (path === '/discover') return '发现';
  if (path === '/weekly') return '每周精选';
  if (path === '/collections') return '合集';
  if (path === '/upload') return '上传';
  if (path === '/download/mac') return 'Mac 下载';
  if (path.startsWith('/wallpaper/')) return '壁纸详情';
  if (path.startsWith('/collection/')) return '合集详情';
  if (path.startsWith('/user/')) return '用户主页';
  if (path.startsWith('/device/')) return '设备页面';
  if (path.startsWith('/admin')) return '管理后台';
  return '页面';
}

function deltaText(current: number, previous: number): { text: string; up: boolean } | null {
  if (previous <= 0) return current > 0 ? { text: '— · 新增', up: true } : null;
  const pct = ((current - previous) / previous) * 100;
  return { text: `${pct >= 0 ? '+' : ''}${pct.toFixed(0)}% · 较上期`, up: pct >= 0 };
}

function TimeseriesChart({
  data,
  series,
}: {
  data: AnalyticsDay[];
  series: Array<{ key: keyof AnalyticsDay; label: string; color: string }>;
}) {
  if (data.length === 0) return <div className="text-xs text-slate-400 px-5 py-6">暂无数据</div>;
  const max = Math.max(1, ...data.map((day) => Math.max(...series.map((item) => Number(day[item.key]) || 0))));
  const width = 800;
  const height = 200;
  const padX = 24;
  const padY = 16;
  const innerW = width - padX * 2;
  const innerH = height - padY * 2;
  const xAt = (index: number) => padX + (data.length === 1 ? innerW / 2 : (index / (data.length - 1)) * innerW);
  const yAt = (value: number) => padY + innerH - (value / max) * innerH;

  return (
    <div className="px-5 pb-5">
      <div className="flex items-center justify-between mb-3 text-xs text-slate-500 flex-wrap gap-2">
        <div className="flex items-center gap-4 flex-wrap">
          {series.map((item) => (
            <span key={item.key} className="inline-flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full" style={{ background: item.color }} />{item.label}
            </span>
          ))}
        </div>
        <span>峰值 {exactNumber(max)}</span>
      </div>
      <svg viewBox={`0 0 ${width} ${height}`} className="w-full" preserveAspectRatio="none">
        {[0, 0.25, 0.5, 0.75, 1].map((position) => (
          <line key={position} x1={padX} x2={width - padX} y1={padY + innerH * position} y2={padY + innerH * position}
            stroke="currentColor" className="text-slate-200 dark:text-slate-800" strokeWidth={1} />
        ))}
        {series.map((item) => (
          <polyline key={item.key}
            points={data.map((day, index) => `${xAt(index)},${yAt(Number(day[item.key]) || 0)}`).join(' ')}
            fill="none" stroke={item.color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
        ))}
        <text x={xAt(0)} y={height - 2} fontSize="10" textAnchor="start" className="fill-slate-400">
          {dayLabel(data[0].day).slice(5)}
        </text>
        <text x={xAt(data.length - 1)} y={height - 2} fontSize="10" textAnchor="end" className="fill-slate-400">
          {dayLabel(data[data.length - 1].day).slice(5)}
        </text>
      </svg>
    </div>
  );
}

function RankedTable({
  title,
  rows,
  rightLabel = 'PV',
  format = (value: string) => value,
}: {
  title: string;
  rows: { label: string; count: number; subtitle?: string }[];
  rightLabel?: string;
  format?: (value: string) => string;
}) {
  const total = rows.reduce((sum, row) => sum + row.count, 0);
  return (
    <Card title={title} action={<span className="text-[11px] text-slate-400">{rightLabel}</span>}>
      {rows.length === 0 ? <div className="text-xs text-slate-400 px-5 py-6">暂无数据</div> : rows.map((row) => {
        const ratio = total > 0 ? (row.count / total) * 100 : 0;
        return (
          <div key={row.label} className="px-5 py-2.5 border-b border-slate-100 dark:border-slate-800 last:border-b-0">
            <div className="flex items-baseline justify-between text-sm gap-3">
              <span className="truncate" title={row.label}>{format(row.label)}</span>
              <span className="font-mono">{exactNumber(row.count)}</span>
            </div>
            {row.subtitle && <div className="text-[11px] text-slate-400 truncate">{row.subtitle}</div>}
            <div className="mt-1 h-1 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden">
              <div className="h-full bg-purple-500" style={{ width: `${ratio}%` }} />
            </div>
          </div>
        );
      })}
    </Card>
  );
}

function DailySummary({ data }: { data: AnalyticsDay[] }) {
  return (
    <Card title="每日精确汇总" action={<span className="text-[11px] text-slate-400">按后台时区归档</span>}>
      <div className="overflow-x-auto max-h-[420px]">
        <table className="w-full text-sm">
          <thead className="sticky top-0 bg-slate-50 dark:bg-slate-800 text-xs text-slate-500">
            <tr>
              <th className="text-left px-4 py-2 font-medium">日期</th>
              <th className="text-right px-4 py-2 font-medium">页面 PV</th>
              <th className="text-right px-4 py-2 font-medium">会话</th>
              <th className="text-right px-4 py-2 font-medium">独立 IP</th>
              <th className="text-right px-4 py-2 font-medium">壁纸浏览</th>
              <th className="text-right px-4 py-2 font-medium">API 请求</th>
              <th className="text-right px-4 py-2 font-medium">API 错误</th>
              <th className="text-right px-4 py-2 font-medium">平均 / P95</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 dark:divide-slate-800 font-mono">
            {[...data].reverse().map((day) => (
              <tr key={day.day} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
                <td className="px-4 py-2 font-sans whitespace-nowrap">{dayLabel(day.day)}</td>
                <td className="px-4 py-2 text-right">{exactNumber(day.page_views)}</td>
                <td className="px-4 py-2 text-right">{exactNumber(day.sessions)}</td>
                <td className="px-4 py-2 text-right">{exactNumber(day.unique_ips)}</td>
                <td className="px-4 py-2 text-right">{exactNumber(day.wallpaper_views)}</td>
                <td className="px-4 py-2 text-right">{exactNumber(day.api_requests)}</td>
                <td className="px-4 py-2 text-right text-rose-600">{exactNumber(day.api_errors)}</td>
                <td className="px-4 py-2 text-right whitespace-nowrap">{day.avg_api_latency_ms} / {day.p95_api_latency_ms} ms</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}

function MethodBadge({ method }: { method: string }) {
  const color = method === 'GET' ? 'text-sky-700 bg-sky-50 dark:bg-sky-900/30 dark:text-sky-300'
    : method === 'POST' ? 'text-emerald-700 bg-emerald-50 dark:bg-emerald-900/30 dark:text-emerald-300'
      : method === 'DELETE' ? 'text-rose-700 bg-rose-50 dark:bg-rose-900/30 dark:text-rose-300'
        : 'text-amber-700 bg-amber-50 dark:bg-amber-900/30 dark:text-amber-300';
  return <span className={`inline-flex rounded px-1.5 py-0.5 text-[10px] font-semibold ${color}`}>{method}</span>;
}

function DetailTable({ tab, data, loading }: { tab: DetailTab; data: DetailData | null; loading: boolean }) {
  if (loading && !data) return <Spinner />;
  if (!data || data.items.length === 0) {
    return <div className="px-5 py-10 text-sm text-center text-slate-400">暂无匹配数据</div>;
  }
  if (tab === 'pages') {
    const rows = data.items as AnalyticsPageViewDay[];
    return (
      <div className="overflow-x-auto"><table className="w-full text-sm">
        <thead className="bg-slate-50 dark:bg-slate-800/50 text-xs text-slate-500"><tr>
          <th className="text-left px-4 py-2 font-medium">日期</th><th className="text-left px-4 py-2 font-medium">Web 页面</th>
          <th className="text-left px-4 py-2 font-medium">客户端</th><th className="text-right px-4 py-2 font-medium">PV</th>
          <th className="text-right px-4 py-2 font-medium">会话</th><th className="text-right px-4 py-2 font-medium">用户</th>
          <th className="text-right px-4 py-2 font-medium">独立 IP</th>
        </tr></thead>
        <tbody className="divide-y divide-slate-100 dark:divide-slate-800">{rows.map((row) => (
          <tr key={`${row.day}-${row.path}-${row.client}`} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
            <td className="px-4 py-2 whitespace-nowrap">{dayLabel(row.day)}</td>
            <td className="px-4 py-2 min-w-[260px]"><div className="font-medium">{pageLabel(row.path)}</div><div className="text-xs text-slate-400 font-mono break-all">{row.path}</div></td>
            <td className="px-4 py-2 whitespace-nowrap">{clientLabel(row.client)}</td>
            <td className="px-4 py-2 text-right font-mono">{exactNumber(row.views)}</td><td className="px-4 py-2 text-right font-mono">{exactNumber(row.sessions)}</td>
            <td className="px-4 py-2 text-right font-mono">{exactNumber(row.unique_users)}</td><td className="px-4 py-2 text-right font-mono">{exactNumber(row.unique_ips)}</td>
          </tr>
        ))}</tbody>
      </table></div>
    );
  }
  if (tab === 'wallpapers') {
    const rows = data.items as AnalyticsWallpaperViewDay[];
    return (
      <div className="overflow-x-auto"><table className="w-full text-sm">
        <thead className="bg-slate-50 dark:bg-slate-800/50 text-xs text-slate-500"><tr>
          <th className="text-left px-4 py-2 font-medium">日期</th><th className="text-left px-4 py-2 font-medium">壁纸</th>
          <th className="text-left px-4 py-2 font-medium">客户端</th><th className="text-right px-4 py-2 font-medium">浏览</th>
          <th className="text-right px-4 py-2 font-medium">会话</th><th className="text-right px-4 py-2 font-medium">用户</th>
          <th className="text-right px-4 py-2 font-medium">独立 IP</th>
        </tr></thead>
        <tbody className="divide-y divide-slate-100 dark:divide-slate-800">{rows.map((row) => (
          <tr key={`${row.day}-${row.wallpaper_id}-${row.client}`} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
            <td className="px-4 py-2 whitespace-nowrap">{dayLabel(row.day)}</td>
            <td className="px-4 py-2 min-w-[280px]"><a href={`/wallpaper/${row.slug || row.wallpaper_id}`} target="_blank" rel="noreferrer" className="flex items-center gap-3 hover:text-purple-600">
              {row.thumb_url ? <img src={row.thumb_url} alt="" className="w-12 h-8 rounded object-cover bg-slate-100" /> : <span className="w-12 h-8 rounded bg-slate-100 dark:bg-slate-800" />}
              <span><span className="block font-medium line-clamp-1">{row.title || `#${row.wallpaper_id}`}</span><span className="block text-xs text-slate-400">#{row.wallpaper_id} · {row.slug || '—'}</span></span>
            </a></td>
            <td className="px-4 py-2 whitespace-nowrap">{clientLabel(row.client)}</td>
            <td className="px-4 py-2 text-right font-mono">{exactNumber(row.views)}</td><td className="px-4 py-2 text-right font-mono">{exactNumber(row.sessions)}</td>
            <td className="px-4 py-2 text-right font-mono">{exactNumber(row.unique_users)}</td><td className="px-4 py-2 text-right font-mono">{exactNumber(row.unique_ips)}</td>
          </tr>
        ))}</tbody>
      </table></div>
    );
  }

  const rows = data.items as AnalyticsAPIRequestDay[];
  return (
    <div className="overflow-x-auto"><table className="w-full text-sm">
      <thead className="bg-slate-50 dark:bg-slate-800/50 text-xs text-slate-500"><tr>
        <th className="text-left px-4 py-2 font-medium">日期</th><th className="text-left px-4 py-2 font-medium">接口</th>
        <th className="text-left px-4 py-2 font-medium">客户端</th><th className="text-right px-4 py-2 font-medium">请求</th>
        <th className="text-right px-4 py-2 font-medium">成功 / 4xx / 5xx</th><th className="text-right px-4 py-2 font-medium">平均 / P95 / 最大</th>
        <th className="text-right px-4 py-2 font-medium">会话 / 用户 / IP</th><th className="text-right px-4 py-2 font-medium">入站 / 出站</th>
      </tr></thead>
      <tbody className="divide-y divide-slate-100 dark:divide-slate-800">{rows.map((row) => (
        <tr key={`${row.day}-${row.method}-${row.route}-${row.client}`} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
          <td className="px-4 py-2 whitespace-nowrap">{dayLabel(row.day)}</td>
          <td className="px-4 py-2 min-w-[300px]"><div className="flex items-center gap-2"><MethodBadge method={row.method} /><code className="text-xs break-all">{row.route}</code></div></td>
          <td className="px-4 py-2 whitespace-nowrap">{clientLabel(row.client)}</td>
          <td className="px-4 py-2 text-right font-mono">{exactNumber(row.requests)}</td>
          <td className="px-4 py-2 text-right font-mono whitespace-nowrap"><span className="text-emerald-600">{row.successes}</span> / <span className="text-amber-600">{row.client_errors}</span> / <span className="text-rose-600">{row.server_errors}</span></td>
          <td className="px-4 py-2 text-right font-mono whitespace-nowrap">{row.avg_latency_ms} / {row.p95_latency_ms} / {row.max_latency_ms} ms</td>
          <td className="px-4 py-2 text-right font-mono whitespace-nowrap">{row.sessions} / {row.unique_users} / {row.unique_ips}</td>
          <td className="px-4 py-2 text-right font-mono whitespace-nowrap">{fmtBytes(row.request_bytes)} / {fmtBytes(row.response_bytes)}</td>
        </tr>
      ))}</tbody>
    </table></div>
  );
}

export default function AnalyticsPage() {
  const [days, setDays] = useState(7);
  const [data, setData] = useState<AnalyticsOverview | null>(null);
  const [loginLogs, setLoginLogs] = useState<AdminLoginLogRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<DetailTab>('pages');
  const [detailPage, setDetailPage] = useState(1);
  const [detailClient, setDetailClient] = useState('');
  const [queryInput, setQueryInput] = useState('');
  const [detailQuery, setDetailQuery] = useState('');
  const [detailData, setDetailData] = useState<DetailData | null>(null);
  const [detailLoading, setDetailLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    const timer = window.setTimeout(() => {
      if (!alive) return;
      setLoading(true);
      Promise.all([getAnalytics(days, browserTimezone), listAdminLoginLogs({ page: 1, limit: 20 })])
        .then(([response, logs]) => {
          if (!alive) return;
          const overview = response.data.data;
          setData({
            ...overview,
            daily: overview.daily ?? [], countries: overview.countries ?? [], sources: overview.sources ?? [],
            paths: overview.paths ?? [], clients: overview.clients ?? [], client_downloads: overview.client_downloads ?? [],
          });
          setLoginLogs(logs.data.data.items ?? []);
        })
        .catch(() => { if (alive) toast.error('加载流量数据失败'); })
        .finally(() => { if (alive) setLoading(false); });
    }, 0);
    return () => { alive = false; window.clearTimeout(timer); };
  }, [days]);

  useEffect(() => {
    let alive = true;
    const timer = window.setTimeout(() => {
      if (!alive) return;
      setDetailLoading(true);
      const params = { days, timezone: browserTimezone, page: detailPage, limit: DETAIL_LIMIT, client: detailClient || undefined, query: detailQuery || undefined };
      const request = tab === 'pages' ? getAnalyticsPages(params) : tab === 'wallpapers' ? getAnalyticsWallpapers(params) : getAnalyticsRequests(params);
      request.then((response) => { if (alive) setDetailData(response.data.data as DetailData); })
        .catch(() => { if (alive) { setDetailData(null); toast.error('加载明细失败'); } })
        .finally(() => { if (alive) setDetailLoading(false); });
    }, 0);
    return () => { alive = false; window.clearTimeout(timer); };
  }, [days, tab, detailPage, detailClient, detailQuery]);

  const selectDays = (value: number) => { setDays(value); setDetailPage(1); };
  const selectTab = (value: DetailTab) => { setTab(value); setDetailPage(1); setDetailData(null); };
  const submitSearch = (event: FormEvent) => { event.preventDefault(); setDetailPage(1); setDetailQuery(queryInput.trim()); };
  const totals = data?.totals;
  const previous = data?.previous;
  const pvDelta = totals && previous ? deltaText(totals.page_views, previous.page_views) : null;
  const sessionDelta = totals && previous ? deltaText(totals.sessions, previous.sessions) : null;
  const wallpaperDelta = totals && previous ? deltaText(totals.wallpaper_views, previous.wallpaper_views) : null;
  const apiErrorRate = totals ? percent(totals.api_errors, totals.api_requests) : '0.00%';
  const clientDownloadTotal = data?.client_downloads.reduce((sum, item) => sum + item.count, 0) ?? 0;

  return (
    <div className="px-6 py-6 max-w-[1600px] mx-auto">
      <PageHeader title="流量分析" subtitle={`页面、壁纸与 API 的日粒度统计 · 时区 ${data?.timezone || browserTimezone} · Bot 仅从访客指标中过滤`} action={
        <div className="inline-flex rounded-lg border border-slate-200 dark:border-slate-800 overflow-hidden text-sm">
          {[7, 14, 30, 90].map((value) => <button key={value} onClick={() => selectDays(value)} className={`px-3 py-1.5 ${days === value ? 'bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900' : 'bg-white dark:bg-slate-900 text-slate-600 hover:bg-slate-50 dark:hover:bg-slate-800'}`}>{value}d</button>)}
        </div>
      } />

      {loading && !data ? <div className="py-20 flex justify-center"><Spinner /></div> : !data ? <div className="text-sm text-slate-500">暂无数据</div> : <>
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-6 gap-4 mb-6">
          <StatCard label="Web 页面浏览" value={fmtNumber(data.totals.page_views)} hint={pvDelta?.text} tone={pvDelta?.up ? 'good' : 'bad'} />
          <StatCard label="独立会话" value={fmtNumber(data.totals.sessions)} hint={sessionDelta?.text} tone={sessionDelta?.up ? 'good' : 'bad'} />
          <StatCard label="独立 IP" value={fmtNumber(data.totals.unique_ips)} hint="页面访客去重" tone="info" />
          <StatCard label="壁纸详情浏览" value={fmtNumber(data.totals.wallpaper_views)} hint={wallpaperDelta?.text} tone={wallpaperDelta?.up ? 'good' : 'bad'} />
          <StatCard label="API 请求" value={fmtNumber(data.totals.api_requests)} hint={`平均 ${data.totals.avg_api_latency_ms} ms · P95 ${data.totals.p95_api_latency_ms} ms`} tone="info" />
          <StatCard label="API 错误" value={fmtNumber(data.totals.api_errors)} hint={`${apiErrorRate} · HTTP 4xx/5xx`} tone={data.totals.api_errors > 0 ? 'warn' : 'good'} />
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-2 gap-4 mb-6">
          <Card title="访客与内容趋势"><TimeseriesChart data={data.daily} series={[
            { key: 'page_views', label: '页面 PV', color: '#a855f7' }, { key: 'sessions', label: '会话', color: '#0ea5e9' },
            { key: 'unique_ips', label: '独立 IP', color: '#10b981' }, { key: 'wallpaper_views', label: '壁纸浏览', color: '#f97316' },
          ]} /></Card>
          <Card title="API 健康趋势"><TimeseriesChart data={data.daily} series={[
            { key: 'api_requests', label: '请求', color: '#2563eb' }, { key: 'api_errors', label: '4xx/5xx', color: '#e11d48' },
          ]} /></Card>
        </div>
        <div className="mb-6"><DailySummary data={data.daily} /></div>

        <Card title="日明细" action={<span className="text-[11px] text-slate-400">每个日期 × 页面/壁纸/接口 × 客户端</span>}>
          <div className="px-4 py-3 border-b border-slate-200 dark:border-slate-800 flex flex-wrap gap-3 items-center justify-between">
            <div className="inline-flex rounded-lg bg-slate-100 dark:bg-slate-800 p-1 text-sm">
              {([['pages', 'Web 页面'], ['wallpapers', '壁纸浏览'], ['requests', 'API 接口']] as const).map(([value, label]) => (
                <button key={value} onClick={() => selectTab(value)} className={`px-3 py-1.5 rounded-md ${tab === value ? 'bg-white dark:bg-slate-700 shadow-sm font-medium' : 'text-slate-500'}`}>{label}</button>
              ))}
            </div>
            <form onSubmit={submitSearch} className="flex items-center gap-2">
              <select value={detailClient} onChange={(event) => { setDetailClient(event.target.value); setDetailPage(1); }} className="rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2.5 py-1.5 text-sm">
                <option value="">全部客户端</option>{Object.entries(CLIENT_NAMES).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
              <input value={queryInput} onChange={(event) => setQueryInput(event.target.value)} placeholder={tab === 'pages' ? '搜索页面路径' : tab === 'wallpapers' ? '标题 / slug / ID' : '接口路由 / 方法'} className="w-52 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-3 py-1.5 text-sm" />
              <button className="rounded-lg bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900 px-3 py-1.5 text-sm">查询</button>
            </form>
          </div>
          <div className={detailLoading ? 'opacity-60 transition-opacity' : ''}><DetailTable tab={tab} data={detailData} loading={detailLoading} /></div>
          {detailData && <Pagination page={detailData.page} limit={detailData.limit} total={detailData.total} onChange={setDetailPage} />}
          {tab === 'requests' && <div className="px-5 py-3 text-xs text-slate-400 border-t border-slate-100 dark:border-slate-800">API 请求明细从本功能部署后开始累计；此前的容器访问日志不会自动回填，原始请求事件保留 180 天。</div>}
        </Card>

        <div className="grid grid-cols-1 lg:grid-cols-2 xl:grid-cols-4 gap-4 mt-6">
          <RankedTable title="来源渠道" rows={data.sources.map((source) => ({ label: source.source, count: source.count, subtitle: source.hosts?.slice(0, 3).join(' · ') }))} />
          <RankedTable title="国家 / 地区" rows={data.countries.map((country) => ({ label: country.label, count: country.count }))} format={countryLabel} />
          <RankedTable title="客户端行为事件" rows={data.clients.map((client) => ({ label: client.label, count: client.count }))} rightLabel="事件" format={clientLabel} />
          <RankedTable title="官网下载" rows={data.client_downloads.map((client) => ({ label: client.label, count: client.count }))} rightLabel={`共 ${exactNumber(clientDownloadTotal)}`} format={clientLabel} />
        </div>

        <div className="mt-6"><Card title="最近登录" action={<span className="text-[11px] text-slate-400">最近 20 条</span>}>
          {loginLogs.length === 0 ? <div className="text-xs text-slate-400 px-5 py-6">暂无登录记录</div> : <div className="overflow-x-auto"><table className="w-full text-sm">
            <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs"><tr><th className="text-left px-5 py-2 font-medium">用户</th><th className="text-left px-5 py-2 font-medium">客户端</th><th className="text-left px-5 py-2 font-medium">IP / 地区</th><th className="text-left px-5 py-2 font-medium">时间</th></tr></thead>
            <tbody className="divide-y divide-slate-100 dark:divide-slate-800">{loginLogs.map((log) => <tr key={log.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30"><td className="px-5 py-2"><div className="font-medium">{log.nickname || log.username || `#${log.user_id}`}</div><div className="text-xs text-slate-400">@{log.username || '?'} · {log.email || '-'}</div></td><td className="px-5 py-2">{clientLabel(log.client)}</td><td className="px-5 py-2 text-xs text-slate-500">{log.ip || '—'}{log.country ? ` · ${countryLabel(log.country)}` : ''}</td><td className="px-5 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(log.created_at)}</td></tr>)}</tbody>
          </table></div>}
        </Card></div>
      </>}
    </div>
  );
}
