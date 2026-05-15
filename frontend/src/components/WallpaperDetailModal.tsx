import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { AiOutlineClose } from 'react-icons/ai';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

export default function WallpaperDetailModal() {
  const navigate = useNavigate();
  const close = useCallback(() => navigate(-1), [navigate]);

  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    document.addEventListener('keydown', handleKey);

    // Lock body scroll while the modal is open. Just setting overflow: hidden
    // removes the page's scrollbar — and since the viewport width measurement
    // (window.innerWidth) jumps by the scrollbar's width, every component
    // that watches `resize` (e.g. ProfilePage's useViewportPageSize) sees a
    // bogus event, recomputes page size, and triggers a cascading re-render
    // that visually flickers the controls underneath. We compensate by
    // padding the body with the same width so the viewport metric stays
    // stable across the lock/unlock cycle.
    const body = document.body;
    const prevOverflow = body.style.overflow;
    const prevPadding = body.style.paddingRight;
    const scrollbarWidth = window.innerWidth - document.documentElement.clientWidth;
    body.style.overflow = 'hidden';
    if (scrollbarWidth > 0) {
      body.style.paddingRight = `${scrollbarWidth}px`;
    }
    return () => {
      document.removeEventListener('keydown', handleKey);
      body.style.overflow = prevOverflow;
      body.style.paddingRight = prevPadding;
    };
  }, [close]);

  // Wrap close in a propagation stopper for the close button so the click
  // doesn't *also* bubble up to the overlay's onClick — without this you'd
  // get two navigate(-1) calls per click and pop two history entries,
  // landing the user wherever they were *before* opening the previous page
  // (typical symptom: closing kicks you out of /wallpaper/:slug all the way
  // back to your profile page when you opened it from the home grid).
  const onCloseClick = (e: React.MouseEvent) => {
    e.stopPropagation();
    close();
  };

  return (
    // Outer overlay closes on any click that bubbles up to it. The card and the
    // close button below stopPropagation so clicking either doesn't double-fire.
    <div
      onClick={close}
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm overflow-y-auto"
    >
      <div className="min-h-full flex justify-center py-8 px-4">
        <div
          className="relative w-full max-w-5xl"
          onClick={(e) => e.stopPropagation()}
        >
          <WallpaperDetailPage />
        </div>
      </div>
      {/* Close button lives outside the card and is pinned to the viewport corner
          so it stays visible while the modal content scrolls. */}
      <button
        onClick={onCloseClick}
        className="fixed top-4 right-4 z-[60] p-2 bg-black/50 hover:bg-black/70 text-white rounded-full transition-colors"
        aria-label="Close"
      >
        <AiOutlineClose size={20} />
      </button>
    </div>
  );
}
