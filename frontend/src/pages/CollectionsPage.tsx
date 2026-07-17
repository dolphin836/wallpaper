import { useState, useEffect, useCallback, useRef } from 'react';
import { Trans, useTranslation } from 'react-i18next';
import toast from 'react-hot-toast';
import { AiOutlinePlus } from 'react-icons/ai';
import { Link } from 'react-router-dom';
import type { Collection, CollectionTile } from '../types';
import { getCollections, createCollection } from '../api';
import { useAuthStore } from '../store/auth';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';
import Pagination from '../components/Pagination';

const PAGE_SIZE = 12;

export default function CollectionsPage() {
  const { t } = useTranslation('collections');
  const { isAuthenticated } = useAuthStore();

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
  const [showCreate, setShowCreate] = useState(false);

  const fetchPage = useCallback(async (page: number) => {
    if (pages[page]) return;
    const cursor = cursors[page];
    if (page > 1 && cursor === undefined) return;
    setLoading(true);
    try {
      const res = await getCollections({ cursor, limit: PAGE_SIZE });
      const items = res.data.data.items || [];
      const nextCursor = res.data.data.next_cursor;
      const hasMore = res.data.data.has_more;
      const total = res.data.data.total;
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
  }, [pages, cursors]);

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
        title={t('meta.titleThemes')}
        description={t('meta.descriptionThemes')}
      />

      <main className="c4-shell">
        <header className="c4-masthead">
          <div className="c4-masthead-copy">
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              {t('list.kickerThemes')}
            </div>
            <h1 className="display c4-masthead-title">
              <Trans i18nKey="list.headingThemes" ns="collections" components={[<em key="0" />]} />
            </h1>
            <p className="c4-masthead-intro">
              {t('list.introThemes')}
            </p>
          </div>

          <aside className="c4-catalogue-meta" aria-label={t('list.kickerThemes')}>
            <div className="c4-catalogue-count">
              {serverTotal !== null ? (
                <>
                  <strong>{String(serverTotal).padStart(2, '0')}</strong>
                  <span>{t('list.archiveCount', { num: serverTotal })}</span>
                </>
              ) : (
                <>
                  <span className="c4-count-skeleton skeleton-card" aria-hidden />
                  <span className="c4-count-label-skeleton skeleton-card" aria-hidden />
                </>
              )}
            </div>
            <span className="c4-page-label">
              {t('list.pageLabel', { current, total })}
            </span>
            {isAuthenticated && (
              <button
                onClick={() => setShowCreate(true)}
                className="c-list-new"
              >
                <AiOutlinePlus size={13} /> {t('list.newButton')}
              </button>
            )}
          </aside>
        </header>

        {loading && visible.length === 0 ? (
          <CollectionsSkeleton current={current} />
        ) : error && visible.length === 0 ? (
          <ErrorState />
        ) : visible.length === 0 ? (
          <EmptyState
            title={t('list.emptyTitle')}
            message={t('list.emptyMessage')}
            actionLabel={isAuthenticated ? t('list.emptyAction') : undefined}
            onAction={isAuthenticated ? () => setShowCreate(true) : undefined}
          />
        ) : (
          <div className="c4-index">
            {visible.map((c, index) => (
              <CollectionIndexCard
                key={c.id}
                collection={c}
                index={(current - 1) * PAGE_SIZE + index + 1}
                reverse={index % 2 === 1}
                eager={current === 1 && index === 0}
                onTintsChange={applyTints}
              />
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

function collectionCoverTiles(c: Collection): [
  CollectionTile | undefined,
  CollectionTile | undefined,
  CollectionTile | undefined,
] {
  const tiles = c.recent_tiles ?? [];
  let first = tiles[0];

  // Older or empty collections may only expose cover_url. Treat it as
  // a one-stage tile so the card still follows the same rendering path.
  if (!first && c.cover_url) {
    first = {
      thumb_url: c.cover_url,
      preview_url: c.cover_url,
      dominant_color: c.accent_color || '',
    };
  }

  // A collection cover always has three visual slots. When the API has
  // only one or two wallpapers, repeat the first one instead of leaving
  // a blank cell; this matches the product's cover composition contract.
  return [first, tiles[1] ?? first, tiles[2] ?? first];
}

function countLabel(c: Collection, t: (k: string, o?: Record<string, unknown>) => string): string {
  return c.wallpaper_count === 1
    ? t('tile.wallpaperCountOne')
    : t('tile.wallpaperCount', { num: c.wallpaper_count });
}

/* The loading view mirrors the same alternating index rows, copy rails,
   and three-slot cover geometry as the resolved catalogue. */
function CollectionsSkeleton({ current }: { current: number }) {
  return (
    <div className="c4-index" aria-hidden>
      {Array.from({ length: PAGE_SIZE }).map((_, i) => (
        <div
          key={`${current}-${i}`}
          className={`c4-entry c4-skeleton-entry${i % 2 === 1 ? ' is-reverse' : ''}`}
        >
          <div className="c4-entry-copy">
            <div className="c4-entry-kicker">
              <span className="c4-skeleton-line c4-skeleton-kicker skeleton-card" />
              <span className="c4-skeleton-line c4-skeleton-folio skeleton-card" />
            </div>
            <div>
              <span className="c4-skeleton-line c4-skeleton-title skeleton-card" />
              <span className="c4-skeleton-line c4-skeleton-title is-short skeleton-card" />
              <span className="c4-skeleton-line c4-skeleton-description skeleton-card" />
              <span className="c4-skeleton-line c4-skeleton-description is-short skeleton-card" />
            </div>
            <div className="c4-entry-meta">
              <span className="c4-skeleton-line c4-skeleton-count skeleton-card" />
              <span className="c4-skeleton-arrow skeleton-card" />
            </div>
          </div>
          <div className="c4-entry-media skeleton-card">
            <div className="c2-mosaic c4-skeleton-mosaic">
              <div className="c2-main" />
              <div />
              <div />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

type ImageLoadState = 'idle' | 'loaded' | 'failed';

/* One collection-cover slot, loaded in a strict sequence:
   dominant color (immediate from API) -> thumb -> preview. The preview
   element is not mounted until the thumb has settled, so the browser
   cannot start the larger request early. The loading beam remains over
   the slot until the final available stage succeeds or fails. */
function ProgressiveCollectionImage({
  tile,
  fallbackColor,
  alt = '',
  eager = false,
  allowPreview = true,
  onThumbSettled,
}: {
  tile?: CollectionTile;
  fallbackColor?: string;
  alt?: string;
  eager?: boolean;
  allowPreview?: boolean;
  onThumbSettled?: () => void;
}) {
  const thumbSrc = tile?.thumb_url || tile?.preview_url || '';
  const previewSrc = tile?.preview_url || thumbSrc;
  const hasPreviewStage = Boolean(thumbSrc && previewSrc && previewSrc !== thumbSrc);
  const [thumbState, setThumbState] = useState<ImageLoadState>('idle');
  const [previewState, setPreviewState] = useState<ImageLoadState>('idle');
  const thumbSettled = thumbState !== 'idle';
  const shouldLoadPreview = hasPreviewStage && thumbSettled && allowPreview;
  const finalSettled = !thumbSrc || (hasPreviewStage ? previewState !== 'idle' : thumbSettled);

  const settleThumb = useCallback((state: Exclude<ImageLoadState, 'idle'>) => {
    setThumbState(state);
    onThumbSettled?.();
  }, [onThumbSettled]);

  const syncThumbRef = useCallback((node: HTMLImageElement | null) => {
    if (!node?.complete) return;
    settleThumb(node.naturalWidth > 0 ? 'loaded' : 'failed');
  }, [settleThumb]);

  const syncPreviewRef = useCallback((node: HTMLImageElement | null) => {
    if (!node?.complete) return;
    setPreviewState(node.naturalWidth > 0 ? 'loaded' : 'failed');
  }, []);

  return (
    <div
      className="c2-progressive-image"
      style={{ backgroundColor: tile?.dominant_color || fallbackColor || 'var(--color-paper-2)' }}
    >
      {thumbSrc && (
        <img
          ref={syncThumbRef}
          src={thumbSrc}
          alt={alt}
          loading={eager ? 'eager' : 'lazy'}
          decoding="async"
          fetchPriority={eager ? 'high' : 'auto'}
          onLoad={() => settleThumb('loaded')}
          onError={() => settleThumb('failed')}
          className={`c2-progressive-img c2-progressive-thumb${thumbState === 'loaded' ? ' is-loaded' : ''}${hasPreviewStage && previewState !== 'failed' ? ' is-soft' : ''}`}
        />
      )}
      {shouldLoadPreview && (
        <img
          ref={syncPreviewRef}
          src={previewSrc}
          alt=""
          aria-hidden
          loading={eager ? 'eager' : 'lazy'}
          decoding="async"
          fetchPriority={eager ? 'high' : 'auto'}
          onLoad={() => setPreviewState('loaded')}
          onError={() => setPreviewState('failed')}
          className={`c2-progressive-img c2-progressive-preview${previewState === 'loaded' ? ' is-loaded' : ''}`}
        />
      )}
      {!finalSettled && <span className="card-loading-beam" aria-hidden />}
    </div>
  );
}

/* All three small images in a mosaic get a chance to settle before any
   large preview is mounted. This protects the small-first network order
   at the whole-card level, rather than only within each individual slot. */
function ProgressiveCollectionMosaic({
  tiles,
  fallbackColor,
  title,
  eager = false,
}: {
  tiles: [CollectionTile | undefined, CollectionTile | undefined, CollectionTile | undefined];
  fallbackColor: string;
  title: string;
  eager?: boolean;
}) {
  const [settledSlots, setSettledSlots] = useState<Set<number>>(() => new Set());
  const requiredThumbs = tiles.reduce((count, tile) => (
    tile?.thumb_url || tile?.preview_url ? count + 1 : count
  ), 0);
  const allowPreview = settledSlots.size >= requiredThumbs;

  const markThumbSettled = useCallback((index: number) => {
    setSettledSlots((current) => {
      if (current.has(index)) return current;
      const next = new Set(current);
      next.add(index);
      return next;
    });
  }, []);
  const markMainSettled = useCallback(() => markThumbSettled(0), [markThumbSettled]);
  const markSub1Settled = useCallback(() => markThumbSettled(1), [markThumbSettled]);
  const markSub2Settled = useCallback(() => markThumbSettled(2), [markThumbSettled]);

  const [main, sub1, sub2] = tiles;
  return (
    <div className="c2-mosaic">
      <div className="c2-main">
        <ProgressiveCollectionImage
          tile={main}
          fallbackColor={fallbackColor}
          alt={title}
          eager={eager}
          allowPreview={allowPreview}
          onThumbSettled={markMainSettled}
        />
      </div>
      <div>
        <ProgressiveCollectionImage
          tile={sub1}
          fallbackColor={fallbackColor}
          eager={eager}
          allowPreview={allowPreview}
          onThumbSettled={markSub1Settled}
        />
      </div>
      <div>
        <ProgressiveCollectionImage
          tile={sub2}
          fallbackColor={fallbackColor}
          eager={eager}
          allowPreview={allowPreview}
          onThumbSettled={markSub2Settled}
        />
      </div>
    </div>
  );
}

/* One catalogue row: a restrained copy rail paired with the three-image
   mood board. Alternating the two columns creates rhythm without turning
   the page into a wall of unrelated card shapes. */
function CollectionIndexCard({
  collection: c,
  index,
  reverse,
  eager,
  onTintsChange,
}: {
  collection: Collection;
  index: number;
  reverse: boolean;
  eager: boolean;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  const [main, sub1, sub2] = collectionCoverTiles(c);
  const fallback = main?.dominant_color || c.accent_color || 'var(--color-paper-2)';
  const mosaicKey = [main, sub1, sub2]
    .map((tile) => `${tile?.thumb_url || ''}|${tile?.preview_url || ''}`)
    .join('||');
  const applyCollectionTints = () => {
    const tints = collectionTints(c);
    if (tints.length) onTintsChange?.(tints);
  };

  return (
    <Link
      to={`/collections/${c.slug}`}
      className={`c4-entry no-underline${reverse ? ' is-reverse' : ''}`}
      style={{ '--c4-accent': c.accent_color || fallback } as React.CSSProperties}
      onMouseEnter={applyCollectionTints}
      onMouseLeave={() => onTintsChange?.(null)}
      onFocus={applyCollectionTints}
      onBlur={() => onTintsChange?.(null)}
    >
      <div className="c4-entry-copy">
        <div className="c4-entry-kicker">
          <span>{c.kind === 1 ? t('tile.weeklyRecommendation') : t('tile.kickerCollection')}</span>
          <span aria-hidden>COL—{String(index).padStart(2, '0')}</span>
        </div>
        <div className="c4-entry-body">
          <h2 className="display c4-entry-title" title={c.title}>{c.title}</h2>
          {c.description && <p className="c4-entry-description">{c.description}</p>}
        </div>
        <div className="c4-entry-meta">
          <span>{countLabel(c, t)}</span>
          <span className="c4-entry-open" aria-hidden>↗</span>
        </div>
      </div>
      <div className="c4-entry-media">
        <ProgressiveCollectionMosaic
          key={mosaicKey}
          tiles={[main, sub1, sub2]}
          fallbackColor={fallback}
          title={c.title}
          eager={eager}
        />
        {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
        <span className="c4-media-folio" aria-hidden>{String(index).padStart(2, '0')}</span>
      </div>
    </Link>
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
