import { useState, useEffect, useCallback } from 'react';
import { Trans, useTranslation } from 'react-i18next';
import toast from 'react-hot-toast';
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

  return (
    <div className="c-list min-h-full">
      <PageMeta
        title={t('meta.titleThemes')}
        description={t('meta.descriptionThemes')}
      />

      <main className="c5-shell">
        <header className="c5-header">
          <div className="c5-header-copy">
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              {t('list.kickerThemes')}
            </div>
            <h1 className="display c5-header-title">
              <Trans i18nKey="list.headingThemes" ns="collections" components={[<em key="0" />]} />
            </h1>
            <p className="c5-header-intro">
              {t('list.introThemes')}
            </p>
          </div>

          <aside className="c5-summary" aria-label={t('list.kickerThemes')}>
            <div className="c5-count">
              {serverTotal !== null ? (
                <>
                  <strong>{String(serverTotal).padStart(2, '0')}</strong>
                  <span>{t('list.archiveCount', { num: serverTotal })}</span>
                </>
              ) : (
                <>
                  <span className="c5-count-number-skeleton skeleton-card" aria-hidden />
                  <span className="c5-count-label-skeleton skeleton-card" aria-hidden />
                </>
              )}
            </div>
            <span className="c5-page-label">
              {t('list.pageLabel', { current, total })}
            </span>
            {isAuthenticated && (
              <button
                onClick={() => setShowCreate(true)}
                className="c-list-new"
              >
                <span aria-hidden>+</span> {t('list.newButton')}
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
          <div className="c5-list">
            {visible.map((c, index) => (
              <CollectionListCard
                key={c.id}
                collection={c}
                index={(current - 1) * PAGE_SIZE + index + 1}
                eager={current === 1 && index === 0}
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

function collectionCoverTiles(c: Collection): Array<CollectionTile | undefined> {
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

  // Keep the card quiet: one image is the default cover. A second recent
  // image may form a narrow supporting panel, but we never manufacture
  // extra slots by repeating the first wallpaper.
  return tiles[1] ? [first, tiles[1]] : [first];
}

function countLabel(c: Collection, t: (k: string, o?: Record<string, unknown>) => string): string {
  return c.wallpaper_count === 1
    ? t('tile.wallpaperCountOne')
    : t('tile.wallpaperCount', { num: c.wallpaper_count });
}

/* The loading view mirrors the resolved horizontal card list exactly. */
function CollectionsSkeleton({ current }: { current: number }) {
  return (
    <div className="c5-list" aria-hidden>
      {Array.from({ length: PAGE_SIZE }).map((_, i) => (
        <div
          key={`${current}-${i}`}
          className="c5-card c5-skeleton-card"
        >
          <div className="c5-media skeleton-card" />
          <div className="c5-copy">
            <div className="c5-eyebrow">
              <span className="c5-skeleton-line c5-skeleton-source skeleton-card" />
              <span className="c5-skeleton-line c5-skeleton-folio skeleton-card" />
            </div>
            <div className="c5-body">
              <span className="c5-skeleton-line c5-skeleton-title skeleton-card" />
              <span className="c5-skeleton-line c5-skeleton-description skeleton-card" />
              <span className="c5-skeleton-line c5-skeleton-description is-short skeleton-card" />
            </div>
            <div className="c5-meta">
              <span className="c5-skeleton-line c5-skeleton-count skeleton-card" />
            </div>
          </div>
          <span className="c5-skeleton-arrow skeleton-card" />
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

/* Every small image settles before a large preview is mounted, preserving
   the existing dominant colour -> thumb -> preview network order. */
function ProgressiveCollectionCover({
  tiles,
  fallbackColor,
  title,
  eager = false,
}: {
  tiles: Array<CollectionTile | undefined>;
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

  return (
    <div className={`c5-cover-layout${tiles.length > 1 ? ' is-duo' : ' is-single'}`}>
      {tiles.map((tile, index) => (
        <ProgressiveCollectionCoverSlot
          key={`${tile?.thumb_url || tile?.preview_url || 'empty'}-${index}`}
          tile={tile}
          index={index}
          fallbackColor={fallbackColor}
          title={title}
          eager={eager}
          allowPreview={allowPreview}
          onThumbSettled={markThumbSettled}
        />
      ))}
    </div>
  );
}

function ProgressiveCollectionCoverSlot({
  tile,
  index,
  fallbackColor,
  title,
  eager,
  allowPreview,
  onThumbSettled,
}: {
  tile?: CollectionTile;
  index: number;
  fallbackColor: string;
  title: string;
  eager: boolean;
  allowPreview: boolean;
  onThumbSettled: (index: number) => void;
}) {
  const handleThumbSettled = useCallback(() => onThumbSettled(index), [index, onThumbSettled]);

  return (
    <div>
      <ProgressiveCollectionImage
        tile={tile}
        fallbackColor={fallbackColor}
        alt={index === 0 ? title : ''}
        eager={eager}
        allowPreview={allowPreview}
        onThumbSettled={handleThumbSettled}
      />
    </div>
  );
}

/* A consistent horizontal card list. The image remains the lead, while
   metadata stays in one predictable reading path on every row. */
function CollectionListCard({
  collection: c,
  index,
  eager,
}: {
  collection: Collection;
  index: number;
  eager: boolean;
}) {
  const { t } = useTranslation('collections');
  const tiles = collectionCoverTiles(c);
  const main = tiles[0];
  const fallback = main?.dominant_color || c.accent_color || 'var(--color-paper-2)';
  const coverKey = tiles
    .map((tile) => `${tile?.thumb_url || ''}|${tile?.preview_url || ''}`)
    .join('||');
  const source = c.kind === 1
    ? t('tile.weeklyRecommendation')
    : c.author_username
      ? t('tile.byAuthor', { name: c.author_username })
      : t('tile.authorFallback');

  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c5-card no-underline"
      style={{ '--c5-accent': c.accent_color || fallback } as React.CSSProperties}
    >
      <div className="c5-media">
        <ProgressiveCollectionCover
          key={coverKey}
          tiles={tiles}
          fallbackColor={fallback}
          title={c.title}
          eager={eager}
        />
        {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
      </div>
      <div className="c5-copy">
        <div className="c5-eyebrow">
          <span className="c5-source"><i aria-hidden />{source}</span>
          <span aria-hidden>COL—{String(index).padStart(2, '0')}</span>
        </div>
        <div className="c5-body">
          <h2 className="display c5-title" title={c.title}>{c.title}</h2>
          {c.description && <p className="c5-description">{c.description}</p>}
        </div>
        <div className="c5-meta">{countLabel(c, t)}</div>
      </div>
      <span className="c5-arrow" aria-hidden>
        <svg viewBox="0 0 24 24" focusable="false">
          <path d="M5 12h13M13 7l5 5-5 5" />
        </svg>
      </span>
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
