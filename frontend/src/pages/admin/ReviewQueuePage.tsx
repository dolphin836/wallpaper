import { useCallback, useEffect, useState } from 'react';
import toast from 'react-hot-toast';
import {
  listAdminReviewQueue,
  approveAdminReview,
  rejectAdminReview,
  type AdminWallpaperRow,
} from '../../api/admin';

// Review queue surfaces every wallpaper in status=PendingReview (5)
// alongside a preview the admin needs to make the call. We render the
// queue oldest-first so first-come is first-reviewed; reject prompts
// for a reason that gets stored on the row and surfaces to the
// uploader on their "my uploads" tab.
export default function ReviewQueuePage() {
  const [rows, setRows] = useState<AdminWallpaperRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const limit = 20;
  const [actingID, setActingID] = useState<number | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await listAdminReviewQueue({ page, limit });
      setRows(res.data.data.items);
      setTotal(res.data.data.total);
    } catch (e) {
      console.error(e);
      toast.error('Failed to load review queue');
    } finally {
      setLoading(false);
    }
  }, [page]);

  useEffect(() => { load(); }, [load]);

  const approve = async (id: number) => {
    setActingID(id);
    try {
      await approveAdminReview(id);
      toast.success('Approved');
      setRows((r) => r.filter((x) => x.id !== id));
      setTotal((t) => Math.max(0, t - 1));
    } catch {
      toast.error('Approve failed');
    } finally {
      setActingID(null);
    }
  };

  const reject = async (id: number) => {
    const reason = window.prompt('Rejection reason (shown to the uploader):', '');
    if (reason === null) return; // user hit Cancel
    setActingID(id);
    try {
      await rejectAdminReview(id, reason);
      toast.success('Rejected');
      setRows((r) => r.filter((x) => x.id !== id));
      setTotal((t) => Math.max(0, t - 1));
    } catch {
      toast.error('Reject failed');
    } finally {
      setActingID(null);
    }
  };

  return (
    <div>
      <div className="flex items-baseline justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold">审核队列</h1>
          <p className="text-sm text-gray-500 mt-1">
            待审核：<span className="font-medium text-gray-900">{total}</span> 张
          </p>
        </div>
      </div>

      {loading ? (
        <div className="text-gray-500 text-sm">Loading…</div>
      ) : rows.length === 0 ? (
        <div className="rounded border border-gray-200 bg-white p-10 text-center text-gray-500">
          队列为空。新上传会自动进入这里。
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {rows.map((w) => (
            <ReviewCard
              key={w.id}
              wallpaper={w}
              onApprove={() => approve(w.id)}
              onReject={() => reject(w.id)}
              busy={actingID === w.id}
            />
          ))}
        </div>
      )}

      {total > limit && (
        <div className="flex items-center justify-center gap-3 mt-6 text-sm">
          <button
            disabled={page <= 1}
            onClick={() => setPage((p) => p - 1)}
            className="px-3 py-1 border border-gray-300 rounded disabled:opacity-40"
          >
            ← Prev
          </button>
          <span className="text-gray-500">
            Page {page} of {Math.max(1, Math.ceil(total / limit))}
          </span>
          <button
            disabled={page * limit >= total}
            onClick={() => setPage((p) => p + 1)}
            className="px-3 py-1 border border-gray-300 rounded disabled:opacity-40"
          >
            Next →
          </button>
        </div>
      )}
    </div>
  );
}

function ReviewCard({
  wallpaper,
  onApprove,
  onReject,
  busy,
}: {
  wallpaper: AdminWallpaperRow;
  onApprove: () => void;
  onReject: () => void;
  busy: boolean;
}) {
  const isVideo = (wallpaper.file_type || '').startsWith('video/');
  return (
    <div className="rounded-lg border border-gray-200 bg-white overflow-hidden flex flex-col">
      <div className="aspect-[4/3] bg-gray-100 relative">
        {isVideo && wallpaper.original_url ? (
          <video
            src={wallpaper.original_url}
            poster={wallpaper.preview_url || wallpaper.thumb_url}
            controls
            muted
            playsInline
            preload="metadata"
            className="absolute inset-0 w-full h-full object-contain bg-black"
          />
        ) : (
          <img
            src={wallpaper.preview_url || wallpaper.thumb_url || wallpaper.original_url}
            alt=""
            className="absolute inset-0 w-full h-full object-cover"
            loading="lazy"
          />
        )}
        {isVideo && (
          <span className="absolute top-2 left-2 px-2 py-0.5 text-[10px] font-semibold rounded bg-black/60 text-white">
            VIDEO
          </span>
        )}
      </div>
      <div className="p-4 flex-1 flex flex-col gap-2">
        <div className="text-xs text-gray-500">
          #{wallpaper.id} · user {wallpaper.user_id} · {new Date(wallpaper.created_at).toLocaleString()}
        </div>
        <div className="text-sm text-gray-900 line-clamp-2 min-h-[2.5em]">
          {wallpaper.title || <span className="text-gray-400 italic">untitled</span>}
        </div>
        {wallpaper.description && (
          <div className="text-xs text-gray-600 line-clamp-2">{wallpaper.description}</div>
        )}
        <div className="text-xs text-gray-500">
          {wallpaper.width}×{wallpaper.height} · {(wallpaper.file_size / 1024 / 1024).toFixed(1)} MB · {wallpaper.file_type || '—'}
        </div>
        <div className="flex gap-2 pt-2 mt-auto">
          <button
            onClick={onApprove}
            disabled={busy}
            className="flex-1 px-3 py-1.5 text-sm bg-green-600 text-white rounded hover:bg-green-700 disabled:opacity-50"
          >
            Approve
          </button>
          <button
            onClick={onReject}
            disabled={busy}
            className="flex-1 px-3 py-1.5 text-sm bg-red-600 text-white rounded hover:bg-red-700 disabled:opacity-50"
          >
            Reject
          </button>
        </div>
      </div>
    </div>
  );
}
