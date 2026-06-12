import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import toast from 'react-hot-toast';
import { AiOutlinePlus } from 'react-icons/ai';
import { Link } from 'react-router-dom';
import type { Collection } from '../types';
import { getCollections, createCollection } from '../api';
import { useAuthStore } from '../store/auth';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';
import Pagination from '../components/Pagination';

type Filter = 'all' | 'yours';

const PAGE_SIZE = 12;

export default function CollectionsPage() {
  const { t } = useTranslation('collections');
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
  const [error, setError] = useState(false);
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
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, [pages, cursors, filter, user, kind]);

  useEffect(() => { fetchPage(current); }, [current, fetchPage]);

  const visible = pages[current] || [];
  // Real page total from the server count. Falls back to 1 only while
  // the very first request is in flight.
  const total = serverTotal !== null ? Math.max(1, Math.ceil(serverTotal / PAGE_SIZE)) : 1;

  // Page-mesh palette is driven by whichever collection card the
  // cursor is hovering over — we read up to three dominant colours
  // from that collection's recent_tiles and stamp them as
  // --c-list-c1/c2/c3 on the page root. The CSS .c-list-mesh
  // radials read those vars, so the soft cloud behind the grid
  // tracks the card. On mouse-leave the vars are removed and the
  // mesh falls back to its default neutral triad.
  const rootRef = useRef<HTMLDivElement | null>(null);
  const applyTints = useCallback((tints: string[] | null) => {
    const root = rootRef.current;
    if (!root) return;
    if (!tints || tints.length === 0) {
      root.style.removeProperty('--c-list-c1');
      root.style.removeProperty('--c-list-c2');
      root.style.removeProperty('--c-list-c3');
      return;
    }
    const [c1, c2 = c1, c3 = c1] = tints;
    root.style.setProperty('--c-list-c1', c1);
    root.style.setProperty('--c-list-c2', c2);
    root.style.setProperty('--c-list-c3', c3);
  }, []);

  return (
    <div ref={rootRef} className="c-list min-h-full">
      <div className="c-list-mesh" aria-hidden />
      <PageMeta
        title={isThemes ? t('meta.titleThemes') : t('meta.title')}
        description={isThemes ? t('meta.descriptionThemes') : t('meta.description')}
      />

      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-10">
        <header className="c-list-head">
          <div>
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              {isThemes ? t('list.kickerThemes') : t('list.kicker')}
            </div>
            <h1 className="display text-[clamp(34px,4.2vw,56px)] leading-[1.02] mt-2 tracking-[-0.01em] text-ink">
              {isThemes
                ? <Trans i18nKey="list.headingThemes" ns="collections" components={[<em key="0" />]} />
                : <Trans i18nKey="list.heading" ns="collections" components={[<em key="0" />]} />}
            </h1>
            <p className="text-ink-2 mt-3 max-w-2xl text-[14px] leading-relaxed">
              {isThemes ? t('list.introThemes') : t('list.intro')}
            </p>
          </div>

          <div className="c-list-toolbar">
            <FilterChip active={filter === 'all'} onClick={() => setFilter('all')}>{t('list.filterAll')}</FilterChip>
            {isAuthenticated && (
              <FilterChip active={filter === 'yours'} onClick={() => setFilter('yours')}>{t('list.filterYours')}</FilterChip>
            )}
            {isAuthenticated && (
              <button
                onClick={() => setShowCreate(true)}
                className="c-list-new"
              >
                <AiOutlinePlus size={13} /> {t('list.newButton')}
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
        ) : error && visible.length === 0 ? (
          <ErrorState />
        ) : visible.length === 0 ? (
          <EmptyState
            title={filter === 'yours' ? t('list.emptyYoursTitle') : t('list.emptyTitle')}
            message={filter === 'yours' ? t('list.emptyYoursMessage') : t('list.emptyMessage')}
            actionLabel={isAuthenticated ? t('list.emptyAction') : undefined}
            onAction={isAuthenticated ? () => setShowCreate(true) : undefined}
          />
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-7">
            {visible.map((c) => (
              <CollectionTile key={c.id} collection={c} onTintsChange={applyTints} />
            ))}
          </div>
        )}

        <Pagination
          current={current}
          total={total}
          maxReachable={Math.max(1, ...Object.entries(cursors)
            .filter(([, v]) => v !== undefined)
            .map(([k]) => Number(k)))}
          onChange={setCurrent}
        />
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
function CollectionTile({
  collection: c,
  onTintsChange,
}: {
  collection: Collection;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  const accent = c.accent_color || 'var(--color-accent)';
  // Cover source priority:
  //   1. first recent_tile's preview_url (1600px wide, sharpest)
  //   2. collection.cover_url (may be a 400px thumb from legacy
  //      auto-backfill — only used when no tile is available)
  //   3. first recent_tile's thumb_url
  // The tile frame is rendered at ~480px square on lg grids
  // (960px on 2× Retina), so using a 400px thumb cropped + scaled
  // up reads visibly blurry. Preview wins whenever it exists.
  // Legacy stale .jpg cover_urls (cleaned up when the worker
  // switched to .webp) still get caught by the onError fallback.
  const firstTile = c.recent_tiles?.[0];
  const preferred = firstTile?.preview_url || c.cover_url || firstTile?.thumb_url || '';
  const fallbackSrc = firstTile?.thumb_url || '';
  const [src, setSrc] = useState(preferred);
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c-tile no-underline"
      style={{ '--c-accent': accent } as React.CSSProperties}
      onMouseEnter={() => {
        // Push up to three dominant colours from this collection's
        // recent tiles for the page-mesh radials. Drop accent_color
        // in as a fourth fallback so themed collections (kind=1)
        // always have at least one strong colour to paint with.
        const tints = (c.recent_tiles ?? [])
          .map((t) => t.dominant_color)
          .filter((s): s is string => Boolean(s))
          .slice(0, 3);
        if (tints.length === 0 && c.accent_color) tints.push(c.accent_color);
        if (tints.length > 0) onTintsChange?.(tints);
      }}
      onMouseLeave={() => onTintsChange?.(null)}
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
          <div className="c-tile-empty">{t('tile.noCover')}</div>
        )}
      </div>
      <div className="c-tile-caption">
        <div className="c-tile-kicker">
          {c.kind === 1 ? t('tile.kickerTheme') : t('tile.kickerCollection')}
          {!c.is_public && ` · ${t('tile.private')}`}
        </div>
        <div className="c-tile-title">{c.title}</div>
        <div className="c-tile-meta">
          {c.wallpaper_count === 1
            ? t('tile.wallpaperCountOne')
            : t('tile.wallpaperCount', { num: c.wallpaper_count })}
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
  const { t } = useTranslation('collections');
  const [title, setTitle] = useState('');
  const [creating, setCreating] = useState(false);

  const submit = async () => {
    const trimmed = title.trim();
    if (!trimmed || creating) return;
    setCreating(true);
    try {
      await createCollection({ title: trimmed });
      toast.success(t('create.success'));
      onCreated();
    } catch {
      toast.error(t('create.error'));
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
        <div className="mono text-[10px] tracking-[0.16em] uppercase text-muted mb-3">{t('create.kicker')}</div>
        <input
          autoFocus
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') submit(); if (e.key === 'Escape') onClose(); }}
          placeholder={t('create.placeholder')}
          maxLength={100}
          className="w-full px-3.5 py-3 bg-paper text-[14px] text-ink placeholder:text-muted outline-none rounded-lg"
          style={{ border: '1px solid var(--color-hair)' }}
        />
        <div className="flex justify-end gap-2 mt-3">
          <button
            onClick={onClose}
            className="px-3.5 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2 transition-colors"
          >{t('create.cancel')}</button>
          <button
            onClick={submit}
            disabled={!title.trim() || creating}
            className="px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50 transition-colors"
          >{creating ? t('create.creating') : t('create.create')}</button>
        </div>
      </div>
    </div>
  );
}
