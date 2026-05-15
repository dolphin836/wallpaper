import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import type { Collection } from '../types';
import { getCollections } from '../api';
import Spinner from '../components/Spinner';
import PageMeta from '../components/PageMeta';
import CoverImage from '../components/CoverImage';

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

  return (
    <div className="px-6 py-8 max-w-[1200px] mx-auto w-full">
      <PageMeta
        title="Collections"
        description="Browse community-curated wallpaper collections — themed sets of HD and 4K wallpapers grouped by mood, color, and platform."
      />

      {/* Page header */}
      <div className="flex flex-col gap-1.5 mb-8 pb-6 border-b border-ws-border dark:border-white/5">
        <h1 className="text-[28px] sm:text-[32px] font-bold tracking-tight text-slate-900 dark:text-white leading-tight">
          Curated Collections
        </h1>
        <p className="text-sm sm:text-base text-ws-muted dark:text-ws-dark-muted">
          Thematic groups of high-fidelity digital art.
        </p>
      </div>

      {loading && collections.length === 0 ? (
        <Spinner />
      ) : collections.length === 0 ? (
        <div className="text-center py-20 text-ws-muted dark:text-ws-dark-muted">No collections yet.</div>
      ) : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-8">
            {collections.map((c) => (
              <CollectionCard key={c.id} c={c} />
            ))}
          </div>

          {hasMore && (
            <div className="flex justify-center mt-10">
              <button
                onClick={loadMore}
                disabled={loadingMore}
                className="px-6 py-2.5 text-sm font-semibold text-ws-purple border border-ws-purple rounded-full hover:bg-ws-purple hover:text-white transition-colors duration-200 disabled:opacity-50"
              >
                {loadingMore ? (
                  <span className="flex items-center gap-2">
                    <div className="w-4 h-4 border-2 border-ws-purple-light border-t-ws-purple rounded-full animate-spin" />
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

function CollectionCard({ c }: { c: Collection }) {
  // Build the three preview slots. We prefer the explicit recent_thumbs
  // array; if it's missing or short, the cover_url fills the hero slot and
  // empty trailing slots fall through to placeholder tint.
  const thumbs = c.recent_thumbs ?? [];
  const hero = thumbs[0] || c.cover_url || '';
  const sideTop = thumbs[1] || '';
  const sideBottom = thumbs[2] || '';

  return (
    <Link
      to={`/collections/${c.slug}`}
      className="group flex flex-col gap-4 cursor-pointer"
    >
      {/* Mosaic preview: 2/3 hero on the left, two stacked thumbs on the
          right. aspect-video controls the slot size — children are absolute
          inside relative containers so object-cover crops cleanly and the
          card never stretches or distorts the source images. */}
      <div className="aspect-video w-full rounded-xl overflow-hidden flex gap-1 bg-ws-purple-light dark:bg-purple-900/20">
        <div className="w-2/3 relative overflow-hidden">
          <CoverImage
            src={hero}
            alt={c.title}
            className="transition-transform duration-500 ease-out group-hover:scale-105"
          />
        </div>
        <div className="w-1/3 flex flex-col gap-1">
          <div className="flex-1 relative overflow-hidden">
            <CoverImage src={sideTop} alt="" />
          </div>
          <div className="flex-1 relative overflow-hidden">
            <CoverImage src={sideBottom} alt="" />
          </div>
        </div>
      </div>

      <div>
        <h3 className="text-lg font-bold text-slate-900 dark:text-white group-hover:text-ws-purple transition-colors">
          {c.title}
        </h3>
        <p className="text-sm text-ws-muted dark:text-ws-dark-muted mt-0.5">
          {c.wallpaper_count} {c.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
        </p>
      </div>
    </Link>
  );
}
