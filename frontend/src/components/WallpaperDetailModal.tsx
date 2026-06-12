import { useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { AiOutlineClose } from 'react-icons/ai';
import WallpaperDetailPage from '../pages/WallpaperDetailPage';

/**
 * Modal frame around the wallpaper detail. Rounded inset panel pinned with
 * comfortable margins from the viewport, backed by a dim scrim.
 *
 * The visible chrome inside the modal is now just a small ✕ button anchored
 * to the top-right of the panel (faint by default, opaque on hover). Both
 * ESC and backdrop-click are also valid close paths. The previous header
 * strip with "SPECIMEN №… · OVERLAY VIEW · ESC · ✕" was removed because
 * it took vertical space without earning it.
 */
export default function WallpaperDetailModal() {
  const { t } = useTranslation('detail');
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

        {/* Faint close affordance — sits over the page chrome with low
            opacity until hovered, so it doesn't compete with the
            wallpaper preview for attention. */}
        <button
          onClick={close}
          className="wd-modal-close"
          aria-label={t('modal.close')}
          title={t('modal.closeEsc')}
        >
          <AiOutlineClose size={16} />
        </button>
        <style>{`
.wd-modal-close {
  position: absolute;
  top: 14px;
  right: 14px;
  z-index: 80;
  width: 34px;
  height: 34px;
  border-radius: 999px;
  background: rgba(20, 18, 15, 0.42);
  backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.18);
  color: white;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  opacity: 0.45;
  transition: opacity .2s ease, background-color .2s ease, transform .15s ease;
}
.wd-modal-close:hover {
  opacity: 1;
  background: rgba(20, 18, 15, 0.7);
  transform: scale(1.05);
}
        `}</style>
      </div>
    </div>
  );
}
