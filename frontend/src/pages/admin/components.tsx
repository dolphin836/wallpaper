import type { ReactNode } from 'react';

export function PageHeader({ title, subtitle, action }: { title: string; subtitle?: string; action?: ReactNode }) {
  return (
    <div className="flex items-end justify-between px-8 pt-7 pb-5">
      <div>
        <h1 className="text-2xl font-semibold">{title}</h1>
        {subtitle && <p className="text-sm text-slate-500 mt-1">{subtitle}</p>}
      </div>
      {action && <div>{action}</div>}
    </div>
  );
}

export function StatCard({
  label,
  value,
  hint,
  tone = 'default',
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  tone?: 'default' | 'good' | 'warn' | 'bad' | 'info' | 'mute';
}) {
  const tones: Record<string, string> = {
    default: 'border-slate-200 dark:border-slate-800',
    good: 'border-emerald-200 dark:border-emerald-900/40',
    warn: 'border-amber-200 dark:border-amber-900/40',
    bad: 'border-rose-200 dark:border-rose-900/40',
    info: 'border-sky-200 dark:border-sky-900/40',
    mute: 'border-slate-200 dark:border-slate-800 opacity-90',
  };
  return (
    <div className={`bg-white dark:bg-slate-900 rounded-xl border ${tones[tone]} px-5 py-4`}>
      <div className="text-xs text-slate-500 uppercase tracking-wide">{label}</div>
      <div className="text-2xl font-semibold mt-1.5">{value}</div>
      {hint && <div className="text-xs text-slate-400 mt-1">{hint}</div>}
    </div>
  );
}

export function Card({ title, action, children }: { title?: string; action?: ReactNode; children: ReactNode }) {
  return (
    <div className="bg-white dark:bg-slate-900 rounded-xl border border-slate-200 dark:border-slate-800 overflow-hidden">
      {(title || action) && (
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex items-center justify-between">
          {title && <h2 className="text-sm font-semibold">{title}</h2>}
          {action}
        </div>
      )}
      {children}
    </div>
  );
}

export function StatusBadge({ label, tone }: { label: string; tone: 'good' | 'warn' | 'bad' | 'mute' | 'info' }) {
  const colors: Record<string, string> = {
    good: 'bg-emerald-50 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300',
    warn: 'bg-amber-50 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
    bad: 'bg-rose-50 text-rose-700 dark:bg-rose-900/30 dark:text-rose-300',
    mute: 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300',
    info: 'bg-sky-50 text-sky-700 dark:bg-sky-900/30 dark:text-sky-300',
  };
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${colors[tone]}`}>
      {label}
    </span>
  );
}

export function Spinner() {
  return (
    <div className="flex justify-center py-10">
      <div className="w-6 h-6 border-2 border-slate-300 border-t-purple-500 rounded-full animate-spin" />
    </div>
  );
}

export function Empty({ children }: { children: ReactNode }) {
  return <div className="py-12 text-center text-sm text-slate-400">{children}</div>;
}

export function Pagination({
  page,
  limit,
  total,
  onChange,
}: {
  page: number;
  limit: number;
  total: number;
  onChange: (p: number) => void;
}) {
  const totalPages = Math.max(1, Math.ceil(total / limit));
  if (totalPages <= 1) return null;
  return (
    <div className="flex items-center justify-between px-5 py-3 border-t border-slate-200 dark:border-slate-800 text-sm">
      <div className="text-slate-500">
        共 {total} 条 · 第 {page} / {totalPages} 页
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => onChange(Math.max(1, page - 1))}
          disabled={page <= 1}
          className="px-3 py-1 rounded border border-slate-200 dark:border-slate-700 disabled:opacity-40 hover:bg-slate-50 dark:hover:bg-slate-800"
        >
          上一页
        </button>
        <button
          onClick={() => onChange(Math.min(totalPages, page + 1))}
          disabled={page >= totalPages}
          className="px-3 py-1 rounded border border-slate-200 dark:border-slate-700 disabled:opacity-40 hover:bg-slate-50 dark:hover:bg-slate-800"
        >
          下一页
        </button>
      </div>
    </div>
  );
}

export function fmtNumber(n: number | undefined | null): string {
  if (n == null) return '-';
  if (Math.abs(n) >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (Math.abs(n) >= 1_000) return (n / 1_000).toFixed(1) + 'K';
  return String(n);
}

export function fmtBytes(n: number | undefined | null): string {
  if (!n || n <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i += 1;
  }
  return `${v.toFixed(v >= 100 || i === 0 ? 0 : v >= 10 ? 1 : 2)} ${units[i]}`;
}

export function fmtDate(iso: string): string {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return iso;
  return d.toLocaleString('zh-CN', { hour12: false });
}

export const WALLPAPER_STATUS: Record<number, { label: string; tone: 'good' | 'warn' | 'bad' | 'mute' | 'info' }> = {
  0: { label: '处理中', tone: 'warn' },
  1: { label: '已发布', tone: 'good' },
  2: { label: '处理失败', tone: 'bad' },
  3: { label: '已下架', tone: 'mute' },
  4: { label: '重复', tone: 'mute' },
};

export const REPORT_STATUS: Record<number, { label: string; tone: 'good' | 'warn' | 'bad' | 'mute' }> = {
  0: { label: '待处理', tone: 'warn' },
  1: { label: '已处理', tone: 'good' },
  2: { label: '已驳回', tone: 'mute' },
};
