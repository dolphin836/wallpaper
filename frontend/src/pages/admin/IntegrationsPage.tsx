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

function StatusPill({ configured, connected }: { configured?: boolean; connected?: boolean }) {
  const label = !configured ? '未配置' : connected ? '已连接' : '未授权';
  return (
    <span className={`rounded-full px-3 py-1 text-xs font-semibold ${
      connected
        ? 'bg-emerald-50 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300'
        : configured
          ? 'bg-amber-50 text-amber-700 dark:bg-amber-500/10 dark:text-amber-300'
          : 'bg-slate-100 text-slate-500 dark:bg-slate-800 dark:text-slate-400'
    }`}>
      {label}
    </span>
  );
}

function errorMessage(err: unknown, fallback: string) {
  const apiError = err as {
    response?: { data?: { data?: { error?: string }; message?: string } };
    message?: string;
  };
  return (
    apiError.response?.data?.data?.error ||
    apiError.response?.data?.message ||
    apiError.message ||
    fallback
  );
}

export default function IntegrationsPage() {
  const [pinterestStatus, setPinterestStatus] = useState<admin.PinterestStatus | null>(null);
  const [redditStatus, setRedditStatus] = useState<admin.RedditStatus | null>(null);
  const [redditPreview, setRedditPreview] = useState<admin.RedditWeeklyPreview | null>(null);
  const [wallpaperId, setWallpaperId] = useState('');
  const [forcePin, setForcePin] = useState(false);
  const [loading, setLoading] = useState(true);
  const [connecting, setConnecting] = useState('');
  const [postingPin, setPostingPin] = useState(false);
  const [postingReddit, setPostingReddit] = useState(false);
  const [previewLoading, setPreviewLoading] = useState(false);
  const [lastPin, setLastPin] = useState<admin.PinterestPinResult | null>(null);
  const [lastRedditPost, setLastRedditPost] = useState<admin.RedditWeeklyPostResult | null>(null);
  const [subreddit, setSubreddit] = useState('');
  const [redditTitle, setRedditTitle] = useState('');
  const [redditText, setRedditText] = useState('');
  const [forceReddit, setForceReddit] = useState(false);

  const loadPinterestStatus = useCallback(async () => {
    const res = await admin.getPinterestStatus();
    setPinterestStatus(res.data.data);
  }, []);

  const loadRedditStatus = useCallback(async () => {
    const res = await admin.getRedditStatus();
    const data = res.data.data;
    setRedditStatus(data);
    setSubreddit((current) => current || data.default_subreddit || '');
    return data;
  }, []);

  const loadRedditPreview = useCallback(async (nextSubreddit?: string) => {
    setPreviewLoading(true);
    try {
      const res = await admin.getRedditWeeklyPreview({
        subreddit: nextSubreddit || redditStatus?.default_subreddit,
      });
      const data = res.data.data;
      setRedditPreview(data);
      setSubreddit(data.subreddit || nextSubreddit || '');
      setRedditTitle(data.title);
      setRedditText(data.text);
      setLastRedditPost(data.existing_post || null);
    } catch (err) {
      toast.error(errorMessage(err, '生成 Reddit 草稿失败'));
    } finally {
      setPreviewLoading(false);
    }
  }, [redditStatus?.default_subreddit]);

  const loadAll = useCallback(async () => {
    setLoading(true);
    try {
      const [, reddit] = await Promise.all([
        loadPinterestStatus(),
        loadRedditStatus(),
      ]);
      await loadRedditPreview(reddit.default_subreddit);
    } catch {
      toast.error('读取推广集成状态失败');
    } finally {
      setLoading(false);
    }
  }, [loadPinterestStatus, loadRedditPreview, loadRedditStatus]);

  useEffect(() => {
    loadAll();
  }, [loadAll]);

  const redditIssueLabel = useMemo(() => {
    if (!redditPreview) return '本周合集';
    return `${redditPreview.year}-W${String(redditPreview.week).padStart(2, '0')}`;
  }, [redditPreview]);

  const handleConnectPinterest = async () => {
    setConnecting('pinterest');
    try {
      const res = await admin.getPinterestAuthURL();
      const authURL = res.data.data.auth_url;
      if (!authURL) throw new Error('missing auth url');
      window.location.href = authURL;
    } catch {
      toast.error('生成 Pinterest 授权链接失败');
      setConnecting('');
    }
  };

  const handleConnectReddit = async () => {
    setConnecting('reddit');
    try {
      const res = await admin.getRedditAuthURL();
      const authURL = res.data.data.auth_url;
      if (!authURL) throw new Error('missing auth url');
      window.location.href = authURL;
    } catch {
      toast.error('生成 Reddit 授权链接失败');
      setConnecting('');
    }
  };

  const handleCopy = async (value?: string) => {
    if (!value) return;
    await navigator.clipboard.writeText(value);
    toast.success('已复制回调地址');
  };

  const handleTestPin = async () => {
    setPostingPin(true);
    setLastPin(null);
    try {
      const id = Number(wallpaperId.trim());
      const res = await admin.testPinterestPin({
        wallpaper_id: Number.isFinite(id) && id > 0 ? id : undefined,
        force: forcePin,
      });
      setLastPin(res.data.data);
      toast.success(res.data.data.already_posted ? '这张壁纸之前已经发过 Pin' : '测试 Pin 发布成功');
    } catch (err) {
      toast.error(errorMessage(err, '测试 Pin 发布失败'));
    } finally {
      setPostingPin(false);
    }
  };

  const handlePublishReddit = async () => {
    if (!redditPreview) return;
    setPostingReddit(true);
    setLastRedditPost(null);
    try {
      const res = await admin.postRedditWeekly({
        year: redditPreview.year,
        week: redditPreview.week,
        subreddit,
        title: redditTitle,
        text: redditText,
        force: forceReddit,
      });
      setLastRedditPost(res.data.data);
      toast.success(res.data.data.already_posted ? '本周已经发过 Reddit 文章' : 'Reddit 文章发布成功');
      await loadRedditPreview(subreddit);
    } catch (err) {
      toast.error(errorMessage(err, 'Reddit 发布失败'));
    } finally {
      setPostingReddit(false);
    }
  };

  return (
    <div className="min-h-screen px-8 py-8">
      <div className="mx-auto max-w-7xl space-y-6">
        <header className="flex flex-col gap-4 border-b border-slate-200 pb-6 dark:border-slate-800 md:flex-row md:items-end md:justify-between">
          <div>
            <div className="text-xs font-semibold uppercase tracking-[0.28em] text-slate-400">Marketing</div>
            <h1 className="mt-2 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">推广集成</h1>
            <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-500 dark:text-slate-400">
              连接官方推广账号，人工确认后发布 Pinterest Pin 或 Reddit 每周合集文章。
            </p>
          </div>
          <button
            type="button"
            onClick={loadAll}
            disabled={loading}
            className="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
          >
            <AiOutlineReload className={loading ? 'animate-spin' : ''} />
            刷新状态
          </button>
        </header>

        <section className="grid gap-4 xl:grid-cols-2">
          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="grid h-11 w-11 place-items-center rounded-2xl bg-red-50 text-xl text-red-600 dark:bg-red-500/10 dark:text-red-300">
                  <AiOutlinePushpin />
                </div>
                <div>
                  <h2 className="text-xl font-semibold text-slate-950 dark:text-white">Pinterest</h2>
                  <p className="text-sm text-slate-500 dark:text-slate-400">按分类发布精选壁纸 Pin。</p>
                </div>
              </div>
              <StatusPill configured={pinterestStatus?.configured} connected={pinterestStatus?.connected} />
            </div>

            <div className="mt-6 grid gap-3 md:grid-cols-2">
              <Field label="账号" value={pinterestStatus?.account_name || pinterestStatus?.account_id || '未授权'} />
              <Field label="Token 过期时间" value={pinterestStatus?.expires_at ? new Date(pinterestStatus.expires_at).toLocaleString() : '未授权'} />
            </div>

            <CallbackBox
              value={pinterestStatus?.redirect_url || 'https://wallpaperexchange.com/api/v1/admin/integrations/pinterest/callback'}
              onCopy={() => handleCopy(pinterestStatus?.redirect_url)}
            />

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={handleConnectPinterest}
                disabled={!pinterestStatus?.configured || connecting === 'pinterest'}
                className="inline-flex items-center justify-center gap-2 rounded-full bg-slate-950 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
              >
                <AiOutlineLink />
                {pinterestStatus?.connected ? '重新授权 Pinterest' : '连接 Pinterest'}
              </button>
              {pinterestStatus?.connected && (
                <span className="inline-flex items-center gap-2 rounded-full bg-emerald-50 px-4 py-2 text-sm font-semibold text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300">
                  <AiOutlineCheckCircle />
                  可以发布测试 Pin
                </span>
              )}
            </div>

            <div className="mt-6 rounded-2xl border border-slate-200 bg-slate-50 p-4 dark:border-slate-800 dark:bg-slate-950/50">
              <div className="flex items-center gap-3">
                <div className="grid h-10 w-10 place-items-center rounded-xl bg-orange-50 text-lg text-orange-600 dark:bg-orange-500/10 dark:text-orange-300">
                  <AiOutlineApi />
                </div>
                <div>
                  <h3 className="font-semibold text-slate-950 dark:text-white">测试发布</h3>
                  <p className="text-sm text-slate-500 dark:text-slate-400">不填 ID 时默认发布最新公开壁纸。</p>
                </div>
              </div>
              <label className="mt-4 block text-sm font-medium text-slate-700 dark:text-slate-300">
                壁纸 ID
                <input
                  value={wallpaperId}
                  onChange={(e) => setWallpaperId(e.target.value)}
                  inputMode="numeric"
                  placeholder="例如 123，留空则使用最新壁纸"
                  className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-orange-400 focus:ring-4 focus:ring-orange-100 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:focus:ring-orange-500/10"
                />
              </label>
              <label className="mt-4 flex cursor-pointer items-center gap-3 text-sm text-slate-600 dark:text-slate-300">
                <input
                  type="checkbox"
                  checked={forcePin}
                  onChange={(e) => setForcePin(e.target.checked)}
                  className="h-4 w-4 rounded border-slate-300 text-orange-500 focus:ring-orange-400"
                />
                已经发过的壁纸也重新发布一个 Pin
              </label>
              <button
                type="button"
                onClick={handleTestPin}
                disabled={!pinterestStatus?.connected || postingPin}
                className="mt-5 inline-flex w-full items-center justify-center gap-2 rounded-full bg-orange-500 px-5 py-3 text-sm font-semibold text-white shadow-lg shadow-orange-500/20 transition hover:bg-orange-400 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
              >
                <AiOutlinePushpin />
                {postingPin ? '发布中...' : '发布测试 Pin'}
              </button>
              {lastPin && (
                <ResultBox title={lastPin.already_posted ? '已存在发布记录' : '发布成功'}>
                  <div>Board：{lastPin.board_name || lastPin.board_id}</div>
                  {lastPin.pin_url && <ExternalLink href={lastPin.pin_url}>打开 Pinterest Pin</ExternalLink>}
                </ResultBox>
              )}
            </div>
          </div>

          <div className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-center gap-3">
                <div className="grid h-11 w-11 place-items-center rounded-2xl bg-orange-50 text-sm font-black text-orange-600 dark:bg-orange-500/10 dark:text-orange-300">
                  r/
                </div>
                <div>
                  <h2 className="text-xl font-semibold text-slate-950 dark:text-white">Reddit</h2>
                  <p className="text-sm text-slate-500 dark:text-slate-400">一周一篇，发布后台人工精选的每周推荐和推荐合集。</p>
                </div>
              </div>
              <StatusPill configured={redditStatus?.configured} connected={redditStatus?.connected} />
            </div>

            <div className="mt-6 grid gap-3 md:grid-cols-2">
              <Field label="账号" value={redditStatus?.account_name || redditStatus?.account_id || '未授权'} />
              <Field label="默认 subreddit" value={`r/${redditStatus?.default_subreddit || 'wallpapers'}`} />
            </div>

            <CallbackBox
              value={redditStatus?.redirect_url || 'https://wallpaperexchange.com/api/v1/admin/integrations/reddit/callback'}
              onCopy={() => handleCopy(redditStatus?.redirect_url)}
            />

            <div className="mt-6 flex flex-wrap gap-3">
              <button
                type="button"
                onClick={handleConnectReddit}
                disabled={!redditStatus?.configured || connecting === 'reddit'}
                className="inline-flex items-center justify-center gap-2 rounded-full bg-slate-950 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:bg-slate-300 dark:bg-white dark:text-slate-950 dark:hover:bg-slate-200"
              >
                <AiOutlineLink />
                {redditStatus?.connected ? '重新授权 Reddit' : '连接 Reddit'}
              </button>
              <button
                type="button"
                onClick={() => loadRedditPreview(subreddit)}
                disabled={previewLoading}
                className="inline-flex items-center justify-center gap-2 rounded-full border border-slate-200 bg-white px-5 py-2.5 text-sm font-semibold text-slate-700 transition hover:bg-slate-50 disabled:opacity-60 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-200 dark:hover:bg-slate-800"
              >
                <AiOutlineReload className={previewLoading ? 'animate-spin' : ''} />
                重新生成草稿
              </button>
            </div>
          </div>
        </section>

        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
            <div>
              <div className="text-xs font-semibold uppercase tracking-[0.24em] text-slate-400">Weekly Reddit Post</div>
              <h2 className="mt-2 text-2xl font-semibold text-slate-950 dark:text-white">{redditIssueLabel} 推广文章</h2>
              <p className="mt-1 text-sm text-slate-500 dark:text-slate-400">
                默认优先使用每周生成的主题合集；如果没有主题合集，会回退到每周推荐壁纸列表。
              </p>
            </div>
            {redditPreview?.already_posted && redditPreview.existing_post?.post_url && (
              <ExternalLink href={redditPreview.existing_post.post_url}>已发布，打开 Reddit</ExternalLink>
            )}
          </div>

          <div className="mt-6 grid gap-6 xl:grid-cols-[0.95fr_1.05fr]">
            <div className="space-y-4">
              <label className="block text-sm font-medium text-slate-700 dark:text-slate-300">
                Subreddit
                <div className="mt-2 flex rounded-xl border border-slate-200 bg-white focus-within:border-orange-400 focus-within:ring-4 focus-within:ring-orange-100 dark:border-slate-700 dark:bg-slate-950 dark:focus-within:ring-orange-500/10">
                  <span className="border-r border-slate-200 px-4 py-3 text-sm font-semibold text-slate-400 dark:border-slate-700">r/</span>
                  <input
                    value={subreddit}
                    onChange={(e) => setSubreddit(e.target.value)}
                    placeholder="wallpapers"
                    className="min-w-0 flex-1 rounded-r-xl bg-transparent px-4 py-3 text-sm text-slate-900 outline-none placeholder:text-slate-400 dark:text-white"
                  />
                </div>
              </label>

              <label className="block text-sm font-medium text-slate-700 dark:text-slate-300">
                标题
                <input
                  value={redditTitle}
                  onChange={(e) => setRedditTitle(e.target.value)}
                  placeholder="Reddit post title"
                  className="mt-2 w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-sm text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-orange-400 focus:ring-4 focus:ring-orange-100 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:focus:ring-orange-500/10"
                />
              </label>

              <label className="block text-sm font-medium text-slate-700 dark:text-slate-300">
                正文 Markdown
                <textarea
                  value={redditText}
                  onChange={(e) => setRedditText(e.target.value)}
                  rows={16}
                  placeholder="Reddit self-post markdown"
                  className="mt-2 w-full resize-y rounded-xl border border-slate-200 bg-white px-4 py-3 font-mono text-sm leading-6 text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-orange-400 focus:ring-4 focus:ring-orange-100 dark:border-slate-700 dark:bg-slate-950 dark:text-white dark:focus:ring-orange-500/10"
                />
              </label>

              <label className="flex cursor-pointer items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-950/50 dark:text-slate-300">
                <input
                  type="checkbox"
                  checked={forceReddit}
                  onChange={(e) => setForceReddit(e.target.checked)}
                  className="h-4 w-4 rounded border-slate-300 text-orange-500 focus:ring-orange-400"
                />
                本周已经发过时仍然重新发布，并用新文章覆盖后台记录
              </label>

              <button
                type="button"
                onClick={handlePublishReddit}
                disabled={!redditStatus?.connected || !redditPreview || postingReddit}
                className="inline-flex w-full items-center justify-center gap-2 rounded-full bg-orange-500 px-5 py-3 text-sm font-semibold text-white shadow-lg shadow-orange-500/20 transition hover:bg-orange-400 disabled:cursor-not-allowed disabled:bg-slate-300 disabled:shadow-none"
              >
                {postingReddit ? '发布中...' : `发布到 r/${subreddit || 'wallpapers'}`}
              </button>

              {lastRedditPost && (
                <ResultBox title={lastRedditPost.already_posted ? '本周已经发过' : 'Reddit 发布成功'}>
                  <div>{lastRedditPost.year}-W{String(lastRedditPost.week).padStart(2, '0')} · r/{lastRedditPost.subreddit}</div>
                  {lastRedditPost.post_url && <ExternalLink href={lastRedditPost.post_url}>打开 Reddit 文章</ExternalLink>}
                </ResultBox>
              )}
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-slate-200 bg-slate-50 p-5 dark:border-slate-800 dark:bg-slate-950/60">
                <div className="flex items-center justify-between gap-4">
                  <div>
                    <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">Source</div>
                    <div className="mt-1 text-lg font-semibold text-slate-950 dark:text-white">
                      {redditPreview?.collection?.title || (redditPreview ? '每周推荐壁纸' : '加载中')}
                    </div>
                  </div>
                  <span className="rounded-full bg-white px-3 py-1 text-xs font-semibold text-slate-500 shadow-sm dark:bg-slate-900 dark:text-slate-300">
                    {redditPreview?.source === 'collection' ? '主题合集' : '每周推荐'}
                  </span>
                </div>
                {redditPreview?.collection?.description && (
                  <p className="mt-3 text-sm leading-6 text-slate-500 dark:text-slate-400">
                    {redditPreview.collection.description}
                  </p>
                )}
              </div>

              <div className="rounded-2xl border border-slate-200 bg-white p-4 dark:border-slate-800 dark:bg-slate-950">
                <div className="mb-3 flex items-center justify-between">
                  <h3 className="font-semibold text-slate-950 dark:text-white">文章里会展示的壁纸</h3>
                  <span className="text-xs font-semibold text-slate-400">{redditPreview?.wallpapers.length || 0} 张</span>
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  {(redditPreview?.wallpapers || []).slice(0, 6).map((w) => (
                    <div key={w.id} className="flex gap-3 rounded-xl border border-slate-200 bg-slate-50 p-2 dark:border-slate-800 dark:bg-slate-900/70">
                      <div className="h-16 w-20 shrink-0 overflow-hidden rounded-lg bg-slate-200 dark:bg-slate-800">
                        {(w.preview_url || w.thumb_url) && (
                          <img src={w.preview_url || w.thumb_url} alt="" className="h-full w-full object-cover" />
                        )}
                      </div>
                      <div className="min-w-0">
                        <div className="truncate text-sm font-semibold text-slate-900 dark:text-white">{w.title || `Wallpaper #${w.id}`}</div>
                        <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">{w.width} x {w.height}</div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="rounded-2xl border border-slate-200 bg-slate-950 p-5 text-slate-100 shadow-sm dark:border-slate-800">
                <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">Markdown Preview</div>
                <h3 className="mt-3 text-xl font-semibold leading-7">{redditTitle || 'Untitled Reddit post'}</h3>
                <pre className="mt-4 max-h-[360px] overflow-auto whitespace-pre-wrap rounded-xl bg-white/5 p-4 text-sm leading-6 text-slate-200">
                  {redditText || '正文还没有生成'}
                </pre>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}

function CallbackBox({ value, onCopy }: { value: string; onCopy: () => void }) {
  return (
    <div className="mt-4 rounded-xl border border-dashed border-slate-200 bg-slate-50 p-4 dark:border-slate-700 dark:bg-slate-950/50">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-xs font-semibold uppercase tracking-[0.2em] text-slate-400">Callback URL</div>
          <div className="mt-2 break-all font-mono text-sm text-slate-700 dark:text-slate-200">{value}</div>
        </div>
        <button
          type="button"
          onClick={onCopy}
          className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-slate-200 bg-white text-slate-600 transition hover:bg-slate-100 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-300 dark:hover:bg-slate-800"
          aria-label="复制回调地址"
        >
          <AiOutlineCopy />
        </button>
      </div>
    </div>
  );
}

function ResultBox({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mt-5 rounded-xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800 dark:border-emerald-500/20 dark:bg-emerald-500/10 dark:text-emerald-200">
      <div className="font-semibold">{title}</div>
      <div className="mt-1 space-y-1">{children}</div>
    </div>
  );
}

function ExternalLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="inline-flex items-center font-semibold text-orange-600 underline-offset-4 hover:underline dark:text-orange-300">
      {children}
    </a>
  );
}
