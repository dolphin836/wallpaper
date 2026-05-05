import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getMyFavorites } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';

export default function FavoritesPage() {
  const { isAuthenticated } = useAuthStore();
  const navigate = useNavigate();
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  useEffect(() => {
    if (!isAuthenticated) {
      navigate('/login');
      return;
    }
    setLoading(true);
    getMyFavorites({ limit: 20 })
      .then((res) => {
        const { items, next_cursor, has_more } = res.data.data;
        setWallpapers(items);
        setCursor(next_cursor);
        setHasMore(has_more);
      })
      .catch(() => toast.error('Failed to load favorites'))
      .finally(() => setLoading(false));
  }, [isAuthenticated, navigate]);

  const loadMore = useCallback(async () => {
    if (loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await getMyFavorites({ cursor, limit: 20 });
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => [...prev, ...items]);
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [cursor, loadingMore]);

  if (!isAuthenticated) return null;

  if (loading) {
    return <Spinner />;
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-8">My Favorites</h1>

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
