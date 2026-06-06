import { useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import { AiOutlineClose } from 'react-icons/ai';
import { reportWallpaper } from '../api';

interface ReportModalProps {
  wallpaperId: number;
  onClose: () => void;
}

const REASONS = [
  { value: 'nsfw', label: 'NSFW / explicit content' },
  { value: 'copyright', label: 'Copyright infringement / not the original author' },
  { value: 'spam', label: 'Spam or low-effort upload' },
  { value: 'low_quality', label: 'Low quality or broken image' },
  { value: 'other', label: 'Other' },
];

export default function ReportModal({ wallpaperId, onClose }: ReportModalProps) {
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
      toast.success('Report submitted. Thanks for helping keep the catalog clean.');
      onClose();
    } catch {
      toast.error('Could not submit report. Try again.');
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
            <div className="kicker text-muted">Catalog moderation</div>
            <h3 id="report-modal-title" className="display text-[22px] leading-none mt-2">Report this wallpaper</h3>
          </div>
          <button
            onClick={onClose}
            disabled={submitting}
            aria-label="Close"
            className="w-8 h-8 rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 inline-flex items-center justify-center transition-colors disabled:opacity-50"
          >
            <AiOutlineClose size={13} />
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block mono text-[10px] tracking-[0.14em] uppercase text-muted mb-1.5">Reason</label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full bg-paper-2 border border-hair rounded-lg py-2.5 px-3.5 text-[13px] text-ink outline-none focus:border-ink-2 transition-colors"
            >
              {REASONS.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block mono text-[10px] tracking-[0.14em] uppercase text-muted mb-1.5">Additional details</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={2000}
              rows={4}
              placeholder="Source URL, copyright owner, or anything else useful for moderators…"
              className="w-full bg-paper-2 border border-hair rounded-lg py-2.5 px-3.5 text-[13px] text-ink placeholder:text-muted outline-none focus:border-ink-2 transition-colors resize-none"
            />
            <p className="text-[11px] text-muted mt-1.5 leading-relaxed">
              For formal DMCA notices please use the dedicated channel on the{' '}
              <a href="/legal/dmca" className="text-accent-ink hover:underline">Copyright page</a>.
            </p>
          </div>

          <div className="flex justify-end gap-2 pt-1">
            <button
              onClick={onClose}
              disabled={submitting}
              className="px-4 py-2 text-[13px] rounded-full border border-hair text-ink-2 hover:text-ink hover:bg-paper-2 transition-colors disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              onClick={submit}
              disabled={submitting}
              className="px-5 py-2 text-[13px] font-semibold rounded-full bg-ink text-paper hover:bg-ink-2 transition-colors disabled:opacity-50"
            >
              {submitting ? 'Submitting…' : 'Submit'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
