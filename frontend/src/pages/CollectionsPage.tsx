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
          // Skeletons mirror the redesigned geometry: full-width 21:9
          // banner + golden-ratio mosaic cards, so the page doesn't
          // shift when the data lands.
          <>
            <div className="wx-card skeleton-card" style={{ aspectRatio: '21/9' }} />
            <div className="c2-grid mt-7">
              {Array.from({ length: 4 }).map((_, i) => (
                <div key={i} className="wx-card skeleton-card" style={{ aspectRatio: '1.618' }} />
              ))}
            </div>
          </>
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
          // Page 1 leads with the first collection as a full-width
          // editorial banner; the rest render as large golden-ratio
          // mosaic cards (docs/design-system.md, mirrors the Mac
          // collections list).
          <>
            {current === 1 && visible.length > 1 && (
              <CollectionHeroBanner collection={visible[0]} onTintsChange={applyTints} />
            )}
            <div className="c2-grid mt-7">
              {(current === 1 && visible.length > 1 ? visible.slice(1) : visible).map((c) => (
                <CollectionShowcaseCard key={c.id} collection={c} onTintsChange={applyTints} />
              ))}
            </div>
          </>
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

/* Shared hover handler: push up to three dominant colours from the
   collection's recent tiles into the page mesh. */
function collectionTints(c: Collection): string[] {
  const tints = (c.recent_tiles ?? [])
    .map((t) => t.dominant_color)
    .filter((s): s is string => Boolean(s))
    .slice(0, 3);
  if (tints.length === 0 && c.accent_color) tints.push(c.accent_color);
  return tints;
}

function coverSrc(c: Collection): string {
  const firstTile = c.recent_tiles?.[0];
  return firstTile?.preview_url || c.cover_url || firstTile?.thumb_url || '';
}

function countLabel(c: Collection, t: (k: string, o?: Record<string, unknown>) => string): string {
  return c.wallpaper_count === 1
    ? t('tile.wallpaperCountOne')
    : t('tile.wallpaperCount', { num: c.wallpaper_count });
}

/* Full-width 21:9 editorial banner for the leading collection. */
function CollectionHeroBanner({
  collection: c,
  onTintsChange,
}: {
  collection: Collection;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="wx-card block w2-cover no-underline"
      style={{ aspectRatio: '21/9', backgroundColor: c.recent_tiles?.[0]?.dominant_color || undefined }}
      onMouseEnter={() => { const tints = collectionTints(c); if (tints.length) onTintsChange?.(tints); }}
      onMouseLeave={() => onTintsChange?.(null)}
    >
      {coverSrc(c) && <img src={coverSrc(c)} alt={c.title} loading="eager" decoding="async" fetchPriority="high" />}
      <div className="wx-card-scrim" />
      {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
      <div className="c2-title-block" style={{ left: 24, bottom: 20 }}>
        <div className="kicker" style={{ color: 'rgba(255,255,255,0.85)' }}>
          {c.kind === 1 ? t('tile.kickerTheme') : t('tile.kickerCollection')}
        </div>
        <div className="display text-[24px] font-semibold leading-tight mt-1 truncate">{c.title}</div>
        <div className="mono text-[11px] tracking-[0.1em] mt-1 opacity-80">{countLabel(c, t)}</div>
      </div>
    </Link>
  );
}

/* Golden-ratio mosaic card: cover left 2/3 + two member tiles stacked
   right 1/3 with hairline seams — reads as "a set" at a glance. Title
   sits inside the card on a bottom scrim (mirrors the Mac
   CollectionShowcaseCard). */
function CollectionShowcaseCard({
  collection: c,
  onTintsChange,
}: {
  collection: Collection;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  const tiles = c.recent_tiles ?? [];
  const fallback = tiles[0]?.dominant_color || c.accent_color || '#999';
  const cell = (idx: number) => {
    const tile = tiles[idx];
    const src = tile?.thumb_url || tile?.preview_url || '';
    return src
      ? <img src={src} alt="" loading="lazy" decoding="async" />
      : <div style={{ position: 'absolute', inset: 0, background: tile?.dominant_color || fallback, opacity: 0.45 }} />;
  };
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="wx-card block no-underline"
      style={{ aspectRatio: '1.618' }}
      onMouseEnter={() => { const tints = collectionTints(c); if (tints.length) onTintsChange?.(tints); }}
      onMouseLeave={() => onTintsChange?.(null)}
    >
      <div className="c2-mosaic">
        <div className="c2-main">
          {coverSrc(c)
            ? <img src={coverSrc(c)} alt={c.title} loading="lazy" decoding="async" />
            : <div style={{ position: 'absolute', inset: 0, background: fallback, opacity: 0.45 }} />}
        </div>
        <div>{cell(1)}</div>
        <div>{cell(2)}</div>
      </div>
      <div className="wx-card-scrim" />
      {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
      <div className="c2-title-block">
        <div className="mono text-[9px] tracking-[0.18em] uppercase opacity-80">
          {c.kind === 1 ? t('tile.kickerTheme') : t('tile.kickerCollection')}
        </div>
        <div className="flex items-baseline gap-2.5 mt-0.5">
          <span className="text-[16px] font-semibold truncate">{c.title}</span>
          <span className="mono text-[10px] tracking-[0.08em] opacity-75 shrink-0">{countLabel(c, t)}</span>
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
