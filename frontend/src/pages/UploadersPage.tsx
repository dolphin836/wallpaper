import { useState, useEffect, useCallback, useRef } from 'react';
import { Link } from 'react-router-dom';
import type { UserListItem } from '../types';
import { getUsers } from '../api';
import PageMeta from '../components/PageMeta';
import Pagination from '../components/Pagination';
import Avatar from '../components/Avatar';
import ErrorState from '../components/ErrorState';

type Sort = 'recent' | 'uploads' | 'coins';
const PAGE_SIZE = 12;

const SORT_TO_LABEL: Record<Sort, string> = {
  recent: 'Recently joined',
  uploads: 'Most uploaded',
  coins: 'Top this month',
};

function formatNumber(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(n >= 10_000 ? 0 : 1) + 'K';
  return n.toLocaleString();
}

// formatJoined removed — the new card design drops the explicit
// "joined …" line. Bring back if a future variant needs it.

export default function UploadersPage() {
  const [items, setItems] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  // The "Top this month" / "Most uploaded" / "Recently joined" chips map to
  // the existing sort options. "Following" is in the design but the product
  // has no follow feature yet, so we skip that chip.
  const [sort, setSort] = useState<Sort>('uploads');

  const fetchUsers = useCallback(async (p: number, s: Sort) => {
    setLoading(true);
    try {
      const apiSort = s === 'recent' ? '' : s;
      const res = await getUsers({ page: p, limit: PAGE_SIZE, sort: apiSort });
      setItems(res.data.data.items ?? []);
      setTotal(res.data.data.total);
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchUsers(page, sort); }, [page, sort, fetchUsers]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="uploaders-page min-h-full">
      <div className="uploaders-mesh" aria-hidden />
      <PageMeta
        title="Uploaders"
        description="The people behind Wallpaper Exchange — top contributors and recent arrivals."
      />

      <div className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-12">
        {/* Header */}
        <div className="flex items-end justify-between gap-6 flex-wrap mb-10">
          <div>
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              Contributors · {total}
            </div>
            <h1 className="display text-[clamp(36px,4vw,52px)] leading-[1.05] mt-2 tracking-[-0.012em] text-ink">
              The people behind <em className="uploaders-title-tail">the wall</em>.
            </h1>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            {(['coins', 'uploads', 'recent'] as Sort[]).map((key) => (
              <button
                key={key}
                onClick={() => { setSort(key); setPage(1); }}
                className={`px-3.5 py-1.5 rounded-full text-[12px] font-medium transition-colors ${
                  sort === key
                    ? 'bg-ink text-paper border border-ink'
                    : 'bg-paper text-ink-2 border border-hair hover:bg-paper-2 hover:border-ink-2'
                }`}
              >
                {SORT_TO_LABEL[key]}
              </button>
            ))}
          </div>
        </div>

        {/* Wall of work — each contributor is a 3×3 mosaic of their
            recent wallpapers, with a frosted strip at the bottom
            carrying avatar + handle + upload count. The work IS the
            card; scanning the page tells you what each person makes
            before you read a single name. */}
        {loading && items.length === 0 ? (
          <UploaderWallSkeleton count={9} />
        ) : error && items.length === 0 ? (
          <ErrorState />
        ) : items.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">No uploaders yet.</div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
            {items.map((u) => <UploaderWallCard key={u.id} u={u} />)}
          </div>
        )}

        <Pagination current={page} total={totalPages} onChange={setPage} />
      </div>
    </div>
  );
}

// Uploader card — one big wallpaper from this contributor as the
// face of the card, with a bottom scrim carrying avatar + handle +
// upload count. On hover the card cycles through up to N of their
// recent wallpapers (1.6s per frame) — the work itself flashes by
// so a single scan of the page reads as 'who makes what'.
function UploaderWallCard({ u }: { u: UserListItem }) {
  const display = u.nickname || u.username;
  const thumbs = (u.recent_thumbs ?? []).slice(0, 9);
  const [idx, setIdx] = useState(0);
  const hoverRef = useRef(false);
  useEffect(() => {
    if (thumbs.length < 2) return;
    let stop = false;
    const tick = () => {
      if (stop) return;
      if (hoverRef.current) setIdx((i) => (i + 1) % thumbs.length);
    };
    const id = window.setInterval(tick, 1600);
    return () => { stop = true; clearInterval(id); };
  }, [thumbs.length]);
  // Reset back to first thumb when the mouse leaves so the page
  // isn't paused mid-cycle next time you come back.
  const onEnter = () => { hoverRef.current = true; };
  const onLeave = () => { hoverRef.current = false; setIdx(0); };

  const cover = thumbs[idx];
  return (
    <Link
      to={`/user/${u.username}`}
      className="uploader-card no-underline"
      onMouseEnter={onEnter}
      onMouseLeave={onLeave}
    >
      {cover ? (
        <img
          src={cover}
          alt=""
          loading="lazy"
          className="uploader-card-img"
        />
      ) : (
        <div className="uploader-card-empty">
          <span className="mono text-[10px] tracking-[0.18em] uppercase text-muted">No uploads yet</span>
        </div>
      )}
      <div className="uploader-card-scrim" aria-hidden />
      <div className="uploader-card-info">
        <Avatar src={u.avatar_url} name={display} size={32} className="uploader-card-avatar" />
        <div className="uploader-card-text">
          <div className="uploader-card-name">{display}</div>
          <div className="uploader-card-handle">@{u.username}</div>
        </div>
        <div className="uploader-card-count">
          <span className="uploader-card-count-num">{formatNumber(u.wallpaper_count)}</span>
          <span className="uploader-card-count-label">{u.wallpaper_count === 1 ? 'upload' : 'uploads'}</span>
        </div>
      </div>
    </Link>
  );
}

// Skeleton variant — same chrome as the real card, paper-2
// shimmer over the image area + a soft strip skeleton.
function UploaderWallSkeleton({ count }: { count: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="uploader-card">
          <div className="uploader-card-img uploader-card-empty skeleton-card" />
          <div className="uploader-card-scrim" />
          <div className="uploader-card-info">
            <div className="uploader-card-avatar uploader-card-skel-avatar" />
            <div className="uploader-card-text">
              <div className="uploader-card-skel-bar" style={{ width: '60%', height: 12 }} />
              <div className="uploader-card-skel-bar mt-1" style={{ width: '40%', height: 8 }} />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
