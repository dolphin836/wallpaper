/* eslint-disable react-hooks/set-state-in-effect, react-hooks/exhaustive-deps */
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { open } from '@tauri-apps/plugin-shell';
import { api } from '../lib/api';
import { clearToken } from '../lib/auth';
import { cmd } from '../lib/commands';
import type {
  Category,
  CollectionBrief,
  CollectionItem,
  CoinTransaction,
  User,
  Wallpaper,
  WallpaperDetail,
  WeeklyArchiveEntry,
  WeeklyCurrent,
} from '../lib/types';

type ViewKey = 'home' | 'discover' | 'weekly' | 'collections' | 'downloads' | 'library' | 'upload' | 'settings';
type LibraryTab = 'favorites' | 'likes' | 'collections' | 'coins';
type ToastKind = 'info' | 'success' | 'error';

const APPLIED_KEY = 'wpe.applied.id';
const AUTOPLAY_COLLECTION_KEY = 'wpe.autoplay.collection';
const AUTOPLAY_COLLECTION_TITLE_KEY = 'wpe.autoplay.collection.title';

const navItems: Array<{ key: ViewKey; title: string; hint: string }> = [
  { key: 'home', title: '首页', hint: '推荐' },
  { key: 'discover', title: '发现页', hint: '浏览' },
  { key: 'weekly', title: '每周推荐', hint: '精选' },
  { key: 'collections', title: '合集', hint: '主题' },
  { key: 'downloads', title: '我的下载', hint: '本地' },
  { key: 'library', title: '我的主页', hint: '账号' },
  { key: 'upload', title: '上传', hint: '发布' },
  { key: 'settings', title: '设置', hint: '偏好' },
];

export default function HomeScreen({
  token,
  onRequestSignIn,
  onSignOut,
}: {
  token: string | null;
  onRequestSignIn: () => void;
  onSignOut: () => void;
}) {
  const [view, setView] = useState<ViewKey>('home');
  const [me, setMe] = useState<User | null>(null);
  const [categories, setCategories] = useState<Category[]>([]);
  const [latest, setLatest] = useState<Wallpaper[]>([]);
  const [forYou, setForYou] = useState<Wallpaper[]>([]);
  const [weekly, setWeekly] = useState<WeeklyCurrent | null>(null);
  const [weeklyArchive, setWeeklyArchive] = useState<WeeklyArchiveEntry[]>([]);
  const [publicCollections, setPublicCollections] = useState<CollectionItem[]>([]);
  const [downloads, setDownloads] = useState<Wallpaper[]>([]);
  const [favorites, setFavorites] = useState<Wallpaper[]>([]);
  const [likes, setLikes] = useState<Wallpaper[]>([]);
  const [myCollections, setMyCollections] = useState<CollectionBrief[]>([]);
  const [coinRows, setCoinRows] = useState<CoinTransaction[]>([]);
  const [discover, setDiscover] = useState<Wallpaper[]>([]);
  const [discoverQuery, setDiscoverQuery] = useState('');
  const [discoverSort, setDiscoverSort] = useState('newest');
  const [discoverCategory, setDiscoverCategory] = useState<number | null>(null);
  const [discoverLive, setDiscoverLive] = useState(false);
  const [libraryTab, setLibraryTab] = useState<LibraryTab>('favorites');
  const [bootLoading, setBootLoading] = useState(true);
  const [discoverLoading, setDiscoverLoading] = useState(true);
  const [authLoading, setAuthLoading] = useState(false);
  const [localIDs, setLocalIDs] = useState<Set<number>>(new Set());
  const [downloadedPaths, setDownloadedPaths] = useState<Map<number, string>>(new Map());
  const [diskBytes, setDiskBytes] = useState(0);
  const [appliedID, setAppliedID] = useState<number | null>(() => numberFromStorage(APPLIED_KEY));
  const [selectedWallpaper, setSelectedWallpaper] = useState<Wallpaper | null>(null);
  const [collectionTarget, setCollectionTarget] = useState<Wallpaper | null>(null);
  const [toast, setToast] = useState<{ kind: ToastKind; title: string; text?: string } | null>(null);
  const [busy, setBusy] = useState<{ id?: number; label: string } | null>(null);
  const [autoplayCollection, setAutoplayCollection] = useState(() => {
    const id = numberFromStorage(AUTOPLAY_COLLECTION_KEY);
    const title = localStorage.getItem(AUTOPLAY_COLLECTION_TITLE_KEY) || '';
    return id ? { id, title } : null;
  });

  const showToast = useCallback((kind: ToastKind, title: string, text?: string) => {
    setToast({ kind, title, text });
    window.setTimeout(() => {
      setToast((current) => (current?.title === title ? null : current));
    }, 4200);
  }, []);

  const refreshLocal = useCallback(async () => {
    try {
      const local = await cmd.listDownloaded();
      setLocalIDs(new Set(local.map((item) => item.id)));
      setDownloadedPaths(new Map(local.map((item) => [item.id, item.path] as const)));
      setDiskBytes(await cmd.downloadsTotalBytes());
    } catch (error) {
      console.error('refresh local downloads failed', error);
    }
  }, []);

  const loadAuthData = useCallback(async () => {
    if (!token) {
      setMe(null);
      setDownloads([]);
      setFavorites([]);
      setLikes([]);
      setMyCollections([]);
      setCoinRows([]);
      setForYou([]);
      return;
    }
    setAuthLoading(true);
    try {
      const [meResult, downloadsResult, favoritesResult, likesResult, collectionsResult, coinsResult, forYouResult] =
        await Promise.allSettled([
          api.me(),
          api.listMyDownloads({ limit: 48 }),
          api.listMyFavorites({ limit: 48 }),
          api.listMyLikes({ limit: 48 }),
          api.listMyCollections({ limit: 80 }),
          api.coinTransactions({ limit: 20 }),
          api.forYou(18),
        ]);
      if (meResult.status === 'fulfilled') setMe(meResult.value);
      if (downloadsResult.status === 'fulfilled') setDownloads(downloadsResult.value.items);
      if (favoritesResult.status === 'fulfilled') setFavorites(favoritesResult.value.items);
      if (likesResult.status === 'fulfilled') setLikes(likesResult.value.items);
      if (collectionsResult.status === 'fulfilled') setMyCollections(collectionsResult.value);
      if (coinsResult.status === 'fulfilled') setCoinRows(coinsResult.value.items);
      if (forYouResult.status === 'fulfilled') setForYou(forYouResult.value);
    } finally {
      setAuthLoading(false);
    }
  }, [token]);

  const loadBootstrap = useCallback(async () => {
    setBootLoading(true);
    try {
      const [categoriesResult, latestResult, weeklyResult, archiveResult, collectionsResult] =
        await Promise.allSettled([
          api.categories(),
          api.listWallpapers({ limit: 24, sort: 'newest', exclude_video: true }),
          api.weeklyCurrent(),
          api.weeklyArchive(32),
          api.listCollections({ limit: 24 }),
        ]);
      if (categoriesResult.status === 'fulfilled') setCategories(categoriesResult.value);
      if (latestResult.status === 'fulfilled') setLatest(latestResult.value.items);
      if (weeklyResult.status === 'fulfilled') setWeekly(weeklyResult.value);
      if (archiveResult.status === 'fulfilled') setWeeklyArchive(archiveResult.value);
      if (collectionsResult.status === 'fulfilled') setPublicCollections(collectionsResult.value.items);
    } catch (error) {
      showToast('error', '加载失败', error instanceof Error ? error.message : String(error));
    } finally {
      setBootLoading(false);
    }
  }, [showToast]);

  const loadDiscover = useCallback(async () => {
    setDiscoverLoading(true);
    try {
      const data = await api.listWallpapers({
        limit: 60,
        sort: discoverSort,
        search: discoverQuery.trim(),
        category_id: discoverCategory,
        dynamic_only: discoverLive || undefined,
        include_dynamic: discoverLive || undefined,
        exclude_video: discoverLive ? undefined : true,
      });
      setDiscover(data.items);
    } catch (error) {
      showToast('error', '发现页加载失败', error instanceof Error ? error.message : String(error));
    } finally {
      setDiscoverLoading(false);
    }
  }, [discoverCategory, discoverLive, discoverQuery, discoverSort, showToast]);

  useEffect(() => {
    loadBootstrap();
    refreshLocal();
  }, [loadBootstrap, refreshLocal]);

  useEffect(() => {
    loadAuthData();
  }, [loadAuthData]);

  useEffect(() => {
    loadDiscover();
  }, [loadDiscover]);

  useEffect(() => {
    if (!autoplayCollection || !token) return;
    const timer = window.setInterval(() => {
      runAutoplayOnce(autoplayCollection.id, false);
    }, 30 * 60 * 1000);
    return () => window.clearInterval(timer);
  }, [autoplayCollection, token]);

  const homeHero = weekly?.picks.find((item) => item.is_hero) ?? weekly?.picks[0] ?? latest[0] ?? null;
  const homeLatest = latest.slice(0, 10);
  const homeForYou = (forYou.length ? forYou : latest).slice(0, 10);
  const storageLabel = useMemo(() => formatBytes(diskBytes), [diskBytes]);

  async function signOut() {
    await clearToken();
    setMe(null);
    setDownloads([]);
    setFavorites([]);
    setLikes([]);
    setMyCollections([]);
    onSignOut();
    showToast('success', '已退出登录');
  }

  function requireAuth(): boolean {
    if (token) return true;
    onRequestSignIn();
    showToast('info', '需要登录', '下载、收藏、点赞和合集功能需要先登录。');
    return false;
  }

  async function runWallpaperAction(wallpaper: Wallpaper, label: string, action: () => Promise<void>) {
    setBusy({ id: wallpaper.id, label });
    try {
      await action();
    } catch (error) {
      showToast('error', `${label}失败`, error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(null);
    }
  }

  async function downloadWallpaper(wallpaper: Wallpaper, quiet = false) {
    if (!requireAuth()) return;
    await runWallpaperAction(wallpaper, '下载', async () => {
      const url = await originalDownloadURL(wallpaper);
      await cmd.downloadWallpaper(wallpaper.id, url);
      await refreshLocal();
      await loadAuthData();
      if (!quiet) showToast('success', '下载完成', `${wallpaper.title || '壁纸'} 已保存到本机下载目录。`);
    });
  }

  async function setWallpaper(wallpaper: Wallpaper) {
    if (!requireAuth()) return;
    await runWallpaperAction(wallpaper, '设为壁纸', async () => {
      if (canSetOriginalOnWindows(wallpaper)) {
        const url = await originalDownloadURL(wallpaper);
        await cmd.setWallpaperById(wallpaper.id, url);
        showToast('success', '已设为桌面壁纸');
      } else {
        const fallbackURL = previewURL(wallpaper);
        if (!fallbackURL) throw new Error('这张壁纸没有可用于 Windows 静态桌面的预览图。');
        const path = await cmd.downloadWallpaper(wallpaper.id, fallbackURL);
        await cmd.setStaticWallpaper(path);
        showToast('success', '已使用静态预览设置', 'Windows 端暂不支持视频/动态壁纸直接作为系统桌面，先降级为静态预览。');
      }
      setAppliedID(wallpaper.id);
      localStorage.setItem(APPLIED_KEY, String(wallpaper.id));
      await refreshLocal();
      await loadAuthData();
    });
  }

  async function setLocalWallpaper(wallpaper: Wallpaper) {
    const path = downloadedPaths.get(wallpaper.id);
    if (!path) return setWallpaper(wallpaper);
    await runWallpaperAction(wallpaper, '设为壁纸', async () => {
      await cmd.setStaticWallpaper(path);
      setAppliedID(wallpaper.id);
      localStorage.setItem(APPLIED_KEY, String(wallpaper.id));
      showToast('success', '已设为桌面壁纸');
    });
  }

  async function toggleLike(wallpaper: Wallpaper) {
    if (!requireAuth()) return;
    await runWallpaperAction(wallpaper, wallpaper.is_liked ? '取消点赞' : '点赞', async () => {
      if (wallpaper.is_liked) await api.unlike(wallpaper.id);
      else await api.like(wallpaper.id);
      updateWallpaperEverywhere(wallpaper.id, {
        is_liked: !wallpaper.is_liked,
        like_count: Math.max(0, (wallpaper.like_count ?? 0) + (wallpaper.is_liked ? -1 : 1)),
      });
      await loadAuthData();
    });
  }

  async function toggleFavorite(wallpaper: Wallpaper) {
    if (!requireAuth()) return;
    await runWallpaperAction(wallpaper, wallpaper.is_favorited ? '取消收藏' : '收藏', async () => {
      if (wallpaper.is_favorited) await api.unfavorite(wallpaper.id);
      else await api.favorite(wallpaper.id);
      updateWallpaperEverywhere(wallpaper.id, {
        is_favorited: !wallpaper.is_favorited,
        favorite_count: Math.max(0, (wallpaper.favorite_count ?? 0) + (wallpaper.is_favorited ? -1 : 1)),
      });
      await loadAuthData();
    });
  }

  async function reportWallpaper(wallpaper: Wallpaper) {
    if (!requireAuth()) return;
    await runWallpaperAction(wallpaper, '举报', async () => {
      await api.reportWallpaper(wallpaper.id);
      showToast('success', '已提交举报', '我们会尽快处理这张壁纸。');
    });
  }

  function updateWallpaperEverywhere(id: number, patch: Partial<Wallpaper>) {
    const updater = (list: Wallpaper[]) => list.map((item) => (item.id === id ? { ...item, ...patch } : item));
    setLatest(updater);
    setForYou(updater);
    setDiscover(updater);
    setDownloads(updater);
    setFavorites(updater);
    setLikes(updater);
    setWeekly((current) => current ? { ...current, picks: updater(current.picks) as WeeklyCurrent['picks'] } : current);
    setSelectedWallpaper((current) => (current?.id === id ? { ...current, ...patch } : current));
  }

  async function enableCollectionAutoplay(collection: CollectionBrief) {
    if (!requireAuth()) return;
    setBusy({ label: '准备自动播放合集' });
    try {
      const wallpapers = await fetchAllCollectionWallpapers(collection.id);
      for (const wallpaper of wallpapers) {
        const url = await originalDownloadURL(wallpaper);
        await cmd.downloadWallpaper(wallpaper.id, url);
      }
      await refreshLocal();
      localStorage.setItem(AUTOPLAY_COLLECTION_KEY, String(collection.id));
      localStorage.setItem(AUTOPLAY_COLLECTION_TITLE_KEY, collection.title);
      setAutoplayCollection({ id: collection.id, title: collection.title });
      showToast('success', '已开启合集自动播放', '缺失的壁纸已自动下载。应用运行时会优先从这个合集中轮播。');
    } catch (error) {
      showToast('error', '自动播放设置失败', error instanceof Error ? error.message : String(error));
    } finally {
      setBusy(null);
    }
  }

  function disableCollectionAutoplay() {
    localStorage.removeItem(AUTOPLAY_COLLECTION_KEY);
    localStorage.removeItem(AUTOPLAY_COLLECTION_TITLE_KEY);
    setAutoplayCollection(null);
    showToast('success', '已关闭合集自动播放');
  }

  async function fetchAllCollectionWallpapers(collectionID: number): Promise<Wallpaper[]> {
    const all: Wallpaper[] = [];
    let cursor: number | null | undefined = null;
    for (let i = 0; i < 4; i += 1) {
      const page = await api.listCollectionWallpapers(collectionID, { limit: 60, cursor });
      all.push(...page.items);
      if (!page.has_more || !page.next_cursor) break;
      cursor = page.next_cursor;
    }
    return all;
  }

  async function runAutoplayOnce(collectionID: number, notify = true) {
    try {
      const wallpapers = await fetchAllCollectionWallpapers(collectionID);
      if (!wallpapers.length) return;
      const wallpaper = wallpapers[Math.floor(Math.random() * wallpapers.length)];
      await setWallpaper(wallpaper);
      if (notify) showToast('success', '已切换自动播放壁纸', wallpaper.title);
    } catch (error) {
      if (notify) showToast('error', '自动播放失败', error instanceof Error ? error.message : String(error));
    }
  }

  async function originalDownloadURL(wallpaper: Wallpaper): Promise<string> {
    if (wallpaper.original_url) return wallpaper.original_url;
    return api.getDownloadURL(wallpaper.id);
  }

  const actionProps: WallpaperActions = {
    busyID: busy?.id,
    appliedID,
    localIDs,
    onOpen: setSelectedWallpaper,
    onDownload: downloadWallpaper,
    onSet: setWallpaper,
    onSetLocal: setLocalWallpaper,
    onLike: toggleLike,
    onFavorite: toggleFavorite,
    onAddToCollection: (wallpaper) => {
      if (!requireAuth()) return;
      setCollectionTarget(wallpaper);
    },
  };

  return (
    <div className="desktop-shell">
      <aside className="side-nav">
        <div className="brand-mark">
          <span>W</span>
        </div>
        <div className="nav-list">
          {navItems.map((item) => (
            <button
              key={item.key}
              className={`nav-item ${view === item.key ? 'active' : ''}`}
              onClick={() => setView(item.key)}
            >
              <span>{item.title}</span>
              <small>{item.hint}</small>
            </button>
          ))}
        </div>
        <div className="side-footer">
          <div className="kicker">Local</div>
          <strong>{storageLabel}</strong>
          <small>{localIDs.size} 张已缓存</small>
        </div>
      </aside>

      <main className="workbench">
        <TopBar me={me} token={token} onSignIn={onRequestSignIn} onSignOut={signOut} />
        {toast && <ToastCard toast={toast} onClose={() => setToast(null)} />}
        {busy && !busy.id && <div className="global-busy">{busy.label}...</div>}

        {view === 'home' && (
          <HomeView
            loading={bootLoading}
            hero={homeHero}
            weekly={weekly}
            latest={homeLatest}
            forYou={homeForYou}
            collections={publicCollections.slice(0, 6)}
            onView={setView}
            actions={actionProps}
          />
        )}

        {view === 'discover' && (
          <DiscoverView
            categories={categories}
            query={discoverQuery}
            sort={discoverSort}
            category={discoverCategory}
            live={discoverLive}
            loading={discoverLoading}
            wallpapers={discover}
            onQuery={setDiscoverQuery}
            onSort={setDiscoverSort}
            onCategory={setDiscoverCategory}
            onLive={setDiscoverLive}
            actions={actionProps}
          />
        )}

        {view === 'weekly' && (
          <WeeklyView
            current={weekly}
            archive={weeklyArchive}
            loading={bootLoading}
            actions={actionProps}
          />
        )}

        {view === 'collections' && (
          <CollectionsView
            collections={publicCollections}
            loading={bootLoading}
            onOpenWallpaper={setSelectedWallpaper}
          />
        )}

        {view === 'downloads' && (
          <DownloadsView
            token={token}
            loading={authLoading}
            wallpapers={downloads}
            localIDs={localIDs}
            actions={actionProps}
            onSignIn={onRequestSignIn}
          />
        )}

        {view === 'library' && (
          <LibraryView
            token={token}
            me={me}
            tab={libraryTab}
            favorites={favorites}
            likes={likes}
            collections={myCollections}
            coinRows={coinRows}
            autoplayCollection={autoplayCollection}
            loading={authLoading}
            actions={actionProps}
            onTab={setLibraryTab}
            onSignIn={onRequestSignIn}
            onEnableAutoplay={enableCollectionAutoplay}
            onDisableAutoplay={disableCollectionAutoplay}
            onRunAutoplay={() => autoplayCollection && runAutoplayOnce(autoplayCollection.id)}
          />
        )}

        {view === 'upload' && <UploadView token={token} onSignIn={onRequestSignIn} />}

        {view === 'settings' && (
          <SettingsView
            me={me}
            appliedID={appliedID}
            storageLabel={storageLabel}
            autoplayCollection={autoplayCollection}
            onDisableAutoplay={disableCollectionAutoplay}
            onRefresh={() => {
              loadBootstrap();
              loadAuthData();
              refreshLocal();
              showToast('success', '已刷新');
            }}
          />
        )}
      </main>

      {selectedWallpaper && (
        <DetailOverlay
          initial={selectedWallpaper}
          actions={actionProps}
          onClose={() => setSelectedWallpaper(null)}
          onReport={reportWallpaper}
        />
      )}

      {collectionTarget && (
        <CollectionPicker
          wallpaper={collectionTarget}
          onClose={() => setCollectionTarget(null)}
          onDone={() => {
            setCollectionTarget(null);
            loadAuthData();
            showToast('success', '合集已更新');
          }}
        />
      )}
    </div>
  );
}

interface WallpaperActions {
  busyID?: number;
  appliedID: number | null;
  localIDs: Set<number>;
  onOpen: (wallpaper: Wallpaper) => void;
  onDownload: (wallpaper: Wallpaper, quiet?: boolean) => Promise<void>;
  onSet: (wallpaper: Wallpaper) => Promise<void>;
  onSetLocal: (wallpaper: Wallpaper) => Promise<void>;
  onLike: (wallpaper: Wallpaper) => Promise<void>;
  onFavorite: (wallpaper: Wallpaper) => Promise<void>;
  onAddToCollection: (wallpaper: Wallpaper) => void;
}

function TopBar({
  me,
  token,
  onSignIn,
  onSignOut,
}: {
  me: User | null;
  token: string | null;
  onSignIn: () => void;
  onSignOut: () => void;
}) {
  return (
    <header className="top-bar">
      <div>
        <div className="kicker">Wallpaper Exchange</div>
        <h1>Windows 客户端</h1>
      </div>
      <div className="account-chip">
        {token && me ? (
          <>
            <Avatar user={me} />
            <div>
              <strong>{me.nickname || me.username}</strong>
              <span>{me.coins} 金币</span>
            </div>
            <button className="ghost" onClick={onSignOut}>退出</button>
          </>
        ) : (
          <button className="primary-pill" onClick={onSignIn}>登录</button>
        )}
      </div>
    </header>
  );
}

function HomeView({
  loading,
  hero,
  weekly,
  latest,
  forYou,
  collections,
  onView,
  actions,
}: {
  loading: boolean;
  hero: Wallpaper | null;
  weekly: WeeklyCurrent | null;
  latest: Wallpaper[];
  forYou: Wallpaper[];
  collections: CollectionItem[];
  onView: (view: ViewKey) => void;
  actions: WallpaperActions;
}) {
  return (
    <div className="page-flow">
      <SectionHeader title="每周推荐" subtitle={weekly ? `第 ${weekly.week} 周` : '最近四周'} action="查看更多" onAction={() => onView('weekly')} />
      {loading && !hero ? (
        <SkeletonHero />
      ) : hero ? (
        <button className="weekly-hero" style={{ backgroundColor: colorOf(hero) }} onClick={() => actions.onOpen(hero)}>
          <ProgressiveImage wallpaper={hero} className="weekly-image" />
          <div className="weekly-copy">
            <span>第 {weekly?.week ?? '--'} 周</span>
            <strong>{weekly?.picks.length ?? 0} 张精选</strong>
          </div>
        </button>
      ) : (
        <EmptyState title="还没有每周推荐" />
      )}

      <SectionHeader title="最新壁纸" subtitle="" action="查看更多" onAction={() => onView('discover')} />
      <WallpaperGrid wallpapers={latest} loading={loading} actions={actions} />

      <SectionHeader title="为你推荐" subtitle="" action="查看更多" onAction={() => onView('discover')} />
      <WallpaperGrid wallpapers={forYou} loading={loading} actions={actions} compact />

      <SectionHeader title="最新合集" subtitle="" action="查看更多" onAction={() => onView('collections')} />
      <CollectionGrid collections={collections} />
    </div>
  );
}

function DiscoverView({
  categories,
  query,
  sort,
  category,
  live,
  loading,
  wallpapers,
  onQuery,
  onSort,
  onCategory,
  onLive,
  actions,
}: {
  categories: Category[];
  query: string;
  sort: string;
  category: number | null;
  live: boolean;
  loading: boolean;
  wallpapers: Wallpaper[];
  onQuery: (value: string) => void;
  onSort: (value: string) => void;
  onCategory: (value: number | null) => void;
  onLive: (value: boolean) => void;
  actions: WallpaperActions;
}) {
  return (
    <div className="page-flow">
      <div className="toolbar-row">
        <input value={query} onChange={(event) => onQuery(event.target.value)} placeholder="搜索壁纸、颜色、主题" />
        <select value={sort} onChange={(event) => onSort(event.target.value)}>
          <option value="newest">最新</option>
          <option value="trending">热门</option>
          <option value="downloads">下载最多</option>
        </select>
        <button className={live ? 'filter active' : 'filter'} onClick={() => onLive(!live)}>动态</button>
      </div>
      <div className="chip-row">
        <button className={category === null ? 'chip-filter active' : 'chip-filter'} onClick={() => onCategory(null)}>全部</button>
        {categories.map((item) => (
          <button
            key={item.id}
            className={category === item.id ? 'chip-filter active' : 'chip-filter'}
            onClick={() => onCategory(item.id)}
          >
            {item.name}
          </button>
        ))}
      </div>
      <WallpaperGrid wallpapers={wallpapers} loading={loading} actions={actions} />
    </div>
  );
}

function WeeklyView({
  current,
  archive,
  loading,
  actions,
}: {
  current: WeeklyCurrent | null;
  archive: WeeklyArchiveEntry[];
  loading: boolean;
  actions: WallpaperActions;
}) {
  const [selectedWeek, setSelectedWeek] = useState<WeeklyArchiveEntry | null>(null);
  const [weekWallpapers, setWeekWallpapers] = useState<Wallpaper[]>([]);
  const [weekLoading, setWeekLoading] = useState(false);

  useEffect(() => {
    if (!selectedWeek) return;
    setWeekLoading(true);
    api.weeklyByWeek(selectedWeek.year, selectedWeek.week)
      .then((data) => setWeekWallpapers(data.picks))
      .finally(() => setWeekLoading(false));
  }, [selectedWeek]);

  return (
    <div className="page-flow">
      <SectionHeader title="每周推荐" subtitle={current ? `${current.year} 第 ${current.week} 周` : ''} />
      <WallpaperGrid wallpapers={current?.picks ?? []} loading={loading} actions={actions} />
      <SectionHeader title="往期推荐" subtitle="" />
      <div className="archive-grid">
        {archive.map((item) => (
          <button
            key={`${item.year}-${item.week}`}
            className="archive-card"
            style={{ backgroundColor: item.dominant_color || item.accent_color || undefined }}
            onClick={() => setSelectedWeek(item)}
          >
            <img src={item.cover_url} alt="" />
            <span>{item.year}</span>
            <strong>第 {item.week} 周</strong>
            <small>{item.count} 张精选</small>
          </button>
        ))}
      </div>
      {selectedWeek && (
        <div className="inline-panel">
          <div className="inline-panel-head">
            <strong>{selectedWeek.year} 第 {selectedWeek.week} 周</strong>
            <button className="ghost" onClick={() => setSelectedWeek(null)}>关闭</button>
          </div>
          <WallpaperGrid wallpapers={weekWallpapers} loading={weekLoading} actions={actions} compact />
        </div>
      )}
    </div>
  );
}

function CollectionsView({
  collections,
  loading,
  onOpenWallpaper,
}: {
  collections: CollectionItem[];
  loading: boolean;
  onOpenWallpaper: (wallpaper: Wallpaper) => void;
}) {
  const [selected, setSelected] = useState<CollectionItem | null>(null);
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [loadingWallpapers, setLoadingWallpapers] = useState(false);

  useEffect(() => {
    if (!selected) return;
    setLoadingWallpapers(true);
    api.listCollectionWallpapers(selected.id, { limit: 48 })
      .then((data) => setWallpapers(data.items))
      .finally(() => setLoadingWallpapers(false));
  }, [selected]);

  return (
    <div className="page-flow">
      <SectionHeader title="最新合集" subtitle="" />
      <CollectionGrid collections={collections} loading={loading} onOpen={setSelected} />
      {selected && (
        <div className="inline-panel">
          <div className="inline-panel-head">
            <div>
              <strong>{selected.title}</strong>
              <span>{selected.wallpaper_count} 张壁纸</span>
            </div>
            <button className="ghost" onClick={() => setSelected(null)}>关闭</button>
          </div>
          {loadingWallpapers ? <SkeletonGrid count={10} /> : (
            <div className="wallpaper-grid compact">
              {wallpapers.map((wallpaper) => (
                <button key={wallpaper.id} className="mini-wallpaper" onClick={() => onOpenWallpaper(wallpaper)}>
                  <ProgressiveImage wallpaper={wallpaper} />
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function DownloadsView({
  token,
  loading,
  wallpapers,
  localIDs,
  actions,
  onSignIn,
}: {
  token: string | null;
  loading: boolean;
  wallpapers: Wallpaper[];
  localIDs: Set<number>;
  actions: WallpaperActions;
  onSignIn: () => void;
}) {
  if (!token) return <LockedState title="登录后查看我的下载" onSignIn={onSignIn} />;
  return (
    <div className="page-flow">
      <SectionHeader title="我的下载" subtitle="服务器下载记录和本机缓存会在这里合并展示" />
      <WallpaperGrid wallpapers={wallpapers} loading={loading} actions={actions} localIDs={localIDs} />
    </div>
  );
}

function LibraryView({
  token,
  me,
  tab,
  favorites,
  likes,
  collections,
  coinRows,
  autoplayCollection,
  loading,
  actions,
  onTab,
  onSignIn,
  onEnableAutoplay,
  onDisableAutoplay,
  onRunAutoplay,
}: {
  token: string | null;
  me: User | null;
  tab: LibraryTab;
  favorites: Wallpaper[];
  likes: Wallpaper[];
  collections: CollectionBrief[];
  coinRows: CoinTransaction[];
  autoplayCollection: { id: number; title: string } | null;
  loading: boolean;
  actions: WallpaperActions;
  onTab: (tab: LibraryTab) => void;
  onSignIn: () => void;
  onEnableAutoplay: (collection: CollectionBrief) => void;
  onDisableAutoplay: () => void;
  onRunAutoplay: () => void;
}) {
  if (!token) return <LockedState title="登录后查看我的主页" onSignIn={onSignIn} />;
  return (
    <div className="page-flow">
      <div className="profile-card">
        <Avatar user={me} large />
        <div>
          <h2>{me?.nickname || me?.username || '我的主页'}</h2>
          <p>{me?.bio || '还没有个人简介。'}</p>
        </div>
        <div className="coin-pill">{me?.coins ?? 0} 金币</div>
      </div>
      <div className="tab-row">
        <button className={tab === 'favorites' ? 'active' : ''} onClick={() => onTab('favorites')}>我的收藏</button>
        <button className={tab === 'likes' ? 'active' : ''} onClick={() => onTab('likes')}>我的点赞</button>
        <button className={tab === 'collections' ? 'active' : ''} onClick={() => onTab('collections')}>我的合集</button>
        <button className={tab === 'coins' ? 'active' : ''} onClick={() => onTab('coins')}>金币明细</button>
      </div>
      {tab === 'favorites' && <WallpaperGrid wallpapers={favorites} loading={loading} actions={actions} />}
      {tab === 'likes' && <WallpaperGrid wallpapers={likes} loading={loading} actions={actions} />}
      {tab === 'collections' && (
        <div className="collection-list">
          {autoplayCollection && (
            <div className="autoplay-banner">
              <div>
                <strong>正在优先自动播放：{autoplayCollection.title}</strong>
                <span>应用运行时会从这个合集中轮播，优先级高于我的下载。</span>
              </div>
              <button onClick={onRunAutoplay}>立即切换</button>
              <button className="ghost" onClick={onDisableAutoplay}>关闭</button>
            </div>
          )}
          {collections.map((collection) => (
            <div key={collection.id} className="my-collection-row">
              <div>
                <strong>{collection.title}</strong>
                <span>{collection.wallpaper_count} 张壁纸</span>
              </div>
              <button onClick={() => onEnableAutoplay(collection)}>
                {autoplayCollection?.id === collection.id ? '重新准备' : '设为自动播放'}
              </button>
            </div>
          ))}
          {!collections.length && <EmptyState title="还没有创建合集" />}
        </div>
      )}
      {tab === 'coins' && (
        <div className="ledger-list">
          {coinRows.map((row) => (
            <div key={row.id} className="ledger-row">
              <strong>{row.amount > 0 ? `+${row.amount}` : row.amount}</strong>
              <span>{row.reason || row.type || '金币变动'}</span>
              <small>{formatDate(row.created_at)}</small>
            </div>
          ))}
          {!coinRows.length && <EmptyState title="暂无金币记录" />}
        </div>
      )}
    </div>
  );
}

function UploadView({ token, onSignIn }: { token: string | null; onSignIn: () => void }) {
  return (
    <div className="upload-panel">
      <div>
        <div className="kicker">Upload</div>
        <h2>上传壁纸</h2>
        <p>Windows 端先降级为打开官网上传页，避免本地文件上传协议和审核字段缺失导致失败。登录状态、审核和金币仍然走同一个线上系统。</p>
      </div>
      {token ? (
        <button className="primary-pill" onClick={() => open('https://wallpaperexchange.com/upload')}>打开官网上传</button>
      ) : (
        <button className="primary-pill" onClick={onSignIn}>登录后上传</button>
      )}
    </div>
  );
}

function SettingsView({
  me,
  appliedID,
  storageLabel,
  autoplayCollection,
  onDisableAutoplay,
  onRefresh,
}: {
  me: User | null;
  appliedID: number | null;
  storageLabel: string;
  autoplayCollection: { id: number; title: string } | null;
  onDisableAutoplay: () => void;
  onRefresh: () => void;
}) {
  return (
    <div className="page-flow">
      <SectionHeader title="设置" subtitle="Windows 端能力和本地状态" />
      <div className="settings-grid">
        <InfoBlock title="当前账号" value={me ? (me.nickname || me.username) : '未登录'} />
        <InfoBlock title="本地缓存" value={storageLabel} />
        <InfoBlock title="当前壁纸" value={appliedID ? `#${appliedID}` : '未设置'} />
        <InfoBlock title="自动播放" value={autoplayCollection?.title || '未开启'} />
      </div>
      <div className="settings-card">
        <h3>Windows 降级说明</h3>
        <p>静态 JPG/PNG/BMP/WebP 会直接调用 Windows 官方桌面壁纸 API。视频壁纸和 macOS 动态 HEIC 暂时会下载原文件，并在设置时降级为静态预览图。</p>
        <div className="button-row">
          <button onClick={onRefresh}>刷新数据</button>
          {autoplayCollection && <button className="ghost" onClick={onDisableAutoplay}>关闭自动播放</button>}
        </div>
      </div>
    </div>
  );
}

function DetailOverlay({
  initial,
  actions,
  onClose,
  onReport,
}: {
  initial: Wallpaper;
  actions: WallpaperActions;
  onClose: () => void;
  onReport: (wallpaper: Wallpaper) => Promise<void>;
}) {
  const [detail, setDetail] = useState<WallpaperDetail | null>(null);
  const [similar, setSimilar] = useState<Wallpaper[]>([]);
  const [loading, setLoading] = useState(true);
  const merged = detail ? { ...initial, ...detail } : initial;

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setDetail(null);
    setSimilar([]);
    api.getWallpaper(initial.slug || initial.id)
      .then((data) => {
        if (!alive) return;
        setDetail(data);
        return api.similar(data.id, 12);
      })
      .then((items) => {
        if (alive && items) setSimilar(items);
      })
      .catch((error) => console.error('detail load failed', error))
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [initial]);

  return (
    <div className="detail-overlay" style={{ backgroundColor: colorOf(merged) }}>
      <button className="round-control back" onClick={onClose}>‹</button>
      <InfoMenu wallpaper={merged} loading={loading} onReport={() => onReport(merged)} />
      <section className="detail-hero">
        <HeroMedia wallpaper={merged} loading={loading} />
        <ActionDock wallpaper={merged} actions={actions} detail />
      </section>
      <section className="similar-section">
        <div>
          <div className="kicker">相关档案</div>
          <h2>更多相似壁纸</h2>
        </div>
        <WallpaperGrid wallpapers={similar} loading={loading} actions={actions} compact />
      </section>
    </div>
  );
}

function HeroMedia({ wallpaper, loading }: { wallpaper: Wallpaper; loading: boolean }) {
  const [loaded, setLoaded] = useState(false);
  const mainURL = originalImageURL(wallpaper);
  const fallback = previewURL(wallpaper);
  const frames = parseFrameURLs(wallpaper.frame_urls);

  useEffect(() => {
    setLoaded(false);
  }, [mainURL, fallback, wallpaper.id]);

  if (isVideo(wallpaper) && (wallpaper.preview_video_url || mainURL)) {
    return (
      <div className="hero-media">
        <video src={wallpaper.preview_video_url || mainURL || undefined} poster={fallback || undefined} autoPlay muted loop playsInline controls />
        {(loading || !loaded) && <ImageBeam />}
      </div>
    );
  }

  if (frames.length > 1) {
    return (
      <div className="hero-media">
        <DynamicFramePreview frames={frames} fallback={fallback} />
        {loading && <ImageBeam />}
      </div>
    );
  }

  return (
    <div className="hero-media">
      {fallback && <img className="hero-preview" src={fallback} alt="" />}
      {mainURL && (
        <img
          className={`hero-full ${loaded ? 'loaded' : ''}`}
          src={mainURL}
          alt=""
          onLoad={() => setLoaded(true)}
          onError={() => setLoaded(true)}
        />
      )}
      {(loading || !loaded) && <ImageBeam />}
    </div>
  );
}

function DynamicFramePreview({ frames, fallback }: { frames: string[]; fallback?: string | null }) {
  const [index, setIndex] = useState(0);
  useEffect(() => {
    if (frames.length < 2) return;
    const timer = window.setInterval(() => {
      setIndex((value) => (value + 1) % frames.length);
    }, 1400);
    return () => window.clearInterval(timer);
  }, [frames.length]);
  return (
    <>
      {fallback && <img className="hero-preview" src={fallback} alt="" />}
      <img className="hero-full loaded" src={frames[index]} alt="" />
    </>
  );
}

function InfoMenu({
  wallpaper,
  loading,
  onReport,
}: {
  wallpaper: Wallpaper;
  loading: boolean;
  onReport: () => void;
}) {
  const [openInfo, setOpenInfo] = useState(false);
  return (
    <div className="info-menu" onMouseEnter={() => setOpenInfo(true)} onMouseLeave={() => setOpenInfo(false)}>
      <button className="round-control">i</button>
      {openInfo && (
        <div className="info-popover">
          {loading ? (
            <div className="info-skeleton" />
          ) : (
            <>
              <InfoLine label="上传者" value={wallpaper.uploader?.nickname || wallpaper.uploader?.username || `用户 #${wallpaper.user_id}`} />
              <InfoLine label="分类" value={wallpaper.category_id ? `#${wallpaper.category_id}` : '未分类'} />
              <InfoLine label="颜色" value={wallpaper.dominant_color || '未识别'} />
              <InfoLine label="下载" value={`${wallpaper.download_count ?? 0}`} />
              <InfoLine label="喜欢" value={`${wallpaper.like_count ?? 0}`} />
              <InfoLine label="收藏" value={`${wallpaper.favorite_count ?? 0}`} />
              <button className="ghost danger" onClick={onReport}>举报</button>
            </>
          )}
        </div>
      )}
    </div>
  );
}

function InfoLine({ label, value }: { label: string; value: string }) {
  return (
    <div className="info-line">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  );
}

function ActionDock({ wallpaper, actions, detail = false }: { wallpaper: Wallpaper; actions: WallpaperActions; detail?: boolean }) {
  const isBusy = actions.busyID === wallpaper.id;
  const downloaded = actions.localIDs.has(wallpaper.id) || wallpaper.is_downloaded;
  const applied = actions.appliedID === wallpaper.id;
  return (
    <div className={`action-dock ${detail ? 'detail' : ''}`}>
      <button className={wallpaper.is_liked ? 'active' : ''} onClick={() => actions.onLike(wallpaper)} disabled={isBusy}>
        {wallpaper.is_liked ? '已点赞' : '点赞'} <span>{wallpaper.like_count ?? 0}</span>
      </button>
      <button className={wallpaper.is_favorited ? 'active' : ''} onClick={() => actions.onFavorite(wallpaper)} disabled={isBusy}>
        {wallpaper.is_favorited ? '已收藏' : '收藏'}
      </button>
      <button onClick={() => actions.onAddToCollection(wallpaper)} disabled={isBusy}>加入合集</button>
      <div className="meta-strip">
        <span>{resolutionLabel(wallpaper)}</span>
        <span>{formatBytes(wallpaper.file_size)}</span>
        {isVideo(wallpaper) && <span>视频</span>}
        {wallpaper.is_dynamic && !isVideo(wallpaper) && <span>动态</span>}
      </div>
      <button className="orange" onClick={() => actions.onDownload(wallpaper)} disabled={isBusy || Boolean(downloaded)}>
        {isBusy ? '处理中' : downloaded ? '已获取' : '下载'}
      </button>
      <button className="orange" onClick={() => downloaded ? actions.onSetLocal(wallpaper) : actions.onSet(wallpaper)} disabled={isBusy || applied}>
        {applied ? '正在使用' : '设为壁纸'}
      </button>
    </div>
  );
}

function WallpaperGrid({
  wallpapers,
  loading,
  actions,
  compact = false,
}: {
  wallpapers: Wallpaper[];
  loading: boolean;
  actions: WallpaperActions;
  localIDs?: Set<number>;
  compact?: boolean;
}) {
  if (loading && wallpapers.length === 0) return <SkeletonGrid count={compact ? 8 : 12} />;
  if (!wallpapers.length) return <EmptyState title="还没有壁纸" />;
  return (
    <div className={`wallpaper-grid ${compact ? 'compact' : ''}`}>
      {wallpapers.map((wallpaper) => (
        <WallpaperCard key={wallpaper.id} wallpaper={wallpaper} actions={actions} />
      ))}
    </div>
  );
}

function WallpaperCard({ wallpaper, actions }: { wallpaper: Wallpaper; actions: WallpaperActions }) {
  return (
    <article className="wallpaper-card" style={{ backgroundColor: colorOf(wallpaper) }}>
      <button className="card-image-button" onClick={() => actions.onOpen(wallpaper)}>
        <ProgressiveImage wallpaper={wallpaper} />
        <span className="resolution-chip">{resolutionLabel(wallpaper)}</span>
        {isVideo(wallpaper) && <span className="type-chip">VIDEO</span>}
        {wallpaper.is_dynamic && !isVideo(wallpaper) && <span className="type-chip">DYNAMIC</span>}
      </button>
      <div className="card-actions">
        <button onClick={() => actions.onLike(wallpaper)}>{wallpaper.is_liked ? '已赞' : '点赞'}</button>
        <button onClick={() => actions.onFavorite(wallpaper)}>{wallpaper.is_favorited ? '已藏' : '收藏'}</button>
        <button onClick={() => actions.onAddToCollection(wallpaper)}>合集</button>
        <button className="orange" onClick={() => actions.onSet(wallpaper)}>设置</button>
      </div>
    </article>
  );
}

function ProgressiveImage({ wallpaper, className = '' }: { wallpaper: Wallpaper; className?: string }) {
  const [previewLoaded, setPreviewLoaded] = useState(false);
  const url = previewURL(wallpaper);
  return (
    <div className={`progressive-image ${className}`} style={{ backgroundColor: colorOf(wallpaper) }}>
      {url && <img src={url} alt="" onLoad={() => setPreviewLoaded(true)} />}
      {!previewLoaded && <ImageBeam />}
    </div>
  );
}

function ImageBeam() {
  return <span className="image-beam" aria-hidden="true" />;
}

function CollectionGrid({
  collections,
  loading = false,
  onOpen,
}: {
  collections: CollectionItem[];
  loading?: boolean;
  onOpen?: (collection: CollectionItem) => void;
}) {
  if (loading && collections.length === 0) return <SkeletonGrid count={6} collection />;
  if (!collections.length) return <EmptyState title="还没有合集" />;
  return (
    <div className="collection-grid">
      {collections.map((collection) => (
        <button key={collection.id} className="collection-card" onClick={() => onOpen?.(collection)}>
          <div className="collection-cover">
            {collection.cover_url ? (
              <img src={collection.cover_url} alt="" />
            ) : (
              collection.recent_tiles?.slice(0, 4).map((tile, index) => (
                <span key={`${collection.id}-${index}`} style={{ backgroundImage: tile.preview_url || tile.thumb_url ? `url(${tile.preview_url || tile.thumb_url})` : undefined, backgroundColor: tile.dominant_color || collection.accent_color || undefined }} />
              ))
            )}
          </div>
          <strong>{collection.title}</strong>
          <span>{collection.wallpaper_count} 张壁纸</span>
        </button>
      ))}
    </div>
  );
}

function CollectionPicker({
  wallpaper,
  onClose,
  onDone,
}: {
  wallpaper: Wallpaper;
  onClose: () => void;
  onDone: () => void;
}) {
  const [collections, setCollections] = useState<CollectionBrief[]>([]);
  const [title, setTitle] = useState('');
  const [titleFocused, setTitleFocused] = useState(false);
  const [busy, setBusy] = useState(false);
  const panelRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    api.listMyCollections({ wallpaper_id: wallpaper.id, limit: 80 }).then(setCollections);
  }, [wallpaper.id]);

  useEffect(() => {
    function closeOnOutside(event: MouseEvent) {
      if (panelRef.current && !panelRef.current.contains(event.target as Node)) onClose();
    }
    window.addEventListener('mousedown', closeOnOutside);
    return () => window.removeEventListener('mousedown', closeOnOutside);
  }, [onClose]);

  async function add(collection: CollectionBrief) {
    if (collection.contains_wallpaper) return;
    setBusy(true);
    try {
      await api.addToCollection(collection.id, wallpaper.id);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  async function create(event: FormEvent) {
    event.preventDefault();
    if (!title.trim()) return;
    setBusy(true);
    try {
      const created = await api.createCollection(title.trim());
      await api.addToCollection(created.id, wallpaper.id);
      onDone();
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="floating-popover-wrap">
      <div className="collection-picker glass-panel" ref={panelRef}>
        <div className="picker-head">
          <strong>加入合集</strong>
          <button className="round-close" onClick={onClose}>x</button>
        </div>
        <div className="picker-list">
          {collections.map((collection) => (
            <button
              key={collection.id}
              className={collection.contains_wallpaper ? 'picker-row exists' : 'picker-row'}
              onClick={() => add(collection)}
              disabled={busy || Boolean(collection.contains_wallpaper)}
            >
              <span>{collection.contains_wallpaper ? '✓' : '+'}</span>
              <div>
                <strong>{collection.title}</strong>
                <small>{collection.wallpaper_count} 张壁纸</small>
              </div>
              {collection.contains_wallpaper && <em>已存在</em>}
            </button>
          ))}
        </div>
        <form className="create-collection" onSubmit={create}>
          <input
            value={title}
            onChange={(event) => setTitle(event.target.value)}
            onFocus={() => setTitleFocused(true)}
            onBlur={() => setTitleFocused(false)}
            placeholder={titleFocused ? '' : '标题'}
          />
          <button className="orange" disabled={busy || !title.trim()}>创建</button>
        </form>
      </div>
    </div>
  );
}

function SectionHeader({ title, subtitle, action, onAction }: { title: string; subtitle?: string; action?: string; onAction?: () => void }) {
  return (
    <div className="section-head">
      <div>
        <h2>{title}</h2>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {action && <button className="text-action" onClick={onAction}>{action}</button>}
    </div>
  );
}

function SkeletonGrid({ count, collection = false }: { count: number; collection?: boolean }) {
  return (
    <div className={collection ? 'collection-grid' : 'wallpaper-grid'}>
      {Array.from({ length: count }).map((_, index) => (
        <div key={index} className={collection ? 'skeleton-card collection' : 'skeleton-card'}>
          <ImageBeam />
        </div>
      ))}
    </div>
  );
}

function SkeletonHero() {
  return (
    <div className="weekly-hero skeleton-hero">
      <ImageBeam />
    </div>
  );
}

function EmptyState({ title }: { title: string }) {
  return <div className="empty-state">{title}</div>;
}

function LockedState({ title, onSignIn }: { title: string; onSignIn: () => void }) {
  return (
    <div className="locked-state">
      <h2>{title}</h2>
      <p>登录后会同步你的收藏、下载、金币和合集。</p>
      <button className="primary-pill" onClick={onSignIn}>登录</button>
    </div>
  );
}

function ToastCard({ toast, onClose }: { toast: { kind: ToastKind; title: string; text?: string }; onClose: () => void }) {
  return (
    <button className={`toast-card ${toast.kind}`} onClick={onClose}>
      <strong>{toast.title}</strong>
      {toast.text && <span>{toast.text}</span>}
    </button>
  );
}

function InfoBlock({ title, value }: { title: string; value: string }) {
  return (
    <div className="info-block">
      <span>{title}</span>
      <strong>{value}</strong>
    </div>
  );
}

function Avatar({ user, large = false }: { user: User | null; large?: boolean }) {
  const label = (user?.nickname || user?.username || 'W').slice(0, 1).toUpperCase();
  return (
    <div className={large ? 'avatar large' : 'avatar'}>
      {user?.avatar_url ? <img src={user.avatar_url} alt="" /> : <span>{label}</span>}
    </div>
  );
}

function originalImageURL(wallpaper: Wallpaper): string | null {
  if (isVideo(wallpaper)) return null;
  return wallpaper.original_url || wallpaper.preview_url || wallpaper.thumb_url || null;
}

function previewURL(wallpaper: Wallpaper): string | null {
  return wallpaper.preview_url || wallpaper.thumb_url || wallpaper.original_url || null;
}

function isVideo(wallpaper: Wallpaper): boolean {
  return wallpaper.file_type?.startsWith('video/') || Boolean(wallpaper.preview_video_url);
}

function canSetOriginalOnWindows(wallpaper: Wallpaper): boolean {
  if (isVideo(wallpaper) || wallpaper.is_dynamic) return false;
  const url = wallpaper.original_url || '';
  const ext = url.split('?')[0].split('.').pop()?.toLowerCase();
  if (ext && ['jpg', 'jpeg', 'png', 'bmp', 'webp'].includes(ext)) return true;
  return ['image/jpeg', 'image/png', 'image/bmp', 'image/webp'].includes(wallpaper.file_type);
}

function parseFrameURLs(value?: string | null): string[] {
  if (!value) return [];
  return value.split(',').map((item) => item.trim()).filter(Boolean);
}

function colorOf(wallpaper: Wallpaper): string {
  return wallpaper.dominant_color || '#d8d1c7';
}

function resolutionLabel(wallpaper: Wallpaper): string {
  const px = Math.max(wallpaper.width || 0, wallpaper.height || 0);
  if (px >= 7680) return '8K';
  if (px >= 3840) return '4K';
  if (px >= 2560) return '2K';
  if (px >= 1920) return '1080P';
  if (wallpaper.width && wallpaper.height) return `${wallpaper.width}x${wallpaper.height}`;
  return 'HD';
}

function formatBytes(bytes?: number | null): string {
  const value = bytes ?? 0;
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(0)} KB`;
  if (value < 1024 * 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB`;
  return `${(value / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

function formatDate(value?: string): string {
  if (!value) return '';
  return new Date(value).toLocaleDateString('zh-CN');
}

function numberFromStorage(key: string): number | null {
  const value = localStorage.getItem(key);
  if (!value) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}
