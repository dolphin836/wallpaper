import { useEffect } from 'react';
import { createPortal } from 'react-dom';

/**
 * In-app confirm dialog that replaces window.confirm() for destructive
 * actions. OS-native confirm in the middle of a bespoke editorial UI was
 * the single most jarring break in the product (see critique P1). This
 * matches the existing trade-CTA confirm panel: ink panel + accent border,
 * primary destructive action accent-tinted, escape and backdrop click cancel.
 *
 * Use:
 *   const [open, setOpen] = useState(false);
 *   ...
 *   <InAppConfirm
 *     open={open}
 *     title="Delete this wallpaper?"
 *     message="This removes the wallpaper and its variants permanently."
 *     confirmLabel="Delete"
 *     destructive
 *     onConfirm={() => { setOpen(false); doDelete(); }}
 *     onCancel={() => setOpen(false)}
 *   />
 */
export default function InAppConfirm({
  open,
  title,
  message,
  confirmLabel = 'Confirm',
  cancelLabel = 'Cancel',
  destructive = false,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  title: string;
  message?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  // ESC to cancel — only while the dialog is open.
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onCancel(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onCancel]);

  if (!open) return null;

  return createPortal(
    <div
      className="fixed inset-0 z-[90] flex items-center justify-center px-6 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
      onClick={onCancel}
      role="dialog"
      aria-modal="true"
      aria-labelledby="iac-title"
    >
      <div
        className="w-full max-w-sm bg-paper text-ink border border-hair rounded-[20px] p-5 shadow-[0_24px_70px_rgba(0,0,0,0.28)]"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="kicker tracking-[0.14em] text-accent-ink">
          {destructive ? 'CONFIRM DELETION' : 'CONFIRM ACTION'}
        </div>
        <h2 id="iac-title" className="display text-[24px] sm:text-[28px] leading-tight mt-1.5">
          {title}
        </h2>
        {message && (
          <p className="mt-3 text-[13px] leading-snug text-ink-2">
            {message}
          </p>
        )}
        <div className="mt-5 flex items-center justify-end gap-2.5">
          <button
            onClick={onCancel}
            className="px-4 py-2 rounded-full font-medium text-[12px] border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 transition-colors"
          >
            {cancelLabel}
          </button>
          <button
            onClick={onConfirm}
            autoFocus
            className="inline-flex items-center justify-center gap-2 px-5 py-2 rounded-full text-paper font-semibold text-[12px] transition-transform hover:translate-y-[-1px]"
            style={{ background: destructive ? 'oklch(54% 0.22 28)' : 'var(--color-ink)' }}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
