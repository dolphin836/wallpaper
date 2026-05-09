import { useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { AiOutlineClose } from 'react-icons/ai';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

export default function WallpaperDetailModal() {
  const navigate = useNavigate();
  const overlayRef = useRef<HTMLDivElement>(null);

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

  const handleOverlayClick = (e: React.MouseEvent) => {
    if (e.target === overlayRef.current) close();
  };

  return (
    <div
      ref={overlayRef}
      onClick={handleOverlayClick}
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm overflow-y-auto"
    >
      <div className="min-h-full flex justify-center py-8 px-4">
        <div className="relative w-full max-w-5xl">
          <button
            onClick={close}
            className="sticky top-4 float-right z-10 mr-2 p-2 bg-black/50 hover:bg-black/70 text-white rounded-full transition-colors"
            aria-label="Close"
          >
            <AiOutlineClose size={20} />
          </button>
          <WallpaperDetailPage />
        </div>
      </div>
    </div>
  );
}
