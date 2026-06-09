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
  const [granting, setGranting] = useState<Row | null>(null);
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

  const applyGrantedBalance = (userID: number, balance: number) => {
    setItems((rows) => rows.map((row) => (row.id === userID ? { ...row, coins: balance } : row)));
    setGranting(null);
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
                        <button onClick={() => setGranting(u)} className="text-xs text-amber-600 hover:underline mr-3">赠送金币</button>
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
      {granting && (
        <GrantCoinsModal
          user={granting}
          onClose={() => setGranting(null)}
          onGranted={applyGrantedBalance}
        />
      )}
    </>
  );
}

function GrantCoinsModal({
  user,
  onClose,
  onGranted,
}: {
  user: Row;
  onClose: () => void;
  onGranted: (userID: number, balance: number) => void;
}) {
  const [amount, setAmount] = useState('100');
  const [description, setDescription] = useState('系统赠送');
  const [saving, setSaving] = useState(false);
  const parsedAmount = Number(amount);
  const validAmount = Number.isInteger(parsedAmount) && parsedAmount > 0 && parsedAmount <= 1_000_000;
  const nextBalance = validAmount ? user.coins + parsedAmount : user.coins;

  const submit = () => {
    if (!validAmount) {
      toast.error('请输入 1 到 1000000 之间的整数');
      return;
    }
    setSaving(true);
    admin
      .grantAdminUserCoins(user.id, {
        amount: parsedAmount,
        description: description.trim() || '系统赠送',
      })
      .then((r) => {
        toast.success(`已赠送 ${r.data.data.amount} 金币`);
        onGranted(user.id, r.data.data.balance);
      })
      .catch((e) => toast.error(e?.response?.data?.message || '赠送失败'))
      .finally(() => setSaving(false));
  };

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-slate-900 rounded-xl w-full max-w-md overflow-hidden shadow-2xl">
        <div className="px-5 py-3 border-b border-slate-200 dark:border-slate-800 flex justify-between items-center">
          <div>
            <h3 className="font-semibold">赠送金币</h3>
            <p className="text-xs text-slate-500 mt-0.5">
              @{user.username} · 当前 {user.coins} 金币
            </p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-700 dark:hover:text-slate-200">×</button>
        </div>

        <div className="p-5 space-y-4">
          <label className="block text-sm">
            <div className="text-slate-500 mb-1">赠送数量</div>
            <input
              type="number"
              min={1}
              max={1_000_000}
              step={1}
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950"
            />
          </label>

          <label className="block text-sm">
            <div className="text-slate-500 mb-1">流水备注</div>
            <input
              value={description}
              maxLength={256}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full px-3 py-2 rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-950"
              placeholder="系统赠送"
            />
          </label>

          <div className="rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-900 dark:border-amber-900/40 dark:bg-amber-900/20 dark:text-amber-200">
            <div className="flex justify-between">
              <span>赠送后余额</span>
              <strong>{nextBalance} 金币</strong>
            </div>
            <p className="mt-1 text-xs opacity-80">会写入用户金币流水，类型为 admin_grant。</p>
          </div>
        </div>

        <div className="px-5 py-3 border-t border-slate-200 dark:border-slate-800 flex justify-end gap-2">
          <button onClick={onClose} className="px-4 py-1.5 rounded text-sm text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800">取消</button>
          <button onClick={submit} disabled={saving || !validAmount} className="px-4 py-1.5 rounded text-sm bg-amber-600 hover:bg-amber-700 text-white disabled:opacity-60">
            {saving ? '赠送中...' : '确认赠送'}
          </button>
        </div>
      </div>
    </div>
  );
}
