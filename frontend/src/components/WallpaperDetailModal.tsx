import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

/**
 * Modal frame around the wallpaper detail. Inset panel pinned 40px from
 * top/bottom and 60px from left/right (per the design handoff), backed by a
 * dim/blur scrim. The panel itself is `overflow: hidden` and lets the
 * detail page's own inner column own the scrolling, so the page never grows
 * a horizontal/vertical scrollbar on the browser viewport.
 *
 * The close affordance now lives *inside* the detail page (header strip
 * with shortcuts + ✕). We still handle ESC + backdrop-click here so those
 * paths don't bleed into the detail body and so body-scroll locks while
 * the modal is up.
 */
export default function WallpaperDetailModal() {
  const navigate = useNavigate();
  const close = useCallback(() => navigate(-1), [navigate]);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    document.addEventListener('keydown', handleKey);

    // Lock body scroll while open; pad away the gutter we steal so the
    // viewport-width metric stays stable (otherwise the page behind shifts
    // by the scrollbar width, which flickers any layout-dependent control
    // on the underlying gallery).
    const body = document.body;
    const prevOverflow = body.style.overflow;
    const prevPadding = body.style.paddingRight;
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
    body.style.overflow = 'hidden';
    if (scrollbarWidth > 0) body.style.paddingRight = `${scrollbarWidth}px`;

    return () => {
      document.removeEventListener('keydown', handleKey);
      body.style.overflow = prevOverflow;
      body.style.paddingRight = prevPadding;
    };
  }, [close]);

  return (
    <div
      onClick={close}
      className="fixed inset-0 z-50 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
    >
      {/* Inset panel — pinned to all four sides so the modal never scrolls
          the underlying page. Inner detail body provides its own column
          scroll. */}
      <div
        onClick={(e) => e.stopPropagation()}
        className="absolute bg-paper border border-ink shadow-[0_24px_80px_rgba(0,0,0,0.25)] flex flex-col overflow-hidden"
        style={{ top: 40, bottom: 40, left: 60, right: 60 }}
      >
        <WallpaperDetailPage />
      </div>
    </div>
  );
}
