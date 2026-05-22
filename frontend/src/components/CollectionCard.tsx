import { useState } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineLock } from 'react-icons/ai';
import type { Collection, CollectionTile } from '../types';

interface Props {
  collection: Collection;
  /** When set, link to /user/:username; the curator handle on the card. */
  curatorHandle?: string;
}

/**
 * Editorial collection card with a 3-photo CSS-Grid composition: one large
 * main photo on the left, two stacked subs on the right, hairline-gapped.
 * Hover lifts the stack -3px, scales the main image 1.04 and the subs
 * 1.06, and reveals white corner brackets on the main photo. Caption
 * below the stack carries the mono № line + display title + curator.
 *
 * Each tile loads progressively: dominant-color placeholder → blurred
 * thumb → sharp preview. Matches the main wallpaper grid's behavior so
 * the visual rhythm is consistent across the site.
 */
export default function CollectionCard({ collection, curatorHandle }: Props) {
  const tiles = collection.recent_tiles ?? [];
  const main = tiles[0];
  const sub1 = tiles[1];
  const sub2 = tiles[2];

  const extra = Math.max(0, collection.wallpaper_count - 3);

  return (
    <Link
      to={`/collections/${collection.slug}`}
      className="coll-card no-underline text-ink"
      style={{ '--card-accent': collection.accent_color || 'var(--color-accent)' } as React.CSSProperties}
    >
      <div className="coll-stack">
        <div className="coll-main">
          <Tile tile={main} />
        </div>
        <div className="coll-sub">
          <Tile tile={sub1} />
        </div>
        <div className="coll-sub">
          <Tile tile={sub2} />
          {extra > 0 && <span className="coll-more">+{extra}</span>}
        </div>
      </div>

      {/* Caption. The 2px rule above is hair-colored at rest and wipes
          to the card's accent on hover (the wipe / accent color is
          set by --card-accent on the Link wrapper above). Themed
          collections carry their own accent_color from Claude; user
          collections fall back to the global accent. ID counter is
          unchanged — kept neutral so the wipe is the only colored
          motion. */}
      <div className="coll-rule mt-3" aria-hidden />
      <div className="pt-3">
        <div className="flex items-center justify-between mono text-[10px] tracking-[0.12em] uppercase text-muted">
          <span>
            №{String(collection.id).padStart(3, '0')} ·{' '}
            {collection.wallpaper_count} {collection.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
          </span>
          {!collection.is_public && (
            <span className="inline-flex items-center gap-1">
              <AiOutlineLock size={11} /> PRIVATE
            </span>
          )}
        </div>
        <div className="display text-[22px] leading-tight mt-1 text-ink line-clamp-1" title={collection.title}>
          {collection.title}
        </div>
        {curatorHandle && (
          <div className="mono text-[10px] tracking-[0.06em] text-muted mt-1">
            @{curatorHandle}
          </div>
        )}
      </div>
    </Link>
  );
}

// Tile is one of the three slots inside .coll-stack. Empty slots fall back
// to a soft paper-2 tint so the grid never shows a gap. Loaded slots paint
// the wallpaper's dominant color first, fade in the blurred thumb on
// download, then crossfade to the sharp preview when it arrives.
function Tile({ tile }: { tile?: CollectionTile }) {
  const [highLoaded, setHighLoaded] = useState(false);
  if (!tile || !tile.thumb_url) return null;

  return (
    <div
      className="absolute inset-0"
      style={{ backgroundColor: tile.dominant_color || 'var(--color-paper-2)' }}
    >
      <img
        src={tile.thumb_url}
        alt=""
        aria-hidden
        className="absolute inset-0 w-full h-full object-cover"
        style={{
          filter: highLoaded ? 'none' : 'blur(12px)',
          transform: highLoaded ? 'none' : 'scale(1.06)',
          transition: 'filter 300ms ease, transform 300ms ease',
        }}
      />
      {tile.preview_url && (
        <img
          src={tile.preview_url}
          alt=""
          loading="lazy"
          onLoad={() => setHighLoaded(true)}
          className="absolute inset-0 w-full h-full object-cover"
          style={{
            opacity: highLoaded ? 1 : 0,
            transition: 'opacity 300ms ease',
          }}
        />
      )}
    </div>
  );
}
