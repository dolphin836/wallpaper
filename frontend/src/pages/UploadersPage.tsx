import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlineLeft, AiOutlineRight } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { UserListItem } from '../types';
import { getUsers } from '../api';
import Spinner from '../components/Spinner';
import PageMeta from '../components/PageMeta';
import Avatar from '../components/Avatar';

export default function UploadersPage() {
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const limit = 24;

  const fetchUsers = useCallback(async (p: number) => {
    setLoading(true);
    try {
      // Hard-coded to `uploads` — we removed the sort toggle. Follow feature
      // doesn't exist yet, so popularity by upload count is the only signal
      // we have to rank contributors.
      const res = await getUsers({ page: p, limit, sort: 'uploads' });
      setUsers(res.data.data.items ?? []);
      setTotal(res.data.data.total);
    } catch {
      toast.error('Failed to load uploaders');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchUsers(page);
  }, [page, fetchUsers]);

  const totalPages = Math.ceil(total / limit);

  // Offset of the first row on the current page, so rank numbers continue
  // across paginated pages (page 2 starts at 25, not 1).
  const rankOffset = (page - 1) * limit;

  return (
    <div className="px-6 py-8 max-w-[1200px] mx-auto w-full">
      <PageMeta
        title="Uploaders"
        description="Discover top contributors on Wallpaper Exchange — the creative minds behind the most popular wallpapers."
      />

      {/* Page header */}
      <div className="flex flex-col gap-1.5 mb-8">
        <h1 className="text-[28px] sm:text-[32px] font-bold tracking-tight text-slate-900 dark:text-white leading-tight">
          Top Uploaders
        </h1>
        <p className="text-sm sm:text-base text-ws-muted dark:text-ws-dark-muted">
          Discover the creative minds behind the most popular wallpapers.
        </p>
      </div>

      {loading && users.length === 0 ? (
        <Spinner />
      ) : users.length === 0 ? (
        <div className="text-center py-20 text-ws-muted dark:text-ws-dark-muted">No uploaders yet.</div>
      ) : (
        <>
          <div className="flex flex-col bg-white dark:bg-ws-dark-card rounded-xl border border-ws-border dark:border-white/5 overflow-hidden">
            {users.map((u, i) => (
              <UploaderRow key={u.id} user={u} rank={rankOffset + i + 1} isLast={i === users.length - 1} />
            ))}
          </div>

          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-2 mt-8">
              <button
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={page <= 1}
                className="p-2 rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              >
                <AiOutlineLeft size={16} />
              </button>
              <span className="px-3 text-sm text-ws-muted dark:text-ws-dark-muted">
                {page} / {totalPages}
              </span>
              <button
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={page >= totalPages}
                className="p-2 rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
              >
                <AiOutlineRight size={16} />
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}

function UploaderRow({ user: u, rank, isLast }: { user: UserListItem; rank: number; isLast: boolean }) {
  const display = u.nickname || u.username;
  const thumbs = (u.recent_thumbs || []).slice(0, 3);

  return (
    <div
      className={`flex items-center justify-between p-4 md:px-6 md:py-4 min-h-[88px] hover:bg-ws-bg dark:hover:bg-white/[0.02] transition-colors ${
        isLast ? '' : 'border-b border-ws-border dark:border-white/5'
      }`}
    >
      {/* Left: rank + avatar + name + uploads */}
      <div className="flex items-center gap-4 md:gap-6 min-w-0 flex-1">
        <span className="text-[#a0a0ab] dark:text-ws-dark-muted text-sm font-semibold w-6 text-center tabular-nums shrink-0">
          {String(rank).padStart(2, '0')}
        </span>
        <Avatar
          src={u.avatar_url}
          name={display}
          size={48}
          alt={display}
          className="ring-1 ring-ws-border dark:ring-white/5 shadow-sm shrink-0"
        />
        <div className="flex flex-col min-w-0">
          <Link
            to={`/user/${u.username}`}
            className="text-slate-900 dark:text-white text-base font-bold leading-tight truncate hover:text-ws-purple transition-colors"
          >
            {display}
          </Link>
          <p className="text-ws-muted dark:text-ws-dark-muted text-xs font-medium mt-0.5">
            {u.wallpaper_count} 张壁纸
          </p>
        </div>
      </div>

      {/* Middle: 3-thumb preview strip — only on wide screens, hidden on
          tablet/phone to keep the row compact. */}
      <div className="hidden lg:flex items-center gap-2 mx-6 shrink-0">
        {thumbs.length > 0 ? (
          thumbs.map((src, i) => (
            <Link
              key={i}
              to={`/user/${u.username}`}
              className="block h-12 w-20 rounded overflow-hidden bg-ws-bg dark:bg-ws-dark-bg"
              title="查看主页"
            >
              <img
                src={src}
                alt=""
                loading="lazy"
                decoding="async"
                className="w-full h-full object-cover"
              />
            </Link>
          ))
        ) : (
          // Empty slots to keep the row height consistent across users
          // that haven't uploaded yet, so the right-side button never
          // visually jumps left.
          <div className="h-12 w-[256px]" />
        )}
      </div>

      {/* Right: view-profile button (replaces the follow CTA from the design
          — follow isn't implemented yet, profile link is the closest action). */}
      <Link
        to={`/user/${u.username}`}
        className="px-4 py-1.5 rounded-lg border border-ws-purple text-ws-purple text-sm font-semibold hover:bg-ws-purple hover:text-white transition-colors w-[100px] text-center shrink-0"
      >
        查看主页
      </Link>
    </div>
  );
}
