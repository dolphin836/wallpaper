import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { Collection } from '../types';
import { getCollections } from '../api';
import Spinner from '../components/Spinner';

export default function CollectionsPage() {
  const [collections, setCollections] = useState<Collection[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  useEffect(() => {
    setLoading(true);
    getCollections({ limit: 18 })
      .then((res) => {
        const { items, next_cursor, has_more } = res.data.data;
        setCollections(items);
        setCursor(next_cursor);
        setHasMore(has_more);
      })
      .catch(() => toast.error('Failed to load collections'))
      .finally(() => setLoading(false));
  }, []);

  const loadMore = useCallback(async () => {
    if (loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await getCollections({ cursor, limit: 18 });
      const { items, next_cursor, has_more } = res.data.data;
      setCollections((prev) => [...prev, ...items]);
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [cursor, loadingMore]);

  if (loading) {
    return <Spinner />;
  }

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Collections</h1>
      </div>

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

      {collections.length === 0 && !loading && (
        <div className="text-center py-20 text-gray-400">No collections yet.</div>
      )}

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
