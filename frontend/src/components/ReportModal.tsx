import { useState } from 'react';
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
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={onClose}>
      <div
        className="bg-white dark:bg-ws-dark-card rounded-2xl shadow-xl border border-ws-border dark:border-white/5 p-6 w-full max-w-md"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-slate-900 dark:text-white">Report this wallpaper</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700 dark:hover:text-white">
            <AiOutlineClose size={20} />
          </button>
        </div>

        <div className="space-y-3">
          <div>
            <label className="block text-xs font-medium text-ws-muted dark:text-ws-dark-muted mb-1">Reason</label>
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              className="w-full bg-ws-bg dark:bg-ws-dark-bg border border-ws-border dark:border-white/10 rounded-xl py-2.5 px-4 text-sm outline-none focus:ring-1 focus:ring-ws-purple dark:text-white"
            >
              {REASONS.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-xs font-medium text-ws-muted dark:text-ws-dark-muted mb-1">Additional details (optional)</label>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              maxLength={2000}
              rows={4}
              placeholder="Source URL, copyright owner, or anything else useful for moderators…"
              className="w-full bg-ws-bg dark:bg-ws-dark-bg border border-ws-border dark:border-white/10 rounded-xl py-2.5 px-4 text-sm outline-none focus:ring-1 focus:ring-ws-purple dark:text-white resize-none"
            />
            <p className="text-[11px] text-ws-muted dark:text-ws-dark-muted mt-1">
              For formal DMCA notices please use the dedicated channel on the{' '}
              <a href="/legal/dmca" className="text-ws-purple hover:underline">Copyright page</a>.
            </p>
          </div>

          <div className="flex justify-end gap-2 pt-2">
            <button
              onClick={onClose}
              className="px-4 py-2 text-sm rounded-xl border border-ws-border dark:border-white/10 hover:bg-ws-bg dark:hover:bg-white/5 transition-colors dark:text-white"
            >
              Cancel
            </button>
            <button
              onClick={submit}
              disabled={submitting}
              className="px-4 py-2 text-sm rounded-xl bg-ws-purple text-white hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {submitting ? 'Submitting…' : 'Submit'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
