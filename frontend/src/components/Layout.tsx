import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import { AiOutlineMenu, AiOutlineClose, AiOutlineCompass, AiOutlineAppstore, AiOutlineCloudUpload, AiOutlineLogin, AiOutlineUserAdd, AiOutlineLogout } from 'react-icons/ai';
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

  const sidebarContent = (
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

        {isAuthenticated && (
          <Link
            to="/upload"
            className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors duration-150 ${
              isActive('/upload')
                ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
                : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 hover:text-gray-900 dark:hover:text-gray-200'
            }`}
          >
            <AiOutlineCloudUpload size={20} />
            Upload
          </Link>
        )}
      </nav>

      {/* Bottom section */}
      <div className="px-3 pb-4 space-y-2 border-t border-gray-200 dark:border-gray-700 pt-4 mt-2">
        {/* Dark mode */}
        <button
          onClick={toggleDark}
          className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors duration-150"
        >
          {dark ? <BsSun size={18} /> : <BsMoon size={18} />}
          {dark ? 'Light Mode' : 'Dark Mode'}
        </button>

        {isAuthenticated && user ? (
          <>
            {/* Coins */}
            <Link
              to={`/user/${user.id}`}
              className="flex items-center gap-3 w-full px-3 py-2 rounded-lg text-sm font-semibold hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors duration-150"
            >
              <span className="text-base">💰</span>
              <span className="bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{user.coins ?? 0} coins</span>
            </Link>

            {/* User */}
            <Link
              to={`/user/${user.id}`}
              className={`flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium transition-colors duration-150 ${
                isActive(`/user/${user.id}`)
                  ? 'bg-indigo-50 text-indigo-700 dark:bg-indigo-900/30 dark:text-indigo-300'
                  : 'text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 hover:text-gray-900 dark:hover:text-gray-200'
              }`}
            >
              {user.avatar_url ? (
                <img src={user.avatar_url} alt="" className="w-7 h-7 rounded-full object-cover" />
              ) : (
                <div className="w-7 h-7 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold text-xs">
                  {(user.nickname || user.username).charAt(0).toUpperCase()}
                </div>
              )}
              <span className="truncate">{user.nickname || user.username}</span>
            </Link>

            {/* Logout */}
            <button
              onClick={handleLogout}
              className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors duration-150"
            >
              <AiOutlineLogout size={18} />
              Logout
            </button>
          </>
        ) : (
          <>
            <Link
              to="/login"
              className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium text-gray-600 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors duration-150"
            >
              <AiOutlineLogin size={18} />
              Login
            </Link>
            <Link
              to="/register"
              className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 justify-center transition-colors duration-150"
            >
              <AiOutlineUserAdd size={18} />
              Register
            </Link>
          </>
        )}
      </div>
    </>
  );

  return (
    <div className="min-h-screen flex bg-gray-50 dark:bg-gray-900 dark:text-gray-100 transition-colors duration-200">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex md:flex-col md:w-56 lg:w-60 fixed inset-y-0 left-0 bg-white dark:bg-gray-800 border-r border-gray-200 dark:border-gray-700 z-40">
        {sidebarContent}
      </aside>

      {/* Mobile overlay */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-40 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setSidebarOpen(false)} />
          <aside className="relative w-64 h-full flex flex-col bg-white dark:bg-gray-800 shadow-xl">
            <button
              onClick={() => setSidebarOpen(false)}
              className="absolute top-4 right-4 p-1.5 rounded-lg text-gray-500 hover:bg-gray-100 dark:hover:bg-gray-700"
            >
              <AiOutlineClose size={20} />
            </button>
            {sidebarContent}
          </aside>
        </div>
      )}

      {/* Mobile top bar */}
      <div className="fixed top-0 left-0 right-0 z-30 md:hidden bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 h-14 flex items-center px-4 gap-3">
        <button onClick={() => setSidebarOpen(true)} className="p-1.5 text-gray-600 dark:text-gray-300">
          <AiOutlineMenu size={22} />
        </button>
        <Link to="/" className="font-bold text-gray-900 dark:text-white">
          Wallpaper <span className="text-indigo-600 dark:text-indigo-400">Exchange</span>
        </Link>
      </div>

      {/* Main content */}
      <div className="flex-1 md:ml-56 lg:ml-60">
        <main className="min-h-screen pt-14 md:pt-0">
          <Outlet />
        </main>

        <footer className="border-t border-gray-200 dark:border-gray-700 py-6">
          <div className="max-w-7xl mx-auto px-4 text-center text-sm text-gray-500 dark:text-gray-400">
            &copy; {new Date().getFullYear()} Wallpaper Exchange. All rights reserved.
          </div>
        </footer>
      </div>
    </div>
  );
}
