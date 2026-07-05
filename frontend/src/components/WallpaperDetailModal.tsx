import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

/**
 * Modal frame around the wallpaper detail. Rounded inset panel pinned with
 * comfortable margins from the viewport, backed by a dim scrim.
 *
 * No close chrome of its own: the immersive page's top-left back circle
 * (navigate(-1)) closes the modal, and ESC / backdrop-click remain as
 * close paths.
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
        className="wd-in-modal absolute bg-paper shadow-[0_24px_80px_rgba(0,0,0,0.32)] flex flex-col overflow-hidden rounded-[24px]"
        style={{ top: 28, bottom: 28, left: 40, right: 40 }}
      >
        <WallpaperDetailPage />
      </div>
    </div>
  );
}
