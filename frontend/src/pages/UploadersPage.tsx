import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { AiOutlinePicture, AiOutlineLeft, AiOutlineRight } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { UserListItem } from '../types';
import { getUsers } from '../api';
import Spinner from '../components/Spinner';
import usePageTitle from '../hooks/usePageTitle';

type SortKey = 'recent' | 'uploads' | 'coins';

function formatDate(dateStr: string): string {
  return new Date(dateStr).toLocaleDateString('en-US', { year: 'numeric', month: 'short' });
}

export default function UploadersPage() {
  usePageTitle('Uploaders');
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [sort, setSort] = useState<SortKey>('recent');
  const limit = 24;

  const fetchUsers = useCallback(async (p: number, s: SortKey) => {
    setLoading(true);
    try {
      const res = await getUsers({ page: p, limit, sort: s === 'recent' ? '' : s });
      setUsers(res.data.data.items ?? []);
      setTotal(res.data.data.total);
    } catch {
      toast.error('Failed to load uploaders');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchUsers(page, sort);
  }, [page, sort, fetchUsers]);

  const handleSort = (key: SortKey) => {
    if (key === sort) return;
    setSort(key);
    setPage(1);
  };

  const totalPages = Math.ceil(total / limit);

  const sortOptions: { key: SortKey; label: string }[] = [
    { key: 'recent', label: 'Newest' },
    { key: 'uploads', label: 'Most Uploads' },
    { key: 'coins', label: 'Most Coins' },
  ];

  return (
    <div className="px-6 py-4">
      <div className="flex flex-wrap items-center justify-between gap-4 mb-6">
        <h1 className="text-xl font-bold text-slate-900 dark:text-white">Uploaders</h1>
        <div className="flex items-center h-10 bg-ws-bg dark:bg-ws-dark-card rounded-lg overflow-hidden border border-ws-border dark:border-white/10">
          {sortOptions.map((opt) => (
            <button
              key={opt.key}
              onClick={() => handleSort(opt.key)}
              className={`px-4 h-full text-sm font-medium transition-colors ${
                sort === opt.key
                  ? 'bg-ws-purple text-white'
                  : 'text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple dark:hover:text-white'
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <Spinner />
      ) : users.length === 0 ? (
        <div className="text-center py-20 text-ws-muted dark:text-ws-dark-muted">No uploaders yet.</div>
      ) : (
        <>
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
            {users.map((u) => (
              <Link
                key={u.id}
                to={`/user/${u.username}`}
                className="group flex flex-col items-center p-5 rounded-xl bg-white dark:bg-ws-dark-card border border-ws-border dark:border-white/5 hover:border-ws-purple/30 dark:hover:border-purple-800/30 hover:shadow-md transition-all duration-200"
              >
                {u.avatar_url ? (
                  <img
                    src={u.avatar_url}
                    alt=""
                    className="w-16 h-16 rounded-full object-cover ring-2 ring-white dark:ring-ws-dark-card shadow-sm group-hover:ring-ws-purple/30 transition-all"
                  />
                ) : (
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-ws-purple-light to-purple-200 dark:from-ws-dark-active dark:to-purple-900/40 flex items-center justify-center text-xl font-bold text-ws-purple dark:text-purple-400 ring-2 ring-white dark:ring-ws-dark-card shadow-sm group-hover:ring-ws-purple/30 transition-all">
                    {(u.nickname || u.username).charAt(0).toUpperCase()}
                  </div>
                )}
                <h3 className="mt-3 text-sm font-semibold text-slate-900 dark:text-white truncate max-w-full group-hover:text-ws-purple transition-colors">
                  {u.nickname || u.username}
                </h3>
                <div className="flex items-center gap-3 mt-2 text-xs text-ws-muted dark:text-ws-dark-muted">
                  <span className="flex items-center gap-1" title="Uploads">
                    <AiOutlinePicture size={13} />
                    {u.wallpaper_count}
                  </span>
                  <span title="Coins">💰 {u.coins}</span>
                </div>
                <p className="mt-1.5 text-[11px] text-ws-muted/60 dark:text-ws-dark-muted/60">
                  Joined {formatDate(u.created_at)}
                </p>
              </Link>
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
