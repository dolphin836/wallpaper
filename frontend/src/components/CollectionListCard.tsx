import { useCallback, useState } from 'react';
import type { CSSProperties } from 'react';
import { useTranslation } from 'react-i18next';
import { Link } from 'react-router-dom';
import type { Collection, CollectionTile } from '../types';

function collectionTints(c: Collection): string[] {
  const tints = (c.recent_tiles ?? [])
    .map((tile) => tile.dominant_color)
    .filter((color): color is string => Boolean(color))
    .slice(0, 3);
  if (!tints.length && c.accent_color) tints.push(c.accent_color);
  return tints;
}

function collectionCoverTiles(c: Collection): Array<CollectionTile | undefined> {
  const available = [...(c.recent_tiles ?? [])];
  let first = available[0];

  // Older or empty collections may only expose cover_url. Treat it as
  // a one-stage tile so the card still follows the same rendering path.
  if (!first && c.cover_url) {
    first = {
      thumb_url: c.cover_url,
      preview_url: c.cover_url,
      dominant_color: c.accent_color || '',
    };
    available.push(first);
  }

  if (!first) return [undefined, undefined, undefined];

  // Cards resolve to at most three slots, matching the list API contract.
  // Repeat the first image when there are fewer than three so the stepped
  // composition stays complete without inventing empty white gaps.
  const resolved = available.slice(0, 3);
  while (resolved.length < 3) resolved.push(first);
  return resolved;
}

function countLabel(c: Collection, t: (k: string, o?: Record<string, unknown>) => string): string {
  return c.wallpaper_count === 1
    ? t('tile.wallpaperCountOne')
    : t('tile.wallpaperCount', { num: c.wallpaper_count });
}

type ImageLoadState = 'idle' | 'loaded' | 'failed';

// One collection-cover slot, loaded in a strict sequence:
// dominant color -> thumb -> preview. The preview element is not mounted
// until the thumb has settled, so the larger request cannot start early.
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

// Every small image settles before a large preview is mounted, preserving
// the dominant colour -> thumb -> preview network order.
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
    <div className="c5-cover-layout">
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

export function CollectionListCard({
  collection: c,
  eager = false,
  onTintsChange,
}: {
  collection: Collection;
  eager?: boolean;
  onTintsChange?: (tints: string[] | null) => void;
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
  const applyCollectionTints = () => {
    const tints = collectionTints(c);
    if (tints.length) onTintsChange?.(tints);
  };

  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c5-card no-underline"
      style={{ '--c5-accent': c.accent_color || fallback } as CSSProperties}
      onMouseEnter={applyCollectionTints}
      onMouseLeave={() => onTintsChange?.(null)}
      onFocus={applyCollectionTints}
      onBlur={() => onTintsChange?.(null)}
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
        </div>
        <div className="c5-body">
          <h2 className="display c5-title" title={c.title}>{c.title}</h2>
          <p
            className={`c5-description${c.description ? '' : ' is-empty'}`}
            aria-hidden={c.description ? undefined : true}
          >
            {c.description || '\u00a0'}
          </p>
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

export function CollectionListCardSkeleton() {
  return (
    <div className="c5-card c5-skeleton-card">
      <div className="c5-media">
        <div className="c5-cover-layout">
          <div className="skeleton-card" />
          <div className="skeleton-card" />
          <div className="skeleton-card" />
        </div>
      </div>
      <div className="c5-copy">
        <div className="c5-eyebrow">
          <span className="c5-skeleton-line c5-skeleton-source skeleton-card" />
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
    </div>
  );
}
