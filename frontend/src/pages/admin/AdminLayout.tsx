import { Outlet, Link, useLocation, Navigate } from 'react-router-dom';
import { useEffect, useState } from 'react';
import { useAuthStore } from '../../store/auth';
import client from '../../api/client';

const NAV = [
  { to: '/admin', label: '总览', exact: true },
  { to: '/admin/analytics', label: '流量' },
  { to: '/admin/wallpapers', label: '壁纸' },
  { to: '/admin/collections', label: '合集' },
  { to: '/admin/weekly-picks', label: '每周推荐' },
  { to: '/admin/integrations', label: '推广集成' },
  { to: '/admin/users', label: '用户' },
  { to: '/admin/reports', label: '举报' },
  { to: '/admin/workers', label: 'Worker' },
];

// Verify with the server that this user is still an admin (the localStorage
// is_admin flag can be stale if the user was demoted while logged in).
function useAdminProbe() {
  const [state, setState] = useState<'loading' | 'ok' | 'forbidden'>('loading');
  useEffect(() => {
    let alive = true;
    client
      .get('/admin/overview')
      .then(() => { if (alive) setState('ok'); })
      .catch((err) => {
        if (!alive) return;
        if (err?.response?.status === 403) setState('forbidden');
        else setState('forbidden');
      });
    return () => { alive = false; };
  }, []);
  return state;
}

export default function AdminLayout() {
  const { isAuthenticated, user, logout } = useAuthStore();
  const location = useLocation();
  const probe = useAdminProbe();

  if (!isAuthenticated || !user) {
    return <Navigate to={`/login?redirect=${encodeURIComponent(location.pathname)}`} replace />;
  }
  if (probe === 'forbidden') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-slate-50 dark:bg-slate-950 text-slate-700 dark:text-slate-300">
        <div className="max-w-md w-full p-8 bg-white dark:bg-slate-900 rounded-xl shadow border border-slate-200 dark:border-slate-800 text-center">
          <h1 className="text-xl font-semibold mb-2">无权访问</h1>
          <p className="text-sm text-slate-500 dark:text-slate-400 mb-6">当前账号不是管理员。</p>
          <Link to="/" className="text-purple-600 hover:underline">返回首页</Link>
        </div>
      </div>
    );
  }
  if (probe === 'loading') {
    return <div className="min-h-screen flex items-center justify-center text-slate-400">Loading…</div>;
  }

  const isActive = (to: string, exact?: boolean) =>
    exact ? location.pathname === to : location.pathname.startsWith(to);

  return (
    <div className="min-h-screen flex bg-slate-50 dark:bg-slate-950 text-slate-900 dark:text-slate-100">
      <aside className="w-56 flex-shrink-0 bg-white dark:bg-slate-900 border-r border-slate-200 dark:border-slate-800 flex flex-col">
        <div className="px-5 py-5 border-b border-slate-200 dark:border-slate-800">
          <div className="text-xs uppercase tracking-widest text-slate-400">Wallpaper</div>
          <div className="text-lg font-semibold mt-0.5">后台管理</div>
        </div>
        <nav className="flex-1 px-3 py-4 space-y-1">
          {NAV.map((item) => (
            <Link
              key={item.to}
              to={item.to}
              className={`block px-3 py-2 rounded-lg text-sm font-medium transition-colors ${
                isActive(item.to, item.exact)
                  ? 'bg-purple-50 dark:bg-purple-500/10 text-purple-700 dark:text-purple-300'
                  : 'text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800'
              }`}
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <div className="px-4 py-4 border-t border-slate-200 dark:border-slate-800 text-xs text-slate-500 space-y-2">
          <div className="truncate">{user.nickname || user.username}</div>
          <div className="flex items-center gap-2">
            <Link to="/" className="text-slate-500 hover:text-slate-900 dark:hover:text-white transition">回前台</Link>
            <span>·</span>
            <button onClick={logout} className="text-slate-500 hover:text-rose-500 transition">退出</button>
          </div>
        </div>
      </aside>

      <main className="flex-1 min-w-0">
        <Outlet />
      </main>
    </div>
  );
}
