import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import {
  AiOutlineMenu,
  AiOutlineClose,
  AiOutlineCompass,
  AiOutlineAppstore,
  AiOutlineLeft,
  AiOutlineRight,
  AiOutlineSearch,
  AiOutlineLogout,
} from 'react-icons/ai';
import { BsSun, BsMoon } from 'react-icons/bs';

function useDarkMode() {
  const [dark, setDark] = useState(() => {
    if (typeof window === 'undefined') return false;
    const stored = localStorage.getItem('theme');
    if (stored) return stored === 'dark';
    return window.matchMedia('(prefers-color-scheme: dark)').matches;
  });

  useEffect(() => {
    const root = document.documentElement;
    if (dark) {
      root.classList.add('dark');
      localStorage.setItem('theme', 'dark');
    } else {
      root.classList.remove('dark');
      localStorage.setItem('theme', 'light');
    }
  }, [dark]);

  return [dark, () => setDark((d) => !d)] as const;
}

export default function Layout() {
  const { isAuthenticated, user, logout } = useAuthStore();
  const navigate = useNavigate();
  const location = useLocation();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [dark, toggleDark] = useDarkMode();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  useEffect(() => {
    setSidebarOpen(false);
  }, [location.pathname]);

  const navItems = [
    { to: '/', label: 'Discover', icon: AiOutlineCompass },
    { to: '/collections', label: 'Collections', icon: AiOutlineAppstore },
  ];

  const isActive = (path: string) => {
    if (path === '/') return location.pathname === '/';
    return location.pathname.startsWith(path);
  };

  const showBackForward = location.pathname !== '/';

  const sidebarNav = (
    <>
      {/* Brand */}
      <div className="p-6 flex items-center gap-2.5">
        <div className="w-7 h-7 border-2 border-slate-800 dark:border-white flex items-center justify-center rotate-45 flex-shrink-0">
          <div className="w-full h-px bg-slate-800 dark:bg-white -rotate-45" />
        </div>
        <Link to="/" className="text-base font-semibold tracking-wide leading-tight text-slate-800 dark:text-white">
          Wallpaper<br />Exchange
        </Link>
      </div>

      {/* Nav */}
      <nav className="flex-1 mt-4 px-4 space-y-1">
        {navItems.map(({ to, label, icon: Icon }) => {
          const active = isActive(to);
          return (
            <Link
              key={to}
              to={to}
              className={`flex items-center gap-3.5 px-4 py-3 rounded-lg text-sm font-medium transition-colors duration-150 ${
                active
                  ? 'bg-ws-purple-light dark:bg-ws-dark-active text-ws-purple dark:text-purple-400 dark:border dark:border-purple-900'
                  : 'text-ws-muted dark:text-ws-dark-muted hover:bg-slate-50 dark:hover:bg-white/5'
              }`}
            >
              <Icon size={18} />
              {label}
            </Link>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="p-6 mt-auto border-t border-slate-50 dark:border-white/5 text-xs text-ws-muted dark:text-ws-dark-muted space-y-3">
        <Link to="/terms" className="block hover:text-slate-900 dark:hover:text-white transition-colors">Terms of Service</Link>
        <div className="flex items-center justify-between">
          <Link to="/privacy" className="hover:text-slate-900 dark:hover:text-white transition-colors">Privacy Policy</Link>
          <span className="w-2 h-2 rounded-full bg-ws-purple" />
        </div>
        <p className="text-[11px] opacity-60 pt-2">&copy; {new Date().getFullYear()} Wallpaper Exchange</p>
      </div>
    </>
  );

  return (
    <div className="min-h-screen flex bg-ws-bg dark:bg-ws-dark-bg text-slate-900 dark:text-white font-sans transition-colors duration-200">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex md:flex-col w-60 fixed inset-y-0 left-0 bg-white dark:bg-ws-dark-sidebar border-r border-ws-border dark:border-white/5 z-40">
        {sidebarNav}
      </aside>

      {/* Mobile sidebar drawer */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setSidebarOpen(false)} />
          <aside className="relative w-64 h-full flex flex-col bg-white dark:bg-ws-dark-sidebar shadow-xl">
            <button
              onClick={() => setSidebarOpen(false)}
              className="absolute top-4 right-4 p-1.5 rounded-lg text-ws-muted hover:bg-slate-100 dark:hover:bg-white/10"
            >
              <AiOutlineClose size={20} />
            </button>
            {sidebarNav}
          </aside>
        </div>
      )}

      {/* Main column */}
      <div className="flex-1 md:ml-60 flex flex-col min-h-screen">
        {/* Top header bar */}
        <header className="sticky top-0 z-30 h-[72px] dark:h-16 flex-shrink-0 flex items-center justify-between px-6 border-b border-ws-border dark:border-white/5 bg-white dark:bg-ws-dark-header">
          {/* Left: hamburger (mobile) + back/forward + search */}
          <div className="flex items-center gap-3 flex-1 max-w-2xl">
            <button onClick={() => setSidebarOpen(true)} className="md:hidden p-2 text-ws-muted dark:text-ws-dark-muted">
              <AiOutlineMenu size={22} />
            </button>

            {showBackForward && (
              <div className="flex items-center gap-1 mr-1">
                <button
                  onClick={() => navigate(-1)}
                  className="p-2 text-ws-muted dark:text-ws-dark-muted hover:text-slate-900 dark:hover:text-white border border-ws-border dark:border-transparent dark:bg-white/5 rounded-lg transition-colors"
                >
                  <AiOutlineLeft size={16} />
                </button>
                <button
                  onClick={() => navigate(1)}
                  className="p-2 text-slate-300 dark:text-ws-dark-muted/50 border border-ws-border dark:border-transparent dark:bg-white/5 rounded-lg cursor-not-allowed opacity-50"
                >
                  <AiOutlineRight size={16} />
                </button>
              </div>
            )}

            <div className="relative flex-1 hidden sm:block">
              <div className="absolute inset-y-0 left-3 flex items-center pointer-events-none">
                <AiOutlineSearch size={16} className="text-slate-400" />
              </div>
              <input
                type="text"
                placeholder="Search..."
                className="w-full bg-ws-bg dark:bg-ws-dark-card border-none rounded-xl py-2.5 pl-10 pr-4 text-sm focus:ring-1 focus:ring-ws-purple outline-none transition-all"
              />
            </div>

            {isAuthenticated && (
              <Link
                to="/upload"
                className="hidden sm:flex items-center gap-2 px-5 py-2.5 bg-ws-purple hover:bg-ws-purple-hover text-white text-sm font-semibold rounded-xl transition-colors shadow-sm"
              >
                <span className="text-lg font-light leading-none">+</span>
                Upload
              </Link>
            )}
          </div>

          {/* Right: utilities */}
          <div className="flex items-center gap-2 ml-4">
            <button
              onClick={toggleDark}
              className="p-2.5 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple dark:hover:text-white bg-ws-bg dark:bg-white/5 rounded-xl transition-colors"
              title={dark ? 'Light Mode' : 'Dark Mode'}
            >
              {dark ? <BsSun size={18} /> : <BsMoon size={18} />}
            </button>

            {isAuthenticated && user ? (
              <>
                <button
                  onClick={handleLogout}
                  className="p-2.5 text-ws-muted dark:text-ws-dark-muted hover:text-red-500 bg-ws-bg dark:bg-white/5 rounded-xl transition-colors border border-transparent hover:border-red-100 dark:hover:border-red-900/30"
                  title="Logout"
                >
                  <AiOutlineLogout size={18} />
                </button>
                <Link to={`/user/${user.id}`} className="ml-1 flex-shrink-0" title={user.nickname || user.username}>
                  {user.avatar_url ? (
                    <img
                      src={user.avatar_url}
                      alt=""
                      className="w-9 h-9 rounded-full dark:rounded-lg object-cover border-2 border-white dark:border-white/10 shadow-sm"
                    />
                  ) : (
                    <div className="w-9 h-9 rounded-full dark:rounded-lg bg-ws-purple-light dark:bg-ws-dark-active text-ws-purple dark:text-purple-400 flex items-center justify-center font-semibold text-sm border-2 border-white dark:border-white/10 shadow-sm">
                      {(user.nickname || user.username).charAt(0).toUpperCase()}
                    </div>
                  )}
                </Link>
              </>
            ) : (
              <>
                <Link
                  to="/login"
                  className="px-4 py-2 text-sm font-medium text-ws-purple hover:bg-ws-purple-light dark:hover:bg-ws-dark-active rounded-xl transition-colors"
                >
                  Login
                </Link>
                <Link
                  to="/register"
                  className="px-4 py-2 text-sm font-medium text-white bg-ws-purple hover:bg-ws-purple-hover rounded-xl transition-colors shadow-sm"
                >
                  Register
                </Link>
              </>
            )}
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1 overflow-y-auto bg-white dark:bg-ws-dark-bg">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
