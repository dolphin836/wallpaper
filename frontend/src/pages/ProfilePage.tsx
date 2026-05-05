import { useState, useEffect, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import toast from 'react-hot-toast';
import type { User, Wallpaper } from '../types';
import { getUserProfile, getUserWallpapers } from '../api';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

export default function ProfilePage() {
  const { id } = useParams<{ id: string }>();
  const [user, setUser] = useState<User | null>(null);
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setWallpapers([]);
    setCursor(undefined);

    Promise.all([
      getUserProfile(Number(id)),
      getUserWallpapers(Number(id), { limit: 20 }),
    ])
      .then(([profileRes, wpRes]) => {
        setUser(profileRes.data.data);
        const { items, next_cursor, has_more } = wpRes.data.data;
        setWallpapers(items);
        setCursor(next_cursor);
        setHasMore(has_more);
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

      <WallpaperGrid wallpapers={wallpapers} />

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
    </div>
  );
}
