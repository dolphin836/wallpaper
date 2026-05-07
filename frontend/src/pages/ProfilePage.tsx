import { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection } from '../types';
import { getUserProfile, getUserWallpapers, getUserCollections, getMyFavorites, getMyLikes } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

type TabKey = 'wallpapers' | 'collections' | 'favorites' | 'likes';

interface WallpaperTab {
  items: Wallpaper[];
  cursor?: number;
  hasMore: boolean;
  loaded: boolean;
}

export default function ProfilePage() {
  const { id } = useParams<{ id: string }>();
  const { user: currentUser } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [activeTab, setActiveTab] = useState<TabKey>('wallpapers');

  const isOwnProfile = currentUser?.id === Number(id);

  const [tabs, setTabs] = useState<Record<string, WallpaperTab>>({
    wallpapers: { items: [], hasMore: false, loaded: false },
    favorites: { items: [], hasMore: false, loaded: false },
    likes: { items: [], hasMore: false, loaded: false },
  });

  const updateTab = (key: string, updates: Partial<WallpaperTab>) => {
    setTabs((prev) => ({ ...prev, [key]: { ...prev[key], ...updates } }));
  };

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setTabs({
      wallpapers: { items: [], hasMore: false, loaded: false },
      favorites: { items: [], hasMore: false, loaded: false },
      likes: { items: [], hasMore: false, loaded: false },
    });
    setActiveTab('wallpapers');

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
  }, [id]);

  const loadTabData = useCallback(async (key: 'favorites' | 'likes') => {
    if (tabs[key].loaded) return;
    const fetcher = key === 'favorites' ? getMyFavorites : getMyLikes;
    try {
      const res = await fetcher({ limit: 20 });
      const { items, next_cursor, has_more } = res.data.data;
      updateTab(key, { items, cursor: next_cursor, hasMore: has_more, loaded: true });
    } catch {
      toast.error('Failed to load data');
    }
  }, [tabs]);

  const handleTabChange = (tab: TabKey) => {
    setActiveTab(tab);
    if ((tab === 'favorites' || tab === 'likes') && !tabs[tab].loaded) {
      loadTabData(tab);
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
    { key: 'wallpapers', label: `Wallpapers`, ownerOnly: false },
    { key: 'collections', label: `Collections`, ownerOnly: false },
    { key: 'favorites', label: `Favorites`, ownerOnly: true },
    { key: 'likes', label: `Likes`, ownerOnly: true },
  ];

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
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
            <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-gradient-to-r from-amber-50 to-orange-50 dark:from-amber-900/20 dark:to-orange-900/20 border border-amber-200/60 dark:border-amber-700/40">
              <span className="text-sm">🪙</span>
              <span className="text-sm font-bold text-amber-600 dark:text-amber-400">{user.coins ?? 0}</span>
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
              {t.label}
            </button>
          ))}
      </div>

      {activeTab === 'collections' ? (
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
          {currentTab && currentTab.items.length > 0 ? (
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
