import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import {
  AiOutlineMenu,
  AiOutlineClose,
  AiOutlineCompass,
  AiOutlineAppstore,
  AiOutlineCloudUpload,
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

const ICON_BTN = 'p-2 rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-150';

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

  const sidebarNav = (
    <>
      {/* Brand */}
      <div className="px-5 pt-6 pb-8">
        <Link to="/" className="block">
          <div className="text-lg font-bold tracking-tight text-gray-900 dark:text-white leading-tight">
            Wallpaper
          </div>
          <div className="text-lg font-bold tracking-tight text-indigo-600 dark:text-indigo-400 leading-tight">
            Exchange
          </div>
        </Link>
      </div>

      {/* Nav */}
      <nav className="flex-1 px-3 space-y-1">
        {navItems.map(({ to, label, icon: Icon }) => {
          const active = isActive(to);
          return (
            <Link
              key={to}
              to={to}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors duration-150 ${
                active
                  ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 hover:text-gray-900 dark:hover:text-gray-200'
              }`}
            >
              <Icon size={20} />
              {label}
            </Link>
          );
        })}
      </nav>

      {/* Copyright */}
      <div className="px-5 pb-4 pt-2">
        <p className="text-[11px] text-gray-400 dark:text-gray-500">
          &copy; {new Date().getFullYear()} Wallpaper Exchange
        </p>
      </div>
    </>
  );

  return (
    <div className="min-h-screen flex bg-gray-50 dark:bg-gray-900 dark:text-gray-100 transition-colors duration-200">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex md:flex-col md:w-56 lg:w-60 fixed inset-y-0 left-0 bg-white dark:bg-gray-800 border-r border-gray-200 dark:border-gray-700 z-40">
        {sidebarNav}
      </aside>

      {/* Mobile sidebar drawer */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setSidebarOpen(false)} />
          <aside className="relative w-64 h-full flex flex-col bg-white dark:bg-gray-800 shadow-xl">
            <button
              onClick={() => setSidebarOpen(false)}
              className="absolute top-4 right-4 p-1.5 rounded-lg text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700"
            >
              <AiOutlineClose size={20} />
            </button>
            {sidebarNav}
          </aside>
        </div>
      )}

      {/* Main column */}
      <div className="flex-1 md:ml-56 lg:ml-60 flex flex-col min-h-screen">
        {/* Top bar */}
        <header className="sticky top-0 z-30 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 h-14 flex items-center justify-between px-4 sm:px-6">
          {/* Left: mobile hamburger + brand */}
          <div className="flex items-center gap-3">
            <button onClick={() => setSidebarOpen(true)} className="md:hidden p-1.5 text-gray-600 dark:text-gray-300">
              <AiOutlineMenu size={22} />
            </button>
            <Link to="/" className="md:hidden font-bold text-gray-900 dark:text-white">
              Wallpaper <span className="text-indigo-600 dark:text-indigo-400">Exchange</span>
            </Link>
          </div>

          {/* Right: actions */}
          <div className="flex items-center gap-1.5">
            <button onClick={toggleDark} className={ICON_BTN} title={dark ? 'Light Mode' : 'Dark Mode'}>
              {dark ? <BsSun size={18} /> : <BsMoon size={18} />}
            </button>

            {isAuthenticated && user ? (
              <>
                <Link to="/upload" className={ICON_BTN} title="Upload">
                  <AiOutlineCloudUpload size={20} />
                </Link>

                <Link
                  to={`/user/${user.id}`}
                  className="flex items-center gap-1.5 ml-1 px-2 py-1.5 rounded-full hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-150"
                  title="Profile"
                >
                  <span className="text-sm">💰</span>
                  <span className="text-xs font-semibold bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">
                    {user.coins ?? 0}
                  </span>
                </Link>

                <Link
                  to={`/user/${user.id}`}
                  className="ml-0.5 flex-shrink-0"
                  title={user.nickname || user.username}
                >
                  {user.avatar_url ? (
                    <img src={user.avatar_url} alt="" className="w-8 h-8 rounded-full object-cover" />
                  ) : (
                    <div className="w-8 h-8 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold text-sm">
                      {(user.nickname || user.username).charAt(0).toUpperCase()}
                    </div>
                  )}
                </Link>

                <button onClick={handleLogout} className={ICON_BTN} title="Logout">
                  <AiOutlineLogout size={18} />
                </button>
              </>
            ) : (
              <>
                <Link
                  to="/login"
                  className="px-4 py-1.5 text-sm font-medium text-indigo-600 hover:bg-indigo-50 dark:hover:bg-indigo-900/20 rounded-lg transition-colors duration-150"
                >
                  Login
                </Link>
                <Link
                  to="/register"
                  className="px-4 py-1.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors duration-150"
                >
                  Register
                </Link>
              </>
            )}
          </div>
        </header>

        {/* Page content */}
        <main className="flex-1">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
