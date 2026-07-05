import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

/**
 * Modal frame around the wallpaper detail. Full-viewport overlay with no
 * inset — mirrors the Mac client's full-window detail overlay; the
 * wallpaper reads as the entire screen, not a floating panel.
 *
 * No close chrome of its own: the immersive page's top-left back circle
 * (navigate(-1)) closes the modal, and ESC remains as a close path.
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
    <div className="fixed inset-0 z-50">
      <div className="wd-in-modal absolute inset-0 bg-paper flex flex-col overflow-hidden">
        <WallpaperDetailPage />
      </div>
    </div>
  );
}
