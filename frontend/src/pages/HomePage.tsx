import { useState, useEffect, useCallback } from 'react';
import { AiOutlineSearch } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { Wallpaper } from '../types';
import { getWallpapers } from '../api';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';

export default function HomePage() {
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [sort, setSort] = useState('latest');
  const [search, setSearch] = useState('');
  const [searchInput, setSearchInput] = useState('');
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  const fetchWallpapers = useCallback(async (reset: boolean) => {
    const setter = reset ? setLoading : setLoadingMore;
    setter(true);
    try {
      const res = await getWallpapers({
        cursor: reset ? undefined : cursor,
        limit: 20,
        sort,
        search: search || undefined,
      });
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => (reset ? items : [...prev, ...items]));
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load wallpapers');
    } finally {
      setter(false);
    }
  }, [cursor, sort, search]);

  useEffect(() => {
    fetchWallpapers(true);
  }, [sort, search]);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    setSearch(searchInput);
  };

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 mb-6">
        <form onSubmit={handleSearch} className="relative w-full sm:w-80">
          <AiOutlineSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={18} />
          <input
            type="text"
            placeholder="Search wallpapers..."
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            className="w-full pl-10 pr-4 py-2 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
          />
        </form>
        <select
          value={sort}
          onChange={(e) => setSort(e.target.value)}
          className="px-3 py-2 text-sm border border-gray-300 rounded-lg bg-white focus:outline-none focus:ring-2 focus:ring-indigo-500"
        >
          <option value="latest">Latest</option>
          <option value="popular">Popular</option>
        </select>
      </div>

      {loading ? (
        <Spinner />
      ) : (
        <>
          <WallpaperGrid wallpapers={wallpapers} />
          {hasMore && (
            <div className="flex justify-center mt-8">
              <button
                onClick={() => fetchWallpapers(false)}
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
