import { useEffect, useState, useCallback } from 'react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import * as admin from '../../api/admin';
import {
  Card,
  PageHeader,
  Spinner,
  Empty,
  Pagination,
  StatusBadge,
  fmtDate,
} from './components';
import { useAuthStore } from '../../store/auth';

type Row = {
  id: number;
  username: string;
  email: string;
  nickname: string;
  avatar_url: string;
  coins: number;
  status: number;
  is_admin: boolean;
  created_at: string;
  wallpaper_count: number;
};

export default function UsersPage() {
  const [items, setItems] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [limit] = useState(20);
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState<number | -1>(-1);
  const [loading, setLoading] = useState(false);
  const me = useAuthStore((s) => s.user);

  const fetchList = useCallback(() => {
    setLoading(true);
    admin
      .listAdminUsers({
        page,
        limit,
        search: search || undefined,
        status: status >= 0 ? status : undefined,
      })
      .then((r) => {
        setItems(r.data.data.items as Row[]);
        setTotal(r.data.data.total);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '加载失败'))
      .finally(() => setLoading(false));
  }, [page, limit, search, status]);

  useEffect(() => { fetchList(); }, [fetchList]);

  const toggleAdmin = (row: Row) => {
    if (row.id === me?.id && row.is_admin) {
      toast.error('不能撤销自己的管理员权限');
      return;
    }
    if (!confirm(row.is_admin ? `撤销 @${row.username} 的管理员？` : `授予 @${row.username} 管理员权限？`)) return;
    admin.setAdminUserAdmin(row.id, !row.is_admin).then(() => {
      toast.success('已更新');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  const setActive = (row: Row, newStatus: number) => {
    if (row.id === me?.id && newStatus !== 1) {
      toast.error('不能禁用自己');
      return;
    }
    admin.setAdminUserStatus(row.id, newStatus).then(() => {
      toast.success('已更新');
      fetchList();
    }).catch((e) => toast.error(e?.response?.data?.message || '操作失败'));
  };

  return (
    <>
      <PageHeader title="用户管理" subtitle={`共 ${total} 个`} />
      <div className="px-8 pb-8 space-y-4">
        <Card>
          <div className="px-5 py-3 flex flex-wrap gap-3 items-center text-sm">
            <input
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              placeholder="搜索用户名 / 邮箱 / 昵称"
              className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 w-72"
            />
            <select value={status} onChange={(e) => { setStatus(Number(e.target.value)); setPage(1); }} className="px-3 py-1.5 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900">
              <option value={-1}>全部状态</option>
              <option value={1}>正常</option>
              <option value={0}>禁用</option>
            </select>
          </div>

          {loading ? <Spinner /> : items.length === 0 ? <Empty>无用户</Empty> : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 dark:bg-slate-800/50 text-slate-500 text-xs uppercase tracking-wide">
                  <tr>
                    <th className="text-left px-4 py-2 font-medium">用户</th>
                    <th className="text-left px-4 py-2 font-medium">邮箱</th>
                    <th className="text-left px-4 py-2 font-medium">权限</th>
                    <th className="text-left px-4 py-2 font-medium">状态</th>
                    <th className="text-right px-4 py-2 font-medium">数据</th>
                    <th className="text-left px-4 py-2 font-medium">注册时间</th>
                    <th className="text-right px-4 py-2 font-medium">操作</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 dark:divide-slate-800">
                  {items.map((u) => (
                    <tr key={u.id} className="hover:bg-slate-50 dark:hover:bg-slate-800/30">
                      <td className="px-4 py-2">
                        <div className="flex items-center gap-2">
                          <div className="w-8 h-8 rounded-full bg-slate-200 dark:bg-slate-700 overflow-hidden flex-shrink-0">
                            {u.avatar_url && <img src={u.avatar_url} alt="" className="w-full h-full object-cover" />}
                          </div>
                          <div className="min-w-0">
                            <Link to={`/user/${u.username}`} className="block font-medium truncate hover:underline">{u.nickname || u.username}</Link>
                            <div className="text-xs text-slate-400 truncate">@{u.username} · #{u.id}</div>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-2 text-xs text-slate-500 truncate max-w-xs">{u.email}</td>
                      <td className="px-4 py-2">
                        {u.is_admin ? <StatusBadge label="管理员" tone="info" /> : <span className="text-xs text-slate-400">普通</span>}
                      </td>
                      <td className="px-4 py-2">
                        {u.status === 1 ? <StatusBadge label="正常" tone="good" /> : <StatusBadge label="禁用" tone="bad" />}
                      </td>
                      <td className="px-4 py-2 text-right text-xs text-slate-500 whitespace-nowrap">
                        <div>上传 {u.wallpaper_count}</div>
                        <div>金币 {u.coins}</div>
                      </td>
                      <td className="px-4 py-2 text-xs text-slate-500 whitespace-nowrap">{fmtDate(u.created_at)}</td>
                      <td className="px-4 py-2 text-right whitespace-nowrap">
                        <button onClick={() => toggleAdmin(u)} className="text-xs text-purple-600 hover:underline mr-3">{u.is_admin ? '撤销管理员' : '设为管理员'}</button>
                        {u.status === 1
                          ? <button onClick={() => setActive(u, 0)} className="text-xs text-rose-500 hover:underline">禁用</button>
                          : <button onClick={() => setActive(u, 1)} className="text-xs text-emerald-600 hover:underline">启用</button>}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          <Pagination page={page} limit={limit} total={total} onChange={setPage} />
        </Card>
      </div>
    </>
  );
}
