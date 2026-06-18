import { useCallback, useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { AiOutlineApi, AiOutlineCheckCircle, AiOutlineCopy, AiOutlineLink, AiOutlinePushpin, AiOutlineReload } from 'react-icons/ai';
import * as admin from '../../api/admin';

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white/80 p-4 dark:border-slate-800 dark:bg-slate-900/80">
      <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">{label}</div>
      <div className="mt-2 break-all font-mono text-sm text-slate-700 dark:text-slate-200">{value || '-'}</div>
    </div>
  );
}

export default function IntegrationsPage() {
  const [status, setStatus] = useState<admin.PinterestStatus | null>(null);
  const [wallpaperId, setWallpaperId] = useState('');
  const [force, setForce] = useState(false);
  const [loading, setLoading] = useState(true);
  const [connecting, setConnecting] = useState(false);
  const [posting, setPosting] = useState(false);
  const [lastPin, setLastPin] = useState<admin.PinterestPinResult | null>(null);

  const loadStatus = useCallback(() => {
    setLoading(true);
    admin.getPinterestStatus()
      .then((res) => setStatus(res.data.data))
      .catch(() => toast.error('读取 Pinterest 状态失败'))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    loadStatus();
  }, [loadStatus]);

  const statusLabel = useMemo(() => {
    if (!status) return '检查中';
    if (!status.configured) return '未配置';
    if (!status.connected) return '未授权';
    return '已连接';
  }, [status]);

  const handleConnect = async () => {
    setConnecting(true);
    try {
      const res = await admin.getPinterestAuthURL();
      const authURL = res.data.data.auth_url;
      if (!authURL) throw new Error('missing auth url');
      window.location.href = authURL;
    } catch {
      toast.error('生成 Pinterest 授权链接失败');
      setConnecting(false);
    }
  };

  const handleCopyRedirect = async () => {
    if (!status?.redirect_url) return;
    await navigator.clipboard.writeText(status.redirect_url);
    toast.success('已复制回调地址');
  };

  const handleTestPin = async () => {
    setPosting(true);
    setLastPin(null);
    try {
      const id = Number(wallpaperId.trim());
      const res = await admin.testPinterestPin({
        wallpaper_id: Number.isFinite(id) && id > 0 ? id : undefined,
        force,
      });
      setLastPin(res.data.data);
      toast.success(res.data.data.already_posted ? '这张壁纸之前已经发过 Pin' : '测试 Pin 发布成功');
    } catch (err) {
      const message = err instanceof Error ? err.message : '测试 Pin 发布失败';
      toast.error(message);
    } finally {
      setPosting(false);
    }
  };

  return (
    <div className="min-h-screen px-8 py-8">
      <div className="mx-auto max-w-6xl space-y-6">
        <header className="flex flex-col gap-4 border-b border-slate-200 pb-6 dark:border-slate-800 md:flex-row md:items-end md:justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Marketing</div>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">推广集成</h1>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500 dark:text-slate-400">
              连接官方 Pinterest 账号，按壁纸分类创建 Board，并把精选壁纸发布为 Pin。
            </p>
          </div>
          <button
            type="button"
            onClick={loadStatus}
            disabled={loading}
            className="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            <AiOutlineReload className={loading ? 'animate-spin' : ''} />
            刷新状态
          </button>
        </header>

        <section className="grid gap-4 lg:grid-cols-[1.1fr_0.9fr]">
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="flex items-center gap-3">
                  <div className="grid h-11 w-11 place-items-center rounded-2xl bg-red-50 text-xl text-red-600 dark:bg-red-500/10 dark:text-red-300">
                    <AiOutlinePushpin />
                  </div>
                  <div>
                    <h2 className="text-xl font-semibold text-slate-950 dark:text-white">Pinterest</h2>
                    <p className="text-sm text-slate-500 dark:text-slate-400">Standard access 审核演示入口</p>
                  </div>
                </div>
              </div>
              <span className={`rounded-full px-3 py-1 text-xs font-semibold ${
                status?.connected
                  ? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300'
                  : status?.configured
                    ? 'bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-300'
                    : 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400'
              }`}>
                {statusLabel}
              </span>
            </div>

            <div className="mt-6 grid gap-3 md:grid-cols-2">
              <Field label="账号" value={status?.account_name || status?.account_id || '未授权'} />
              <Field label="Token 过期时间" value={status?.expires_at ? new Date(status.expires_at).toLocaleString() : '未授权'} />
            </div>

            <div className="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-950/50">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">Callback URL</div>
                  <div className="mt-2 break-all font-mono text-sm text-slate-700 dark:text-slate-200">
                    {status?.redirect_url || 'https://wallpaperexchange.com/api/v1/admin/integrations/pinterest/callback'}
                  </div>
                </div>
                <button
                  type="button"
                  onClick={handleCopyRedirect}
                  className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-600 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
                  aria-label="复制回调地址"
                >
                  <AiOutlineCopy />
                </button>
              </div>
            </div>

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={handleConnect}
                disabled={!status?.configured || connecting}
                className="inline-flex items-center justify-center gap-2 rounded-full bg-slate-950 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
              >
                <AiOutlineLink />
                {status?.connected ? '重新授权 Pinterest' : '连接 Pinterest'}
              </button>
              {status?.connected && (
                <span className="inline-flex items-center gap-2 rounded-full bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300">
                  <AiOutlineCheckCircle />
                  可以发布测试 Pin
                </span>
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="flex items-center gap-3">
              <div className="grid h-11 w-11 place-items-center rounded-2xl bg-orange-50 text-xl text-orange-600 dark:bg-orange-500/10 dark:text-orange-300">
                <AiOutlineApi />
              </div>
              <div>
                <h2 className="text-xl font-semibold text-slate-950 dark:text-white">测试发布</h2>
                <p className="text-sm text-slate-500 dark:text-slate-400">不填 ID 时默认发布最新公开壁纸。</p>
              </div>
            </div>

            <label className="mt-6 block text-sm font-medium text-slate-700 dark:text-slate-300">
              壁纸 ID
              <input
                value={wallpaperId}
                onChange={(e) => setWallpaperId(e.target.value)}
                inputMode="numeric"
                placeholder="例如 123，留空则使用最新壁纸"
                className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-orange-400 focus:ring-4 focus:ring-orange-100 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:focus:ring-orange-500/10"
              />
            </label>

            <label className="mt-4 flex cursor-pointer items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-950/50 dark:text-slate-300">
              <input
                type="checkbox"
                checked={force}
                onChange={(e) => setForce(e.target.checked)}
                className="h-4 w-4 rounded border-slate-300 text-orange-500 focus:ring-orange-400"
              />
              已经发过的壁纸也重新发布一个 Pin
            </label>

            <button
              type="button"
              onClick={handleTestPin}
              disabled={!status?.connected || posting}
              className="mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-orange-500 px-5 py-3 text-sm font-semibold text-white shadow-lg shadow-orange-500/20 transition hover:bg-orange-400 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
            >
              <AiOutlinePushpin />
              {posting ? '发布中...' : '发布测试 Pin'}
            </button>

            {lastPin && (
              <div className="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800 dark:border-emerald-500/20 dark:bg-emerald-500/10 dark:text-emerald-200">
                <div className="font-semibold">{lastPin.already_posted ? '已存在发布记录' : '发布成功'}</div>
                <div className="mt-1">Board：{lastPin.board_name || lastPin.board_id}</div>
                {lastPin.pin_url && (
                  <a href={lastPin.pin_url} target="_blank" rel="noreferrer" className="mt-2 inline-block font-semibold underline">
                    打开 Pinterest Pin
                  </a>
                )}
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}
