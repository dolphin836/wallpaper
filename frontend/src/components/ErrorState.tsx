import { AiOutlineReload } from 'react-icons/ai';

interface Props {
  /** Headline. Defaults to the editorial 'Something's off' line. */
  title?: string;
  /** Body copy under the headline. Defaults to a network-hiccup message. */
  message?: string;
  /**
   * Click handler for the retry button. If omitted, the button does a
   * full window.location.reload() — that's almost always what the user
   * wants when a data page failed to load (it re-runs every fetch the
   * page does on mount, no per-page wiring needed).
   */
  onRetry?: () => void;
}

/**
 * Shared error state for data-fetching pages. Centered card with a
 * warning glyph + headline + body copy + 'Try again' pill. Renders
 * inside whatever container the caller provides — pages typically
 * drop it where the loaded content would go, so the page chrome
 * (header, nav, mesh) stays intact and only the data area is
 * replaced.
 *
 * Don't use on pure-static pages (legal, about, etc.) — they have no
 * fetch to fail.
 */
export default function ErrorState({
  title = "Couldn't load this page",
  message = "Something went wrong on our end. The server might be catching its breath — give it a moment and try again.",
  onRetry,
}: Props) {
  const handleRetry = onRetry || (() => window.location.reload());
  return (
    <div className="error-state">
      <div className="error-state__icon" aria-hidden>
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor"
             strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z" />
          <line x1="12" y1="9" x2="12" y2="13" />
          <line x1="12" y1="17" x2="12.01" y2="17" />
        </svg>
      </div>
      <h2 className="error-state__title">{title}</h2>
      <p className="error-state__message">{message}</p>
      <button type="button" onClick={handleRetry} className="error-state__retry">
        <AiOutlineReload size={13} />
        <span>Try again</span>
      </button>
    </div>
  );
}
