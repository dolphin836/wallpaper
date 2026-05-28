import { useState, useEffect, useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';
import toast from 'react-hot-toast';
import { AiOutlinePlus } from 'react-icons/ai';
import { Link } from 'react-router-dom';
import type { Collection } from '../types';
import { getCollections, createCollection } from '../api';
import { useAuthStore } from '../store/auth';
import PageMeta from '../components/PageMeta';
import Pagination from '../components/Pagination';

type Filter = 'all' | 'yours';

const PAGE_SIZE = 12;

export default function CollectionsPage() {
  const { isAuthenticated, user } = useAuthStore();
  const [searchParams] = useSearchParams();
  // ?kind=1 limits to editor themes. Anything non-numeric falls through
  // as "no filter" so junk values don't 400 the API.
  const kindParam = searchParams.get('kind');
  const kind = kindParam !== null && /^\d+$/.test(kindParam) ? Number(kindParam) : undefined;
  const isThemes = kind === 1;

  const [pages, setPages] = useState<Record<number, Collection[]>>({});
  const [cursors, setCursors] = useState<Record<number, number | undefined>>({ 1: undefined });
  // Total page count comes back on the first response (server returns
  // .total). That lets the Pagination control show the real ceiling
  // (e.g. "1 2 3 … 12") from the very first paint instead of
  // discovering pages cursor-by-cursor and showing "1 2" → "1 2 3".
  const [serverTotal, setServerTotal] = useState<number | null>(null);
  const [current, setCurrent] = useState(1);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<Filter>('all');
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => {
    setPages({});
    setCursors({ 1: undefined });
    setServerTotal(null);
    setCurrent(1);
  }, [filter, kind]);

  const fetchPage = useCallback(async (page: number) => {
    if (pages[page]) return;
    const cursor = cursors[page];
    if (page > 1 && cursor === undefined) return;
    setLoading(true);
    try {
      const res = await getCollections({ cursor, limit: PAGE_SIZE, kind });
      let items = res.data.data.items || [];
      const nextCursor = res.data.data.next_cursor;
      const hasMore = res.data.data.has_more;
      const total = res.data.data.total;
      if (filter === 'yours' && user) {
        items = items.filter((c) => c.user_id === user.id);
      }
      setPages((prev) => ({ ...prev, [page]: items }));
      if (hasMore && nextCursor) {
        setCursors((prev) => ({ ...prev, [page + 1]: nextCursor }));
      }
      if (typeof total === 'number') {
        setServerTotal(total);
      }
    } catch {
      toast.error('Failed to load collections');
    } finally {
      setLoading(false);
    }
  }, [pages, cursors, filter, user, kind]);

  useEffect(() => { fetchPage(current); }, [current, fetchPage]);

  const visible = pages[current] || [];
  // Real page total from the server count. Falls back to 1 only while
  // the very first request is in flight.
  const total = serverTotal !== null ? Math.max(1, Math.ceil(serverTotal / PAGE_SIZE)) : 1;

  return (
    <div className="c-list min-h-full">
      <div className="c-list-mesh" aria-hidden />
      <PageMeta
        title={isThemes ? 'Editor Themes' : 'Collections'}
        description={isThemes
          ? 'Every editor-curated weekly theme collection on Wallpaper Exchange.'
          : 'Curated wallpaper selections from the community on Wallpaper Exchange.'}
      />

      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-10">
        <header className="c-list-head">
          <div>
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              {isThemes ? 'Editor themes' : 'The Library'}
            </div>
            <h1 className="display text-[clamp(34px,4.2vw,56px)] leading-[1.02] mt-2 tracking-[-0.01em] text-ink">
              {isThemes
                ? <>One theme, <em>every week.</em></>
                : <>Crates, <em>curated.</em></>}
            </h1>
            <p className="text-ink-2 mt-3 max-w-2xl text-[14px] leading-relaxed">
              {isThemes
                ? 'Weekly editor-picked themes. Each one bundles wallpapers around a mood, a place, or a moment.'
                : 'Themed sets put together by the community and the editors. Each collection has its own colour, voice, and pace — like a small record.'}
            </p>
          </div>

          <div className="c-list-toolbar">
            <FilterChip active={filter === 'all'} onClick={() => setFilter('all')}>All</FilterChip>
            {isAuthenticated && (
              <FilterChip active={filter === 'yours'} onClick={() => setFilter('yours')}>Yours</FilterChip>
            )}
            {isAuthenticated && (
              <button
                onClick={() => setShowCreate(true)}
                className="c-list-new"
              >
                <AiOutlinePlus size={13} /> New
              </button>
            )}
          </div>
        </header>

        {loading && visible.length === 0 ? (
          // 12 placeholders = 3 full rows at lg (4-col). Each card
          // mirrors the real CollectionTile geometry: 1:1 cover +
          // mono kicker bar + title bar + meta bar, so the page
          // doesn't shift when the data lands.
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-7">
            {Array.from({ length: 12 }).map((_, i) => (
              <div key={i} className="c-tile-skel">
                <div className="c-tile-skel-cover skeleton-card" />
                <div className="c-tile-skel-cap">
                  <div className="c-tile-skel-kicker skeleton-card" />
                  <div className="c-tile-skel-title skeleton-card" />
                  <div className="c-tile-skel-meta skeleton-card" />
                </div>
              </div>
            ))}
          </div>
        ) : visible.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">
            {filter === 'yours' ? "You haven't created any collections yet." : 'No collections yet.'}
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-7">
            {visible.map((c) => (
              <CollectionTile key={c.id} collection={c} />
            ))}
          </div>
        )}

        <Pagination current={current} total={total} onChange={setCurrent} />
      </main>

      {showCreate && (
        <NewCollectionModal
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false);
            setPages({});
            setCursors({ 1: undefined });
            setServerTotal(null);
            setCurrent(1);
          }}
        />
      )}
    </div>
  );
}

/* New collection tile — stacked-paper aesthetic. Single 1:1 cover
   with multi-layer box-shadow rendering paper layers beneath
   (accent-tinted via --c-accent from the collection). Caption block
   below: mono kicker · display title · mono meta. Distinct from the
   old 3-photo composition; reads as "an album on a shelf" instead
   of "a mosaic preview". */
function CollectionTile({ collection: c }: { collection: Collection }) {
  const accent = c.accent_color || 'var(--color-accent)';
  // Cover fallback chain: cover_url → first recent_tile's preview/
  // thumb → empty state. Some legacy collections still carry a
  // stale cover_url pointing at the old .jpg objects that got
  // cleaned up when the worker switched to .webp; the onError
  // handler silently swaps the src to a fresh tile so the user
  // sees an image instead of a broken-image placeholder.
  const firstTile = c.recent_tiles?.[0];
  const fallbackSrc = firstTile?.preview_url || firstTile?.thumb_url || '';
  const [src, setSrc] = useState(c.cover_url || fallbackSrc);
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c-tile no-underline"
      style={{ '--c-accent': accent } as React.CSSProperties}
    >
      <div className="c-tile-frame">
        {src ? (
          <img
            src={src}
            alt={c.title}
            loading="lazy"
            onError={() => {
              if (fallbackSrc && src !== fallbackSrc) setSrc(fallbackSrc);
              else setSrc('');
            }}
          />
        ) : (
          <div className="c-tile-empty">No cover yet</div>
        )}
        <span className="c-tile-accent-dot" aria-hidden />
      </div>
      <div className="c-tile-caption">
        <div className="c-tile-kicker">
          {c.kind === 1 ? 'Editor Theme' : 'Collection'}
          {!c.is_public && ' · Private'}
        </div>
        <div className="c-tile-title">{c.title}</div>
        <div className="c-tile-meta">
          {c.wallpaper_count} {c.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
        </div>
      </div>
    </Link>
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
        className="bg-paper border border-ink w-full max-w-[360px] p-5 rounded-xl"
        style={{ boxShadow: '0 16px 40px rgba(0,0,0,0.18)' }}
      >
        <div className="mono text-[10px] tracking-[0.16em] uppercase text-muted mb-3">New collection</div>
        <input
          autoFocus
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') submit(); if (e.key === 'Escape') onClose(); }}
          placeholder="Name your collection"
          maxLength={100}
          className="w-full px-3.5 py-3 bg-paper text-[14px] text-ink placeholder:text-muted outline-none rounded-lg"
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
