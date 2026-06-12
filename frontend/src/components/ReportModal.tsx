import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { useTranslation, Trans } from 'react-i18next';
import { AiOutlineClose } from 'react-icons/ai';
import { reportWallpaper } from '../api';

interface ReportModalProps {
  wallpaperId: number;
  onClose: () => void;
}

// `value` is the API param (do not localise); `labelKey` resolves in the
// `detail` namespace.
const REASONS = [
  { value: 'nsfw', labelKey: 'report.reasons.nsfw' },
  { value: 'copyright', labelKey: 'report.reasons.copyright' },
  { value: 'spam', labelKey: 'report.reasons.spam' },
  { value: 'low_quality', labelKey: 'report.reasons.lowQuality' },
  { value: 'other', labelKey: 'report.reasons.other' },
];

export default function ReportModal({ wallpaperId, onClose }: ReportModalProps) {
  const { t } = useTranslation('detail');
  const [reason, setReason] = useState('nsfw');
  const [note, setNote] = useState('');
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && !submitting) onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose, submitting]);

  const submit = async () => {
    setSubmitting(true);
    try {
      await reportWallpaper(wallpaperId, reason, note.trim());
      toast.success(t('report.submitted'));
      onClose();
    } catch {
      toast.error(t('report.submitFailed'));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 backdrop-blur-[2px]"
      style={{ background: 'rgba(15,12,8,0.55)' }}
      onClick={() => { if (!submitting) onClose(); }}
    >
      <div
        className="bg-paper text-ink rounded-[20px] shadow-[0_24px_70px_rgba(0,0,0,0.28)] border border-hair p-5 w-full max-w-[420px]"
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="report-modal-title"
      >
        <div className="flex items-start justify-between gap-4 mb-5">
          <div>
            <div className="kicker text-muted">{t('report.kicker')}</div>
            <h3 id="report-modal-title" className="display text-[22px] leading-none mt-2">{t('report.title')}</h3>
          </div>
          <button
            onClick={onClose}
            disabled={submitting}
            aria-label={t('report.close')}
            className="w-8 h-8 rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 inline-flex items-center justify-center transition-colors disabled:opacity-50"
          >
            <AiOutlineClose size={13} />
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block mono text-[10px] tracking-[0.14em] uppercase text-muted mb-1.5">{t('report.reason')}</label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full bg-paper-2 border border-hair rounded-lg py-2.5 px-3.5 text-[13px] text-ink outline-none focus:border-ink-2 transition-colors"
            >
              {REASONS.map((r) => (
                <option key={r.value} value={r.value}>{t(r.labelKey)}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block mono text-[10px] tracking-[0.14em] uppercase text-muted mb-1.5">{t('report.details')}</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={2000}
              rows={4}
              placeholder={t('report.placeholder')}
              className="w-full bg-paper-2 border border-hair rounded-lg py-2.5 px-3.5 text-[13px] text-ink placeholder:text-muted outline-none focus:border-ink-2 transition-colors resize-none"
            />
            <p className="text-[11px] text-muted mt-1.5 leading-relaxed">
              <Trans
                i18nKey="report.dmcaNote"
                ns="detail"
                components={[<a href="/legal/dmca" className="text-accent-ink hover:underline" key="0" />]}
              />
            </p>
          </div>

          <div className="flex justify-end gap-2 pt-1">
            <button
              onClick={onClose}
              disabled={submitting}
              className="px-4 py-2 text-[13px] rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 transition-colors disabled:opacity-50"
            >
              {t('report.cancel')}
            </button>
            <button
              onClick={submit}
              disabled={submitting}
              className="px-5 py-2 text-[13px] font-semibold rounded-full bg-ink text-paper hover:bg-ink-2 transition-colors disabled:opacity-50"
            >
              {submitting ? t('report.submitting') : t('report.submit')}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
