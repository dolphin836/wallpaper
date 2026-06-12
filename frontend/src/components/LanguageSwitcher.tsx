import { useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { AiOutlineGlobal, AiOutlineCheck } from 'react-icons/ai';
import { SUPPORTED_LANGS, LANG_NAMES, setLanguage, type Lang } from '../i18n';

/**
 * Globe dropdown in the top-nav right cluster. Language names render in
 * their own script (English / 简体中文 / 繁體中文 / 日本語) regardless of the
 * active language. Choice persists to localStorage via setLanguage.
 */
export default function LanguageSwitcher() {
  const { t, i18n } = useTranslation();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', onDoc);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDoc);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((o) => !o)}
        title={t('header.language')}
        aria-label={t('header.language')}
        aria-expanded={open}
        className="w-[34px] h-[34px] rounded-full inline-flex items-center justify-center bg-paper-2 border border-hair text-ink-2 hover:text-ink hover:border-ink-2 transition-colors"
      >
        <AiOutlineGlobal size={15} />
      </button>
      {open && (
        <div
          role="menu"
          className="absolute right-0 top-[calc(100%+8px)] z-50 min-w-[150px] bg-paper border border-hair rounded-xl shadow-[0_16px_48px_rgba(0,0,0,0.18)] p-1.5"
        >
          {SUPPORTED_LANGS.map((lng: Lang) => {
            const active = i18n.language === lng;
            return (
              <button
                key={lng}
                role="menuitemradio"
                aria-checked={active}
                onClick={() => { setLanguage(lng); setOpen(false); }}
                className={`w-full flex items-center justify-between gap-3 px-3 py-2 rounded-md text-[13px] text-left transition-colors hover:bg-paper-2 ${
                  active ? 'text-ink font-medium' : 'text-ink-2'
                }`}
              >
                {LANG_NAMES[lng]}
                {active && <AiOutlineCheck size={13} className="text-accent" />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
