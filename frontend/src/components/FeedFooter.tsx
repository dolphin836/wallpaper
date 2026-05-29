import { AiOutlineReload } from 'react-icons/ai';

export type FooterState = 'idle' | 'loading' | 'retry' | 'end';

interface Props {
  state: FooterState;
  count: number;
  onRetry: () => void;
}

/**
 * Shared infinite-scroll footer for feeds.
 * Renders one of four states under a wallpaper grid:
 *   - idle    → nothing (caller has fresh content, the
 *               IntersectionObserver hasn't fired yet)
 *   - loading → centered spinner + 'Loading more wallpapers' label
 *   - retry   → warning label + 'Try again' pill (clicked → onRetry)
 *   - end     → editorial 'end of the archive.' marker + count
 *
 * Lives in components/ so both DiscoverPage and DeviceWallpapersPage
 * can use it; the visual vocabulary (.feed-foot, .feed-spinner,
 * .feed-end-mark, …) is owned by index.css and shared across both.
 */
export default function FeedFooter({ state, count, onRetry }: Props) {
  if (state === 'idle') return null;
  if (state === 'loading') {
    return (
      <div className="feed-foot">
        <span className="feed-spinner" aria-hidden />
        <span className="feed-foot__label">Loading more wallpapers</span>
      </div>
    );
  }
  if (state === 'retry') {
    return (
      <div className="feed-foot">
        <span className="feed-foot__label feed-foot__label--warn">
          Couldn't auto-load · network hiccup
        </span>
        <button type="button" className="feed-foot__btn" onClick={onRetry}>
          <AiOutlineReload size={13} />
          Try again
        </button>
      </div>
    );
  }
  return (
    <div className="feed-foot feed-foot--end">
      <div className="feed-end-mark">
        <em>end</em> of the archive.
      </div>
      <div className="feed-end-count">
        {count.toLocaleString()} wallpapers
      </div>
    </div>
  );
}
