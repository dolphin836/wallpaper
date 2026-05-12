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
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', handleKey);
      document.body.style.overflow = '';
    };
  }, [close]);

  return (
    // Outer overlay closes on any click that bubbles up to it. The white card below
    // stops propagation so clicking inside (or on its buttons) keeps the modal open.
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
        onClick={close}
        className="fixed top-4 right-4 z-[60] p-2 bg-black/50 hover:bg-black/70 text-white rounded-full transition-colors"
        aria-label="Close"
      >
        <AiOutlineClose size={20} />
      </button>
    </div>
  );
}
