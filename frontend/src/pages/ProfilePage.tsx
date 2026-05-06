import { useState, useEffect, useCallback } from 'react';
import { useParams, Link } from 'react-router-dom';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection } from '../types';
import { getUserProfile, getUserWallpapers, getUserCollections } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

export default function ProfilePage() {
  const { id } = useParams<{ id: string }>();
  const { user: currentUser } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [collections, setCollections] = useState<Collection[]>([]);
  const [activeTab, setActiveTab] = useState<'wallpapers' | 'collections'>('wallpapers');

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setWallpapers([]);
    setCursor(undefined);

    Promise.all([
      getUserProfile(Number(id)),
      getUserWallpapers(Number(id), { limit: 20 }),
      getUserCollections(Number(id), { limit: 50 }),
    ])
      .then(([profileRes, wpRes, colRes]) => {
        setUser(profileRes.data.data);
        const { items, next_cursor, has_more } = wpRes.data.data;
        setWallpapers(items);
        setCursor(next_cursor);
        setHasMore(has_more);
        setCollections(colRes.data.data?.items || []);
      })
      .catch(() => toast.error('Failed to load profile'))
      .finally(() => setLoading(false));
  }, [id]);

  const loadMore = useCallback(async () => {
    if (!id || loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await getUserWallpapers(Number(id), { cursor, limit: 20 });
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => [...prev, ...items]);
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [id, cursor, loadingMore]);

  if (loading) {
    return <Spinner />;
  }

  if (!user) {
    return <EmptyState message="User not found." />;
  }

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
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
            {user.nickname || user.username}
          </h1>
          {user.bio && <p className="mt-1 text-gray-600 dark:text-gray-400">{user.bio}</p>}
        </div>
      </div>

      <div className="flex gap-1 mb-6 border-b border-gray-200 dark:border-gray-700">
        <button
          onClick={() => setActiveTab('wallpapers')}
          className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
            activeTab === 'wallpapers'
              ? 'border-indigo-600 text-indigo-600'
              : 'border-transparent text-gray-500 hover:text-gray-700'
          }`}
        >
          Wallpapers ({wallpapers.length}{hasMore ? '+' : ''})
        </button>
        <button
          onClick={() => setActiveTab('collections')}
          className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors ${
            activeTab === 'collections'
              ? 'border-indigo-600 text-indigo-600'
              : 'border-transparent text-gray-500 hover:text-gray-700'
          }`}
        >
          Collections ({collections.length})
        </button>
      </div>

      {activeTab === 'wallpapers' ? (
        <>
          <WallpaperGrid wallpapers={wallpapers} showStatus={currentUser?.id === Number(id)} />
          {hasMore && (
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
      ) : (
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
      )}
    </div>
  );
}
