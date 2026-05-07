import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import { AiOutlineMenu, AiOutlineClose } from 'react-icons/ai';
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
  const [menuOpen, setMenuOpen] = useState(false);
  const [dark, toggleDark] = useDarkMode();

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  return (
    <div className="min-h-screen flex flex-col bg-gray-50 dark:bg-gray-900 dark:text-gray-100 transition-colors duration-200">
      <header className="sticky top-0 z-50 bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <Link to="/" className="text-2xl font-bold text-indigo-600 tracking-tight">
              WallShare
            </Link>

            <nav className="hidden md:flex items-center gap-6">
              <Link to="/" className="text-gray-600 dark:text-gray-300 hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors duration-200 font-medium">
                Home
              </Link>
              <Link to="/collections" className="text-gray-600 dark:text-gray-300 hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors duration-200 font-medium">
                Collections
              </Link>
              {isAuthenticated && (
                <Link to="/upload" className="text-gray-600 dark:text-gray-300 hover:text-indigo-600 dark:hover:text-indigo-400 transition-colors duration-200 font-medium">
                  Upload
                </Link>
              )}
            </nav>

            <div className="hidden md:flex items-center gap-3">
              <button
                onClick={toggleDark}
                className="p-2 rounded-lg text-gray-500 dark:text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-200"
                aria-label="Toggle dark mode"
              >
                {dark ? <BsSun size={18} /> : <BsMoon size={18} />}
              </button>
              {isAuthenticated && user && (
                <Link
                  to={`/user/${user.id}`}
                  className="group flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-gradient-to-r from-amber-50 to-yellow-50 dark:from-amber-900/30 dark:to-yellow-900/30 border border-amber-200/60 dark:border-amber-600/40 hover:from-amber-100 hover:to-yellow-100 dark:hover:from-amber-900/50 dark:hover:to-yellow-900/50 transition-all duration-200 text-sm font-semibold shadow-sm hover:shadow"
                  title="My coins"
                >
                  <span className="text-base drop-shadow-sm group-hover:scale-110 transition-transform duration-200">💰</span>
                  <span className="bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{user.coins ?? 0}</span>
                </Link>
              )}
              {isAuthenticated && user ? (
                <>
                  <Link
                    to={`/user/${user.id}`}
                    className="flex items-center gap-2 rounded-full px-3 py-1.5 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors duration-200"
                    title="Profile"
                  >
                    {user.avatar_url ? (
                      <img src={user.avatar_url} alt="" className="w-8 h-8 rounded-full object-cover" />
                    ) : (
                      <div className="w-8 h-8 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold text-sm">
                        {(user.nickname || user.username).charAt(0).toUpperCase()}
                      </div>
                    )}
                    <span className="text-sm font-medium text-gray-700 dark:text-gray-200">
                      {user.nickname || user.username}
                    </span>
                  </Link>
                  <button
                    onClick={handleLogout}
                    className="px-3 py-1.5 text-sm font-medium text-red-500 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors duration-200"
                  >
                    Logout
                  </button>
                </>
              ) : (
                <>
                  <Link
                    to="/login"
                    className="px-4 py-2 text-sm font-medium text-indigo-600 hover:bg-indigo-50 rounded-lg transition-colors duration-200"
                  >
                    Login
                  </Link>
                  <Link
                    to="/register"
                    className="px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors duration-200"
                  >
                    Register
                  </Link>
                </>
              )}
            </div>

            <button
              onClick={() => setMenuOpen(!menuOpen)}
              className="md:hidden p-2 text-gray-600 hover:text-indigo-600"
            >
              {menuOpen ? <AiOutlineClose size={24} /> : <AiOutlineMenu size={24} />}
            </button>
          </div>
        </div>

        {menuOpen && (
          <div className="md:hidden border-t border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-800 px-4 py-3 space-y-2">
            <Link to="/" onClick={() => setMenuOpen(false)} className="block py-2 text-gray-700 dark:text-gray-200 hover:text-indigo-600">
              Home
            </Link>
            <Link to="/collections" onClick={() => setMenuOpen(false)} className="block py-2 text-gray-700 dark:text-gray-200 hover:text-indigo-600">
              Collections
            </Link>
            {isAuthenticated && (
              <Link to="/upload" onClick={() => setMenuOpen(false)} className="block py-2 text-gray-700 hover:text-indigo-600">
                Upload
              </Link>
            )}
            {isAuthenticated && user ? (
              <>
                <Link to={`/user/${user.id}`} onClick={() => setMenuOpen(false)} className="flex items-center gap-1.5 py-2 font-semibold">
                  <span className="text-base">💰</span>
                  <span className="bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{user.coins ?? 0} coins</span>
                </Link>
                <Link to={`/user/${user.id}`} onClick={() => setMenuOpen(false)} className="block py-2 text-gray-700 hover:text-indigo-600">
                  Profile
                </Link>
                <button onClick={() => { handleLogout(); setMenuOpen(false); }} className="block py-2 text-red-600">
                  Logout
                </button>
              </>
            ) : (
              <>
                <Link to="/login" onClick={() => setMenuOpen(false)} className="block py-2 text-indigo-600 font-medium">
                  Login
                </Link>
                <Link to="/register" onClick={() => setMenuOpen(false)} className="block py-2 text-indigo-600 font-medium">
                  Register
                </Link>
              </>
            )}
          </div>
        )}
      </header>

      <main className="flex-1">
        <Outlet />
      </main>

      <footer className="bg-white dark:bg-gray-800 border-t border-gray-200 dark:border-gray-700 py-6">
        <div className="max-w-7xl mx-auto px-4 text-center text-sm text-gray-500 dark:text-gray-400">
          &copy; {new Date().getFullYear()} WallShare. All rights reserved.
        </div>
      </footer>
    </div>
  );
}
