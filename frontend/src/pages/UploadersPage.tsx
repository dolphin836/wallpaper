import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import type { UserListItem } from '../types';
import { getUsers } from '../api';
import PageMeta from '../components/PageMeta';
import Pagination from '../components/Pagination';
import Avatar from '../components/Avatar';
import { UploaderListSkeleton } from '../components/Skeletons';

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
    } catch {
      toast.error('Failed to load uploaders');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchUsers(page, sort); }, [page, sort, fetchUsers]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title="Uploaders"
        description="The people behind Wallpaper Exchange — top contributors and recent arrivals."
      />

      <div className="px-6 sm:px-10 pt-7">
        {/* Header */}
        <div className="flex items-end justify-between gap-6 flex-wrap mb-6">
          <div>
            <div className="kicker text-muted">Contributors · {total}</div>
            <h1 className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-ink">
              The people behind <span className="italic-d">the wall.</span>
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

        {/* List */}
        {loading && items.length === 0 ? (
          <UploaderListSkeleton count={6} />
        ) : items.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">No uploaders yet.</div>
        ) : (
          <div>
            {items.map((u) => <UploaderRow key={u.id} u={u} />)}
          </div>
        )}

        <Pagination current={page} total={totalPages} onChange={setPage} />
      </div>
    </div>
  );
}

function UploaderRow({ u }: { u: UserListItem }) {
  const display = u.nickname || u.username;
  // We don't aggregate per-user download / like totals in the schema yet
  // (counts live on each wallpaper row), so the design's 3-column stats
  // grid is reduced to just UPLOADS until we have honest numbers for the
  // other two.
  const works = u.recent_thumbs ?? [];

  return (
    <Link
      to={`/user/${u.username}`}
      className="grid grid-cols-[68px_1fr] md:grid-cols-[68px_1fr_auto] lg:grid-cols-[68px_1fr_auto_220px] xl:grid-cols-[68px_1fr_auto_280px] gap-4 md:gap-5 lg:gap-6 items-center py-5 border-b border-hair no-underline text-ink hover:bg-paper-2 transition-colors"
    >
      <Avatar
        src={u.avatar_url}
        name={display}
        size={68}
        className="border border-hair flex-shrink-0"
      />

      <div className="min-w-0">
        <div className="display text-[22px] sm:text-[24px] leading-tight">{display}</div>
        <div className="mono text-[11px] tracking-[0.04em] text-muted mt-1">
          @{u.username} <span className="mx-1.5">·</span> joined {formatJoined(u.created_at)}
        </div>
        {u.bio && (
          <p className="text-[13px] text-ink-2 leading-snug mt-2 max-w-[460px] line-clamp-2">
            {u.bio}
          </p>
        )}
      </div>

      <div className="hidden md:block text-right mono">
        <div className="text-[9px] tracking-[0.14em] text-muted">UPLOADS</div>
        <div className="display text-[22px] leading-none mt-1">{formatNumber(u.wallpaper_count)}</div>
      </div>

      {/* Show the 3 most recent thumbnails. Backend returns up to 3 per
          user via `recent_thumbs`, so the slot count exactly matches the
          API contract — no padding logic needed for the common path. */}
      <div className="hidden lg:grid grid-cols-3 gap-1.5">
        {works.length === 0
          ? Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="aspect-square bg-paper-2 border border-hair" />
            ))
          : works.slice(0, 3).map((thumb, i) => (
              <div key={i} className="aspect-square border border-hair overflow-hidden bg-paper-3">
                <img src={thumb} alt="" loading="lazy" className="w-full h-full object-cover" />
              </div>
            ))}
        {works.length > 0 && works.length < 3 &&
          Array.from({ length: 3 - works.length }).map((_, i) => (
            <div key={`pad-${i}`} className="aspect-square bg-paper-2 border border-hair" />
          ))}
      </div>
    </Link>
  );
}
