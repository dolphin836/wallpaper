import { useEffect, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { AiOutlineClose } from 'react-icons/ai';

interface Props {
  onClose: () => void;
}

type OS = 'ios' | 'android' | 'macos' | 'windows' | 'unknown';

function detectOS(): OS {
  const ua = navigator.userAgent;
  if (/iPhone|iPad|iPod/.test(ua)) return 'ios';
  if (/Android/.test(ua)) return 'android';
  if (/Mac/.test(ua)) return 'macos';
  if (/Win/.test(ua)) return 'windows';
  return 'unknown';
}

export default function SetWallpaperGuide({ onClose }: Props) {
  const { t } = useTranslation('detail');
  const os = useMemo(() => detectOS(), []);
  // Per-OS title + steps live in the `detail` locale namespace (guide.<os>).
  const guide = {
    title: t(`guide.${os}.title`),
    steps: t(`guide.${os}.steps`, { returnObjects: true }) as string[],
  };

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
      onClick={onClose}
    >
      <div
        className="bg-paper text-ink rounded-[20px] shadow-[0_24px_70px_rgba(0,0,0,0.28)] border border-hair w-full max-w-[420px] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="set-wallpaper-guide-title"
      >
        <div className="flex items-start justify-between gap-4 p-5 border-b border-hair">
          <div>
            <div className="kicker text-muted">{t('guide.kicker')}</div>
            <h3 id="set-wallpaper-guide-title" className="display text-[22px] leading-none mt-2">{guide.title}</h3>
          </div>
          <button
            onClick={onClose}
            aria-label={t('guide.close')}
            className="w-8 h-8 rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 inline-flex items-center justify-center transition-colors"
          >
            <AiOutlineClose size={13} />
          </button>
        </div>

        <div className="p-5 space-y-3.5">
          {guide.steps.map((step, i) => (
            <div key={i} className="flex gap-3">
              <div className="shrink-0 w-7 h-7 rounded-full bg-accent-soft text-accent-ink border border-accent/20 flex items-center justify-center text-[12px] font-semibold tabular-nums">
                {i + 1}
              </div>
              <p className="text-[13px] leading-relaxed text-ink-2 pt-0.5">{step}</p>
            </div>
          ))}
        </div>

        <div className="px-5 pb-5">
          <button
            onClick={onClose}
            className="w-full py-2.5 text-[13px] font-semibold text-paper bg-ink hover:bg-ink-2 rounded-full transition-colors"
          >
            {t('guide.gotIt')}
          </button>
        </div>
      </div>
    </div>
  );
}
