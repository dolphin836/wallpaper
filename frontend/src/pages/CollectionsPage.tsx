import { useState, useEffect, useCallback, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
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
          <CollectionsSkeleton current={current} />
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
          // Page 1 opens as an editorial spread. The remaining cards use
          // an asymmetric 12-column catalogue rhythm while keeping the
          // existing three-stage cover loader untouched.
          <>
            {current === 1 && visible.length > 1 && (
              <CollectionHeroBanner collection={visible[0]} onTintsChange={applyTints} />
            )}
            <div className="c3-grid">
              {(current === 1 && visible.length > 1 ? visible.slice(1) : visible).map((c, index) => (
                <CollectionShowcaseCard
                  key={c.id}
                  collection={c}
                  index={(current - 1) * PAGE_SIZE + index + (current === 1 && visible.length > 1 ? 2 : 1)}
                  onTintsChange={applyTints}
                />
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

function authorLabel(c: Collection, t: (k: string, o?: Record<string, unknown>) => string): string {
  if (c.kind === 1) return t('tile.weeklyRecommendation');
  if (c.author_username) return t('tile.byAuthor', { name: c.author_username });
  return t('tile.authorFallback');
}

/* The loading view mirrors the editorial spread, asymmetric card widths,
   cover geometry, and all three caption rows of the resolved page. */
function CollectionsSkeleton({ current }: { current: number }) {
  const hasHero = current === 1;
  const cardCount = hasHero ? PAGE_SIZE - 1 : PAGE_SIZE;

  return (
    <>
      {hasHero && (
        <div className="c3-lead c3-skeleton-lead" aria-hidden>
          <div className="c3-lead-cover c3-skeleton-cover skeleton-card" />
          <div className="c3-lead-copy">
            <div>
              <span className="c3-skeleton-line c3-skeleton-kicker skeleton-card" />
              <span className="c3-skeleton-line c3-skeleton-hero-title skeleton-card" />
              <span className="c3-skeleton-line c3-skeleton-hero-title is-short skeleton-card" />
            </div>
            <div className="c3-lead-meta">
              <span className="c3-skeleton-line c3-skeleton-author skeleton-card" />
              <span className="c3-skeleton-line c3-skeleton-count skeleton-card" />
            </div>
          </div>
        </div>
      )}
      <div className="c3-grid">
        {Array.from({ length: cardCount }).map((_, i) => (
          <div key={i} className="c3-card c3-skeleton-card" aria-hidden>
            <div className="c3-card-cover skeleton-card">
              <div className="c2-mosaic c3-skeleton-mosaic">
                <div className="c2-main" />
                <div />
                <div />
              </div>
            </div>
            <div className="c3-card-caption">
              <div className="c3-card-index">
                <span className="c3-skeleton-line c3-skeleton-kicker skeleton-card" />
              </div>
              <span className="c3-skeleton-line c3-skeleton-title skeleton-card" />
              <div className="c3-card-meta">
                <span className="c3-skeleton-line c3-skeleton-author skeleton-card" />
                <span className="c3-skeleton-line c3-skeleton-count skeleton-card" />
              </div>
            </div>
          </div>
        ))}
      </div>
    </>
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
}: {
  tiles: [CollectionTile | undefined, CollectionTile | undefined, CollectionTile | undefined];
  fallbackColor: string;
  title: string;
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
          allowPreview={allowPreview}
          onThumbSettled={markMainSettled}
        />
      </div>
      <div>
        <ProgressiveCollectionImage
          tile={sub1}
          fallbackColor={fallbackColor}
          allowPreview={allowPreview}
          onThumbSettled={markSub1Settled}
        />
      </div>
      <div>
        <ProgressiveCollectionImage
          tile={sub2}
          fallbackColor={fallbackColor}
          allowPreview={allowPreview}
          onThumbSettled={markSub2Settled}
        />
      </div>
    </div>
  );
}

/* The leading collection opens as a two-page editorial spread: artwork on
   the left, a quiet paper colophon on the right. The cover loader itself is
   the same dominant-color -> thumb -> preview sequence used before. */
function CollectionHeroBanner({
  collection: c,
  onTintsChange,
}: {
  collection: Collection;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  const cover = collectionCoverTiles(c)[0];
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c3-lead no-underline"
      style={{ '--c3-accent': c.accent_color || cover?.dominant_color || 'var(--color-ink)' } as React.CSSProperties}
      onMouseEnter={() => { const tints = collectionTints(c); if (tints.length) onTintsChange?.(tints); }}
      onMouseLeave={() => onTintsChange?.(null)}
    >
      <div
        className="c3-lead-cover"
        style={{ backgroundColor: cover?.dominant_color || c.accent_color || undefined }}
      >
        <ProgressiveCollectionImage
          key={`${cover?.thumb_url || ''}|${cover?.preview_url || ''}`}
          tile={cover}
          fallbackColor={c.accent_color}
          alt={c.title}
          eager
        />
        <div className="c3-cover-vignette" />
        {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
        <span className="c3-lead-number" aria-hidden>01</span>
      </div>
      <div className="c3-lead-copy">
        <div>
          <div className="c3-lead-kicker">
            <span>{c.kind === 1 ? t('tile.weeklyRecommendation') : t('tile.kickerCollection')}</span>
            <span aria-hidden>VOL. 01</span>
          </div>
          <h2 className="display c3-lead-title" title={c.title}>{c.title}</h2>
        </div>
        <div className="c3-lead-meta">
          <span>{authorLabel(c, t)}</span>
          <span>{countLabel(c, t)}</span>
        </div>
        <span className="c3-open-mark" aria-hidden>↗</span>
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
  index,
  onTintsChange,
}: {
  collection: Collection;
  index: number;
  onTintsChange?: (tints: string[] | null) => void;
}) {
  const { t } = useTranslation('collections');
  const [main, sub1, sub2] = collectionCoverTiles(c);
  const fallback = main?.dominant_color || c.accent_color || 'var(--color-paper-2)';
  const mosaicKey = [main, sub1, sub2]
    .map((tile) => `${tile?.thumb_url || ''}|${tile?.preview_url || ''}`)
    .join('||');
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c3-card no-underline"
      style={{ '--c3-accent': c.accent_color || fallback } as React.CSSProperties}
      onMouseEnter={() => { const tints = collectionTints(c); if (tints.length) onTintsChange?.(tints); }}
      onMouseLeave={() => onTintsChange?.(null)}
    >
      <div className="c3-card-cover">
        <ProgressiveCollectionMosaic
          key={mosaicKey}
          tiles={[main, sub1, sub2]}
          fallbackColor={fallback}
          title={c.title}
        />
        <div className="c3-cover-vignette" />
        {!c.is_public && <span className="c2-lock">{t('tile.private')}</span>}
      </div>
      <div className="c3-card-caption">
        <div className="c3-card-index">
          <span>{c.kind === 1 ? t('tile.weeklyRecommendation') : t('tile.kickerCollection')}</span>
          <span>COL—{String(index).padStart(2, '0')}</span>
        </div>
        <div className="c3-card-title-row">
          <h2 className="display c3-card-title" title={c.title}>{c.title}</h2>
          <span className="c3-card-arrow" aria-hidden>↗</span>
        </div>
        <div className="c3-card-meta">
          <span>{authorLabel(c, t)}</span>
          <span>{countLabel(c, t)}</span>
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
