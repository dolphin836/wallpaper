import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { getAnalytics, type AnalyticsOverview, type AnalyticsDay } from '../../api/admin';
import { Card, PageHeader, Spinner, StatCard, fmtNumber } from './components';

// Common country code → friendly label. Falls back to the raw code so
// rare countries still show *something* readable. Add codes opportunistically
// as the dashboard surfaces them.
const COUNTRY_NAMES: Record<string, string> = {
  CN: '🇨🇳 China',
  US: '🇺🇸 United States',
  HK: '🇭🇰 Hong Kong',
  TW: '🇹🇼 Taiwan',
  JP: '🇯🇵 Japan',
  KR: '🇰🇷 South Korea',
  SG: '🇸🇬 Singapore',
  GB: '🇬🇧 United Kingdom',
  DE: '🇩🇪 Germany',
  FR: '🇫🇷 France',
  CA: '🇨🇦 Canada',
  AU: '🇦🇺 Australia',
  IN: '🇮🇳 India',
  RU: '🇷🇺 Russia',
  BR: '🇧🇷 Brazil',
  NL: '🇳🇱 Netherlands',
  IT: '🇮🇹 Italy',
  ES: '🇪🇸 Spain',
};

function countryLabel(code: string): string {
  return COUNTRY_NAMES[code.toUpperCase()] || code || '—';
}

const CLIENT_NAMES: Record<string, string> = {
  web: 'Web',
  mac: 'macOS',
  android: 'Android',
  ios: 'iOS',
  windows: 'Windows',
  unknown: 'Unknown',
};

function clientLabel(value: string): string {
  return CLIENT_NAMES[value.toLowerCase()] || value || '—';
}

function TimeseriesChart({ data }: { data: AnalyticsDay[] }) {
  if (!data || data.length === 0) {
    return <div className="text-xs text-slate-400 px-5 py-6">暂无数据</div>;
  }
  // Three overlaid lines: page_views, sessions, unique_ips. Scale all to
  // the global max so the relative shape is comparable.
  const max = Math.max(
    1,
    ...data.map((d) => Math.max(d.page_views, d.sessions, d.unique_ips))
  );
  const w = 800;
  const h = 200;
  const padX = 24;
  const padY = 16;
  const innerW = w - padX * 2;
  const innerH = h - padY * 2;
  const xAt = (i: number) =>
    padX + (data.length === 1 ? innerW / 2 : (i / (data.length - 1)) * innerW);
  const yAt = (v: number) => padY + innerH - (v / max) * innerH;

  const series: Array<{ key: keyof AnalyticsDay; label: string; color: string }> = [
    { key: 'page_views', label: '页面浏览', color: '#a855f7' },
    { key: 'sessions',   label: '会话',     color: '#0ea5e9' },
    { key: 'unique_ips', label: '独立 IP',  color: '#10b981' },
  ];

  return (
    <div className="px-5 pb-5">
      <div className="flex items-center justify-between mb-3 text-xs text-slate-500 flex-wrap gap-y-1">
        <div className="flex items-center gap-4">
          {series.map((s) => (
            <span key={s.key} className="inline-flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full" style={{ background: s.color }} />
              {s.label}
            </span>
          ))}
        </div>
        <span>最近 {data.length} 天 · 峰值 {max}</span>
      </div>
      <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="none">
        {/* horizontal grid */}
        {[0, 0.25, 0.5, 0.75, 1].map((p) => (
          <line
            key={p}
            x1={padX} x2={w - padX}
            y1={padY + innerH * p} y2={padY + innerH * p}
            stroke="currentColor" className="text-slate-200 dark:text-slate-800"
            strokeWidth={1}
          />
        ))}
        {series.map((s) => {
          const pts = data.map((d, i) => `${xAt(i)},${yAt(Number(d[s.key]) || 0)}`).join(' ');
          return (
            <polyline
              key={s.key}
              points={pts}
              fill="none"
              stroke={s.color}
              strokeWidth={2}
              strokeLinecap="round"
              strokeLinejoin="round"
            />
          );
        })}
        {/* X-axis day labels — only first / last / midpoint to avoid clutter */}
        {data.length > 0 && (
          <>
            <text x={xAt(0)} y={h - 2} fontSize="10" textAnchor="start" className="fill-slate-400">
              {data[0].day.slice(5)}
            </text>
            <text x={xAt(data.length - 1)} y={h - 2} fontSize="10" textAnchor="end" className="fill-slate-400">
              {data[data.length - 1].day.slice(5)}
            </text>
          </>
        )}
      </svg>
    </div>
  );
}

function deltaText(current: number, previous: number): { text: string; up: boolean } | null {
  if (previous <= 0) {
    return current > 0 ? { text: '— · 新增', up: true } : null;
  }
  const pct = ((current - previous) / previous) * 100;
  const sign = pct >= 0 ? '+' : '';
  return { text: `${sign}${pct.toFixed(0)}% · 较上期`, up: pct >= 0 };
}

function RankedTable({
  title,
  rows,
  rightLabel = 'PV',
  fmt = (s) => s,
}: {
  title: string;
  rows: { label: string; count: number; subtitle?: string }[];
  rightLabel?: string;
  fmt?: (s: string) => string;
}) {
  const total = rows.reduce((a, b) => a + b.count, 0);
  return (
    <Card
      title={title}
      action={<span className="text-[11px] text-slate-400">{rightLabel}</span>}
    >
      {rows.length === 0 ? (
        <div className="text-xs text-slate-400 px-5 py-6">暂无数据</div>
      ) : (
        <div>
          {rows.map((r) => {
            const pct = total > 0 ? (r.count / total) * 100 : 0;
            return (
              <div
                key={r.label}
                className="px-5 py-2.5 border-b border-slate-100 dark:border-slate-800 last:border-b-0"
              >
                <div className="flex items-baseline justify-between text-sm">
                  <span className="truncate" title={r.label}>{fmt(r.label)}</span>
                  <span className="font-mono ml-3">{fmtNumber(r.count)}</span>
                </div>
                {r.subtitle && (
                  <div className="text-[11px] text-slate-400 truncate">{r.subtitle}</div>
                )}
                <div className="mt-1 h-1 rounded-full bg-slate-100 dark:bg-slate-800 overflow-hidden">
                  <div className="h-full bg-purple-500" style={{ width: `${pct}%` }} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Card>
  );
}

export default function AnalyticsPage() {
  const [days, setDays] = useState(7);
  const [data, setData] = useState<AnalyticsOverview | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    getAnalytics(days)
      .then((r) => {
        if (!alive) return;
        // Defensive coalesce — backend may return null for any of these
        // slices when a query happens to return zero rows (Go nil slice
        // → JSON null). Normalising once here means the render path can
        // assume arrays everywhere.
        const d = r.data.data;
        setData({
          ...d,
          daily:     d.daily     ?? [],
          countries: d.countries ?? [],
          sources:   d.sources   ?? [],
          paths:     d.paths     ?? [],
          clients:   d.clients   ?? [],
          client_downloads: d.client_downloads ?? [],
        });
      })
      .catch(() => { toast.error('加载流量数据失败'); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [days]);

  const pvDelta   = data && deltaText(data.totals.page_views, data.previous.page_views);
  const sessDelta = data && deltaText(data.totals.sessions, data.previous.sessions);
  const ipDelta   = data && deltaText(data.totals.unique_ips, data.previous.unique_ips);
  const clientDownloadTotal = data?.client_downloads.reduce((sum, item) => sum + item.count, 0) ?? 0;

  return (
    <div className="px-6 py-6 max-w-[1400px] mx-auto">
      <PageHeader
        title="流量"
        subtitle="过去 7/30 天的页面浏览、独立访客、官网下载与客户端分布。bot UA 已过滤。"
        action={
          <div className="inline-flex rounded-lg border border-slate-200 dark:border-slate-800 overflow-hidden text-sm">
            {[7, 14, 30].map((d) => (
              <button
                key={d}
                onClick={() => setDays(d)}
                className={`px-3 py-1.5 ${days === d
                  ? 'bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900'
                  : 'bg-white dark:bg-slate-900 text-slate-600 hover:bg-slate-50 dark:hover:bg-slate-800'}`}
              >
                {d}d
              </button>
            ))}
          </div>
        }
      />

      {loading && !data ? (
        <div className="py-20 flex justify-center"><Spinner /></div>
      ) : !data ? (
        <div className="text-sm text-slate-500">No data.</div>
      ) : (
        <>
          {/* KPI tiles */}
          <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4 mb-6">
            <StatCard
              label="页面浏览"
              value={fmtNumber(data.totals.page_views)}
              hint={pvDelta?.text}
              tone={pvDelta?.up ? 'good' : 'bad'}
            />
            <StatCard
              label="独立会话"
              value={fmtNumber(data.totals.sessions)}
              hint={sessDelta?.text}
              tone={sessDelta?.up ? 'good' : 'bad'}
            />
            <StatCard
              label="独立 IP"
              value={fmtNumber(data.totals.unique_ips)}
              hint={ipDelta?.text}
              tone={ipDelta?.up ? 'good' : 'bad'}
            />
            <StatCard
              label="客户端下载"
              value={fmtNumber(clientDownloadTotal)}
              hint="官网 Mac / Android 安装包"
              tone="info"
            />
          </div>

          {/* Timeseries */}
          <div className="mb-6">
            <Card title="每日趋势">
              <TimeseriesChart data={data.daily} />
            </Card>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 mb-6">
            <RankedTable
              title="官网下载"
              rows={data.client_downloads.map((c) => ({ label: c.label, count: c.count }))}
              rightLabel="下载"
              fmt={clientLabel}
            />
            <RankedTable
              title="客户端分布"
              rows={data.clients.map((c) => ({ label: c.label, count: c.count }))}
              rightLabel="事件"
              fmt={clientLabel}
            />
          </div>

          {/* Top breakdowns */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
            <RankedTable
              title="来源渠道"
              rows={data.sources.map((s) => ({
                label: s.source,
                count: s.count,
                subtitle: s.hosts && s.hosts.length > 0 ? s.hosts.slice(0, 3).join(' · ') : undefined,
              }))}
            />
            <RankedTable
              title="国家 / 地区"
              rows={data.countries.map((c) => ({ label: c.label, count: c.count }))}
              fmt={countryLabel}
            />
            <RankedTable
              title="热门页面"
              rows={data.paths.map((p) => ({ label: p.label, count: p.count }))}
            />
          </div>
        </>
      )}
    </div>
  );
}
