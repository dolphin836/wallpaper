import { useState, useEffect, useCallback } from 'react';
import toast from 'react-hot-toast';
import { AiOutlinePlus } from 'react-icons/ai';
import type { Collection } from '../types';
import { getCollections, createCollection } from '../api';
import { useAuthStore } from '../store/auth';
import PageMeta from '../components/PageMeta';
import CollectionCard from '../components/CollectionCard';
import Pagination from '../components/Pagination';

type Filter = 'all' | 'yours';

const PAGE_SIZE = 12;

export default function CollectionsPage() {
  const { isAuthenticated, user } = useAuthStore();

  // Paginated cursor walk — collect into pages so the editorial Pagination
  // can do prev/next moves. We discover total at the end (when has_more
  // flips false) and cache each page once fetched.
  const [pages, setPages] = useState<Record<number, Collection[]>>({});
  const [cursors, setCursors] = useState<Record<number, number | undefined>>({ 1: undefined });
  const [hasMoreUpTo, setHasMoreUpTo] = useState<number | null>(null); // last page that's confirmed not the end
  const [knownTotalPages, setKnownTotalPages] = useState<number | null>(null);
  const [current, setCurrent] = useState(1);
  const [loading, setLoading] = useState(false);
  const [filter, setFilter] = useState<Filter>('all');
  const [showCreate, setShowCreate] = useState(false);

  // Reset cache when the filter changes so the next fetch starts from page 1.
  useEffect(() => {
    setPages({});
    setCursors({ 1: undefined });
    setHasMoreUpTo(null);
    setKnownTotalPages(null);
    setCurrent(1);
  }, [filter]);

  const fetchPage = useCallback(async (page: number) => {
    if (pages[page]) return;
    const cursor = cursors[page];
    if (page > 1 && cursor === undefined) return; // need previous page first
    setLoading(true);
    try {
      const res = await getCollections({ cursor, limit: PAGE_SIZE });
      let items = res.data.data.items || [];
      const nextCursor = res.data.data.next_cursor;
      const hasMore = res.data.data.has_more;
      if (filter === 'yours' && user) {
        items = items.filter((c) => c.user_id === user.id);
      }
      setPages((prev) => ({ ...prev, [page]: items }));
      if (hasMore && nextCursor) {
        setCursors((prev) => ({ ...prev, [page + 1]: nextCursor }));
        setHasMoreUpTo(page);
      } else {
        setKnownTotalPages(page);
      }
    } catch {
      toast.error('Failed to load collections');
    } finally {
      setLoading(false);
    }
  }, [pages, cursors, filter, user]);

  useEffect(() => { fetchPage(current); }, [current, fetchPage]);

  const visible = pages[current] || [];
  // Total pages reveal themselves progressively; until proven otherwise
  // assume there's at least one more page after the last one we've seen.
  const total = knownTotalPages ?? (hasMoreUpTo ? hasMoreUpTo + 1 : 1);

  return (
    <div className="bg-paper-2 min-h-full">
      <PageMeta
        title="Collections"
        description="Curated wallpaper selections from the community on Wallpaper Exchange."
      />

      <div className="px-6 sm:px-10 pt-7">
        {/* Header */}
        <div className="flex items-end justify-between gap-6 flex-wrap mb-6">
          <div>
            <div className="kicker text-muted">Collections{knownTotalPages !== null ? ` · ${visible.length === 0 && current === 1 ? 0 : '∞'}` : ''}</div>
            <h1 className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-ink">
              Curated <span className="italic-d">selections.</span>
            </h1>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <FilterChip active={filter === 'all'} onClick={() => setFilter('all')}>All</FilterChip>
            {isAuthenticated && (
              <FilterChip active={filter === 'yours'} onClick={() => setFilter('yours')}>Yours</FilterChip>
            )}
            {isAuthenticated && (
              <>
                <div className="w-px h-[22px] bg-hair mx-1.5" />
                <button
                  onClick={() => setShowCreate(true)}
                  className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium hover:bg-ink-2 transition-colors"
                >
                  <AiOutlinePlus size={13} /> New collection
                </button>
              </>
            )}
          </div>
        </div>

        {/* Grid */}
        {loading && visible.length === 0 ? (
          <SkeletonGrid />
        ) : visible.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">
            {filter === 'yours' ? "You haven't created any collections yet." : 'No collections yet.'}
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
            {visible.map((c) => (
              <CollectionCard key={c.id} collection={c} />
            ))}
          </div>
        )}

        <Pagination current={current} total={total} onChange={setCurrent} />
      </div>

      {showCreate && (
        <NewCollectionModal
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false);
            // Bust the cache and re-fetch page 1.
            setPages({});
            setCursors({ 1: undefined });
            setHasMoreUpTo(null);
            setKnownTotalPages(null);
            setCurrent(1);
          }}
        />
      )}
    </div>
  );
}

function FilterChip({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`px-3.5 py-1.5 rounded-full text-[12px] font-medium transition-colors ${
        active
          ? 'bg-ink text-paper border border-ink'
          : 'bg-paper text-ink border border-hair hover:bg-paper-2 hover:border-ink-2'
      }`}
    >
      {children}
    </button>
  );
}

function SkeletonGrid() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
      {Array.from({ length: 8 }).map((_, i) => (
        <div key={i} className="flex flex-col gap-3">
          <div className="aspect-[4/3] bg-paper-3 border border-hair skeleton-card" style={{ animationDelay: `${i * 80}ms` }} />
          <div className="h-4 w-2/3 bg-paper-3 skeleton-card" />
        </div>
      ))}
    </div>
  );
}

function NewCollectionModal({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) {
  const [title, setTitle] = useState('');
  const [creating, setCreating] = useState(false);

  const submit = async () => {
    const t = title.trim();
    if (!t || creating) return;
    setCreating(true);
    try {
      await createCollection({ title: t });
      toast.success('Collection created');
      onCreated();
    } catch {
      toast.error('Failed to create collection');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-[60] flex items-start justify-center pt-[20vh] px-4"
      style={{ background: 'rgba(15,12,8,0.55)' }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-paper border border-ink w-full max-w-[360px] p-5"
        style={{ boxShadow: '0 16px 40px rgba(0,0,0,0.18)' }}
      >
        <div className="kicker text-muted mb-3">New collection</div>
        <input
          autoFocus
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') submit(); if (e.key === 'Escape') onClose(); }}
          placeholder="Name your collection"
          maxLength={100}
          className="w-full px-3.5 py-3 bg-paper text-[14px] text-ink placeholder:text-muted outline-none rounded"
          style={{ border: '1px solid var(--color-hair)' }}
        />
        <div className="flex justify-end gap-2 mt-3">
          <button
            onClick={onClose}
            className="px-3.5 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2 transition-colors"
          >Cancel</button>
          <button
            onClick={submit}
            disabled={!title.trim() || creating}
            className="px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50 transition-colors"
          >{creating ? 'Creating…' : 'Create'}</button>
        </div>
      </div>
    </div>
  );
}
