import { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection, CoinTransaction } from '../types';
import { getUserProfile, getUserWallpapers, getUserCollections, getMyFavorites, getMyLikes, getMyDownloads, getMyCoins, getCoinTransactions } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

type TabKey = 'coins' | 'wallpapers' | 'collections' | 'favorites' | 'likes' | 'downloads';

interface WallpaperTab {
  items: Wallpaper[];
  cursor?: number;
  hasMore: boolean;
  loaded: boolean;
}

const TX_LABELS: Record<string, { label: string; color: string }> = {
  register_bonus: { label: 'Registration Bonus', color: 'text-green-600' },
  upload_reward: { label: 'Upload Reward', color: 'text-green-600' },
  download_cost: { label: 'Download Cost', color: 'text-red-500' },
  download_earned: { label: 'Download Earned', color: 'text-green-600' },
};

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleString();
}

export default function ProfilePage() {
  const { id } = useParams<{ id: string }>();
  const { user: currentUser, updateCoins } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  usePageTitle(user ? `${user.nickname || user.username}'s Profile` : 'Profile');
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [collections, setCollections] = useState<Collection[]>([]);

  const isOwnProfile = currentUser?.id === Number(id);
  const [activeTab, setActiveTab] = useState<TabKey>(isOwnProfile ? 'coins' : 'wallpapers');

  const [tabs, setTabs] = useState<Record<string, WallpaperTab>>({
    wallpapers: { items: [], hasMore: false, loaded: false },
    favorites: { items: [], hasMore: false, loaded: false },
    likes: { items: [], hasMore: false, loaded: false },
    downloads: { items: [], hasMore: false, loaded: false },
  });

  const [tabLoading, setTabLoading] = useState(false);
  const [transactions, setTransactions] = useState<CoinTransaction[]>([]);
  const [txCursor, setTxCursor] = useState<number | undefined>();
  const [txHasMore, setTxHasMore] = useState(false);
  const [txLoading, setTxLoading] = useState(false);
  const [txLoaded, setTxLoaded] = useState(false);

  const updateTab = (key: string, updates: Partial<WallpaperTab>) => {
    setTabs((prev) => ({ ...prev, [key]: { ...prev[key], ...updates } }));
  };

  const loadCoins = useCallback(async () => {
    try {
      const res = await getMyCoins();
      updateCoins(res.data.data.coins);
    } catch {
      // silent
    }
  }, [updateCoins]);

  const loadTransactions = useCallback(async (reset: boolean) => {
    setTxLoading(true);
    try {
      const res = await getCoinTransactions({
        cursor: reset ? undefined : txCursor,
        limit: 20,
      });
      const { items, next_cursor, has_more } = res.data.data;
      setTransactions((prev) => (reset ? items : [...prev, ...items]));
      setTxCursor(next_cursor);
      setTxHasMore(has_more);
      setTxLoaded(true);
    } catch {
      toast.error('Failed to load transactions');
    } finally {
      setTxLoading(false);
    }
  }, [txCursor]);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setTabs({
      wallpapers: { items: [], hasMore: false, loaded: false },
      favorites: { items: [], hasMore: false, loaded: false },
      likes: { items: [], hasMore: false, loaded: false },
      downloads: { items: [], hasMore: false, loaded: false },
    });
    setTransactions([]);
    setTxLoaded(false);

    const own = currentUser?.id === Number(id);
    setActiveTab(own ? 'coins' : 'wallpapers');

    Promise.all([
      getUserProfile(Number(id)),
      getUserWallpapers(Number(id), { limit: 20 }),
      getUserCollections(Number(id), { limit: 50 }),
    ])
      .then(([profileRes, wpRes, colRes]) => {
        setUser(profileRes.data.data);
        const { items, next_cursor, has_more } = wpRes.data.data;
        updateTab('wallpapers', { items, cursor: next_cursor, hasMore: has_more, loaded: true });
        setCollections(colRes.data.data?.items || []);
      })
      .catch(() => toast.error('Failed to load profile'))
      .finally(() => setLoading(false));

    if (own) {
      loadCoins();
      loadTransactions(true);
    }
  }, [id]);

  const loadTabData = useCallback(async (key: 'favorites' | 'likes' | 'downloads') => {
    const fetchers = { favorites: getMyFavorites, likes: getMyLikes, downloads: getMyDownloads };
    setTabLoading(true);
    try {
      const res = await fetchers[key]({ limit: 20 });
      const d = res.data.data;
      updateTab(key, {
        items: d?.items ?? [],
        cursor: d?.next_cursor,
        hasMore: d?.has_more ?? false,
        loaded: true,
      });
    } catch {
      toast.error('Failed to load data');
      updateTab(key, { loaded: true });
    } finally {
      setTabLoading(false);
    }
  }, []);

  const handleTabChange = (tab: TabKey) => {
    setActiveTab(tab);
    if ((tab === 'favorites' || tab === 'likes' || tab === 'downloads') && !tabs[tab]?.loaded) {
      loadTabData(tab);
    }
    if (tab === 'coins' && !txLoaded) {
      loadCoins();
      loadTransactions(true);
    }
  };

  const loadMore = useCallback(async () => {
    if (loadingMore) return;
    const tabKey = activeTab;
    const tab = tabs[tabKey];
    if (!tab || !tab.hasMore) return;

    setLoadingMore(true);
    try {
      let res;
      if (tabKey === 'wallpapers') {
        res = await getUserWallpapers(Number(id), { cursor: tab.cursor, limit: 20 });
      } else if (tabKey === 'favorites') {
        res = await getMyFavorites({ cursor: tab.cursor, limit: 20 });
      } else if (tabKey === 'downloads') {
        res = await getMyDownloads({ cursor: tab.cursor, limit: 20 });
      } else {
        res = await getMyLikes({ cursor: tab.cursor, limit: 20 });
      }
      const { items, next_cursor, has_more } = res.data.data;
      updateTab(tabKey, {
        items: [...tab.items, ...items],
        cursor: next_cursor,
        hasMore: has_more,
      });
    } catch {
      toast.error('Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [activeTab, tabs, id, loadingMore]);

  if (loading) return <Spinner />;
  if (!user) return <EmptyState message="User not found." />;

  const currentTab = tabs[activeTab];
  const tabDefs: { key: TabKey; label: string; ownerOnly: boolean }[] = [
    { key: 'coins', label: 'Coins', ownerOnly: true },
    { key: 'wallpapers', label: 'Wallpapers', ownerOnly: false },
    { key: 'collections', label: 'Collections', ownerOnly: false },
    { key: 'downloads', label: 'Downloads', ownerOnly: true },
    { key: 'favorites', label: 'Favorites', ownerOnly: true },
    { key: 'likes', label: 'Likes', ownerOnly: true },
  ];

  const renderCoinsTab = () => (
    <div className="max-w-2xl">
      <div className="bg-gradient-to-r from-amber-400 via-yellow-400 to-orange-400 rounded-2xl p-6 mb-8 text-white shadow-lg relative overflow-hidden">
        <div className="absolute -right-4 -top-4 text-[120px] opacity-10 rotate-12 select-none">💰</div>
        <p className="text-sm font-medium opacity-90 mb-1">My Coins</p>
        <p className="text-4xl font-bold">{currentUser?.coins ?? 0}</p>
        <p className="text-xs opacity-75 mt-2">
          Upload wallpapers to earn coins. Each download costs 1 coin (your own wallpapers are free).
        </p>
      </div>

      <h3 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">Transaction History</h3>

      {txLoading && transactions.length === 0 ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-16 bg-gray-100 dark:bg-gray-800 rounded-lg animate-pulse" />
          ))}
        </div>
      ) : transactions.length === 0 ? (
        <EmptyState message="No transactions yet." />
      ) : (
        <div className="space-y-2">
          {transactions.map((tx) => {
            const info = TX_LABELS[tx.tx_type] ?? { label: tx.tx_type, color: tx.amount > 0 ? 'text-green-600' : 'text-red-500' };
            return (
              <div
                key={tx.id}
                className="flex items-center justify-between px-4 py-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-100 dark:border-gray-700"
              >
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-800 dark:text-gray-200">{info.label}</p>
                  <p className="text-xs text-gray-400 mt-0.5">
                    {formatTime(tx.created_at)}
                    {tx.ref_id > 0 && (
                      <> · <Link to={`/wallpaper/${tx.ref_id}`} className="text-indigo-500 hover:underline">Wallpaper #{tx.ref_id}</Link></>
                    )}
                  </p>
                </div>
                <div className="text-right ml-4">
                  <p className={`text-sm font-bold ${info.color}`}>
                    {tx.amount > 0 ? '+' : ''}{tx.amount}
                  </p>
                  <p className="text-xs text-gray-400">Balance: {tx.balance}</p>
                </div>
              </div>
            );
          })}

          {txHasMore && (
            <div className="flex justify-center pt-4">
              <button
                onClick={() => loadTransactions(false)}
                disabled={txLoading}
                className="px-6 py-2 text-sm font-medium text-indigo-600 border border-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors disabled:opacity-50"
              >
                {txLoading ? 'Loading...' : 'Load More'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );

  return (
    <div className="px-6 py-6">
      <div className="flex items-center gap-5 mb-10">
        {user.avatar_url ? (
          <img src={user.avatar_url} alt="" className="w-20 h-20 rounded-full object-cover" />
        ) : (
          <div className="w-20 h-20 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center text-3xl font-bold">
            {(user.nickname || user.username).charAt(0).toUpperCase()}
          </div>
        )}
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
              {user.nickname || user.username}
            </h1>
            <span className="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-full bg-gradient-to-r from-amber-50 to-yellow-50 dark:from-amber-900/20 dark:to-yellow-900/20 border border-amber-200/60 dark:border-amber-700/40 shadow-sm">
              <span className="text-base">💰</span>
              <span className="text-sm font-bold bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{isOwnProfile ? (currentUser?.coins ?? 0) : (user.coins ?? 0)}</span>
            </span>
          </div>
          {user.bio && <p className="mt-1 text-gray-600 dark:text-gray-400">{user.bio}</p>}
        </div>
      </div>

      <div className="flex gap-1 mb-6 border-b border-gray-200 dark:border-gray-700 overflow-x-auto">
        {tabDefs
          .filter((t) => !t.ownerOnly || isOwnProfile)
          .map((t) => (
            <button
              key={t.key}
              onClick={() => handleTabChange(t.key)}
              className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                activeTab === t.key
                  ? 'border-indigo-600 text-indigo-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {t.key === 'coins' ? (
                <span className="flex items-center gap-1.5">💰 {t.label}</span>
              ) : (
                t.label
              )}
            </button>
          ))}
      </div>

      {activeTab === 'coins' ? (
        renderCoinsTab()
      ) : activeTab === 'collections' ? (
        <>
          {collections.length > 0 ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
              {collections.map((c) => (
                <Link
                  key={c.id}
                  to={`/collections/${c.id}`}
                  className="group block rounded-2xl overflow-hidden bg-white dark:bg-gray-800 shadow-sm hover:shadow-lg transition-all duration-300 border border-gray-100 dark:border-gray-700"
                >
                  <div className="aspect-video bg-gradient-to-br from-indigo-100 to-purple-100 dark:from-indigo-900/30 dark:to-purple-900/30 relative overflow-hidden">
                    {c.cover_url ? (
                      <img src={c.cover_url} alt="" className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <AiOutlinePicture size={48} className="text-indigo-200 dark:text-indigo-700" />
                      </div>
                    )}
                    <div className="absolute bottom-3 right-3 px-2.5 py-1 bg-black/50 backdrop-blur-sm text-white text-xs font-medium rounded-full">
                      {c.wallpaper_count} wallpapers
                    </div>
                  </div>
                  <div className="p-4">
                    <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2 group-hover:text-indigo-600 transition-colors">
                      {c.title}
                    </h3>
                    {c.description && (
                      <p className="text-sm text-gray-500 dark:text-gray-400 line-clamp-2 mb-3">{c.description}</p>
                    )}
                    <div className="flex items-center gap-4 text-xs text-gray-400">
                      <span className="flex items-center gap-1"><AiOutlineHeart size={14} />{c.like_count}</span>
                      <span className="flex items-center gap-1"><AiOutlineEye size={14} />{c.view_count}</span>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          ) : (
            <EmptyState message="No collections yet." />
          )}
        </>
      ) : (
        <>
          {tabLoading && !currentTab?.loaded ? (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 border-2 border-indigo-200 border-t-indigo-600 rounded-full animate-spin" />
            </div>
          ) : currentTab && currentTab.items.length > 0 ? (
            <WallpaperGrid
              wallpapers={currentTab.items}
              showStatus={activeTab === 'wallpapers' && isOwnProfile}
            />
          ) : currentTab?.loaded ? (
            <EmptyState message={`No ${activeTab} yet.`} />
          ) : null}

          {currentTab?.hasMore && (
            <div className="flex justify-center mt-8">
              <button
                onClick={loadMore}
                disabled={loadingMore}
                className="px-6 py-2.5 text-sm font-medium text-indigo-600 border border-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors duration-200 disabled:opacity-50"
              >
                {loadingMore ? (
                  <span className="flex items-center gap-2">
                    <div className="w-4 h-4 border-2 border-indigo-200 border-t-indigo-600 rounded-full animate-spin" />
                    Loading...
                  </span>
                ) : (
                  'Load More'
                )}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
