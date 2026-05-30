import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

/**
 * Modal frame around the wallpaper detail. Inset panel rounded on all
 * sides (no more 90° corners against the scrim), backed by a darken/blur
 * scrim. The panel itself is `overflow: hidden` and lets the detail page's
 * own inner column own the scrolling, so the page never grows a
 * horizontal/vertical scrollbar on the browser viewport.
 *
 * The close affordance lives *inside* the detail page (header strip with
 * shortcuts + ✕). We still handle ESC + backdrop-click here so those paths
 * don't bleed into the detail body and so body-scroll locks while the
 * modal is up. The blurred-wallpaper backdrop + dominant-color tint live
 * in WallpaperDetailPage so all the wallpaper-specific styling is
 * colocated with the wallpaper data.
 */
export default function WallpaperDetailModal() {
  const navigate = useNavigate();
  const close = useCallback(() => navigate(-1), [navigate]);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    document.addEventListener('keydown', handleKey);

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
      <div
        onClick={(e) => e.stopPropagation()}
        className="absolute bg-paper shadow-[0_24px_80px_rgba(0,0,0,0.32)] flex flex-col overflow-hidden rounded-[24px]"
        style={{ top: 28, bottom: 28, left: 40, right: 40 }}
      >
        <WallpaperDetailPage />
      </div>
    </div>
  );
}
