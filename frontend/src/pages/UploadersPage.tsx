import { useState, useEffect, useCallback } from 'react';
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

function formatJoined(iso: string): string {
  if (!iso) return '';
  const d = new Date(iso);
  return d.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
}

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
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
            {items.map((u) => <UploaderWallCard key={u.id} u={u} />)}
          </div>
        )}

        <Pagination current={page} total={totalPages} onChange={setPage} />
      </div>
    </div>
  );
}

// Wall-of-work card — the contributor's actual wallpapers, tiled
// 3×3 (or partial). Footer strip at the bottom carries avatar +
// handle + count. Click → user profile. Hover: thumbs scale 1.02,
// footer brightens.
function UploaderWallCard({ u }: { u: UserListItem }) {
  const display = u.nickname || u.username;
  const thumbs = (u.recent_thumbs ?? []).slice(0, 9);
  // Always 9 cells; empty slots fill with a paper-2 tile so the
  // mosaic geometry stays consistent regardless of upload count.
  const cells = Array.from({ length: 9 }, (_, i) => thumbs[i] || null);
  return (
    <Link to={`/user/${u.username}`} className="uploader-wall no-underline text-ink">
      <div className="uploader-wall-grid" aria-hidden>
        {cells.map((src, i) => (
          <div key={i} className="uploader-wall-cell">
            {src
              ? <img src={src} alt="" loading="lazy" />
              : <div className="uploader-wall-empty" />}
          </div>
        ))}
      </div>
      <div className="uploader-wall-strip">
        <Avatar
          src={u.avatar_url}
          name={display}
          size={36}
          className="flex-shrink-0"
        />
        <div className="min-w-0 flex-1">
          <div className="uploader-wall-name">{display}</div>
          <div className="uploader-wall-meta">
            @{u.username} · joined {formatJoined(u.created_at)}
          </div>
        </div>
        <div className="uploader-wall-count">
          <div className="uploader-wall-count-num">{formatNumber(u.wallpaper_count)}</div>
          <div className="uploader-wall-count-label">{u.wallpaper_count === 1 ? 'upload' : 'uploads'}</div>
        </div>
      </div>
    </Link>
  );
}

// Skeleton variant — same chrome as the real wall card, paper-2
// shimmer for cells.
function UploaderWallSkeleton({ count }: { count: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-5">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="uploader-wall">
          <div className="uploader-wall-grid">
            {Array.from({ length: 9 }).map((__, j) => (
              <div key={j} className="uploader-wall-cell">
                <div className="uploader-wall-empty skeleton-card" />
              </div>
            ))}
          </div>
          <div className="uploader-wall-strip is-skel">
            <div className="uploader-wall-skel-avatar" />
            <div className="flex-1">
              <div className="uploader-wall-skel-bar w-1/2 h-3" />
              <div className="uploader-wall-skel-bar w-2/3 h-2 mt-2" />
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
