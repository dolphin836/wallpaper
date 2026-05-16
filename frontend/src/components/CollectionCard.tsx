import { Link } from 'react-router-dom';
import { AiOutlineLock } from 'react-icons/ai';
import type { Collection } from '../types';

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
 * Reads `collection.recent_thumbs` (max 3) to populate the slots. If the
 * collection has fewer than 3 wallpapers the trailing slots fall back to
 * the cover_url or a soft paper-2 tile.
 */
export default function CollectionCard({ collection, curatorHandle }: Props) {
  const thumbs = collection.recent_thumbs ?? [];
  const fallback = collection.cover_url || '';
  const main = thumbs[0] || fallback;
  const sub1 = thumbs[1] || '';
  const sub2 = thumbs[2] || '';

  const extra = Math.max(0, collection.wallpaper_count - 3);

  return (
    <Link to={`/collections/${collection.slug}`} className="coll-card no-underline text-ink">
      <div className="coll-stack">
        <div className="coll-main">
          {main && <img src={main} alt="" loading="lazy" />}
        </div>
        <div className="coll-sub">
          {sub1 && <img src={sub1} alt="" loading="lazy" />}
        </div>
        <div className="coll-sub">
          {sub2 && <img src={sub2} alt="" loading="lazy" />}
          {extra > 0 && <span className="coll-more">+{extra}</span>}
        </div>
      </div>

      {/* Caption */}
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
