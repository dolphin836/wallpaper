import { useState, useEffect } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import usePageView from '../hooks/usePageView';
import {
  AiOutlineMenu,
  AiOutlineClose,
  AiOutlineLogout,
  AiOutlinePlus,
  AiOutlineDashboard,
} from 'react-icons/ai';
import { BsSun, BsMoon } from 'react-icons/bs';
import { getPublicStats } from '../api';

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

  return [dark, setDark] as const;
}

interface NavItem { label: string; sub: string; to: string; }

function ArchiveSidebar({ onCloseDrawer }: { onCloseDrawer?: () => void }) {
  const { isAuthenticated, user } = useAuthStore();
  const location = useLocation();

  const items: NavItem[] = [
    { label: 'Home',        sub: 'This week\'s picks',     to: '/' },
    { label: 'Discover',    sub: 'Browse the gallery',     to: '/discover' },
    { label: 'Collections', sub: 'Themed wallpaper sets', to: '/collections' },
    { label: 'Uploaders',   sub: 'Top contributors',      to: '/uploaders' },
    { label: 'Devices',     sub: 'Wallpapers by screen',  to: '/wallpapers-for' },
    { label: 'macOS App',   sub: 'Get the Mac app',       to: '/download/mac' },
    // Upload pinned to the bottom so the "browse" items stay together at the
    // top of the nav and the contributor action sits closer to the balance
    // card just below it.
    ...(isAuthenticated ? [{ label: 'Upload', sub: 'Share a wallpaper', to: '/upload' }] : []),
  ];

  // Match the exact route, OR a nested child route (e.g. /collections/foo
  // counts as active for /collections). Important to add the trailing slash
  // — without it /uploaders falsely matches /upload because the latter is a
  // prefix string of the former.
  const isActive = (to: string) =>
    to === '/'
      ? location.pathname === '/'
      : location.pathname === to || location.pathname.startsWith(to + '/');

  return (
    <aside className="w-[232px] h-full flex flex-col bg-paper border-r border-hair font-sans">
      {/* Brand */}
      <Link
        to="/"
        onClick={onCloseDrawer}
        className="flex items-center gap-3 px-6 pt-8 pb-6 text-ink no-underline"
      >
        <img
          src="/logo-192.png"
          alt="Wallpaper Exchange"
          className="w-9 h-9 rounded-lg border border-hair flex-shrink-0 object-cover"
        />
        <div>
          <div className="display text-[20px] leading-none">Wallpaper</div>
          <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted mt-1.5">Exchange</div>
        </div>
      </Link>

      <hr className="mx-6 border-t border-hair" />

      <div className="kicker text-muted px-6 pt-4 pb-3">Sections</div>

      <nav className="flex flex-col px-6">
        {items.map((item, i) => {
          const active = isActive(item.to);
          const isUpload = item.label === 'Upload';
          return (
            <Link
              key={item.label}
              to={item.to}
              onClick={onCloseDrawer}
              className={`group grid grid-cols-[20px_1fr] items-baseline gap-2 pl-3 pr-2 -mx-2 py-3 ${i === 0 ? 'border-t border-hair' : ''} border-b border-hair border-l-2 no-underline transition-colors duration-200 ${
                active
                  ? 'border-l-ink text-ink'
                  : 'border-l-transparent text-ink-2 hover:text-ink hover:border-l-hair'
              }`}
            >
              <span className={`mono text-[10px] transition-colors duration-200 ${active ? 'text-muted-2' : 'text-muted group-hover:text-ink'}`}>
                {String(i + 1).padStart(2, '0')}
              </span>
              <div>
                <div className={`display text-[18px] leading-tight flex items-center gap-1.5 ${isUpload && !active ? 'text-accent' : ''}`}>
                  <span>{item.label}</span>
                  {isUpload && !active && (
                    <AiOutlinePlus size={14} className="text-accent transition-transform duration-200 group-hover:rotate-90" />
                  )}
                </div>
                {/* Sub-description: collapsed to height 0 by default, expands on
                    hover/active. grid-rows trick gives a true height transition
                    (CSS can't transition `height: auto`) without measuring JS. */}
                <div
                  className={`grid transition-[grid-template-rows] duration-300 ${
                    active ? 'grid-rows-[1fr]' : 'grid-rows-[0fr] group-hover:grid-rows-[1fr]'
                  }`}
                  style={{ transitionTimingFunction: 'var(--ease-out-expo)' }}
                >
                  <div className="overflow-hidden">
                    <div className="text-[11px] text-muted pt-1">{item.sub}</div>
                  </div>
                </div>
              </div>
            </Link>
          );
        })}
      </nav>

      {/* Balance card — only when signed in. Routes to /user/:username (the
          owner's own profile, which is where the coin balance lives) rather
          than a non-existent /profile alias. */}
      {isAuthenticated && user && (
        <Link to={`/user/${user.username}`} onClick={onCloseDrawer} className="mx-6 mt-5 px-3.5 py-3 border border-hair bg-paper-2 no-underline block">
          <div className="kicker text-muted">Your balance</div>
          <div className="mt-1.5 flex items-baseline gap-1.5">
            <span className="mono font-semibold text-[22px] text-accent inline-flex items-center gap-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-accent shadow-[inset_0_-2px_0_oklch(48%_0.16_42),inset_0_1px_0_oklch(80%_0.16_60)]" />
              {user?.coins ?? 0}
            </span>
            <span className="mono text-[10px] text-muted">/ COINS</span>
          </div>
          <div className="mt-2 text-[11px] text-ink-2 leading-snug">
            Upload to earn <span className="text-accent">+1</span>.
          </div>
        </Link>
      )}

      {/* Legal footer — the link row wraps from the left so a 2/3 split
          across two lines stays left-aligned (centered wrapping looked
          uneven). The copyright line below stays centered for the
          stamp-style sign-off. */}
      <div className="mt-auto px-6 pt-6 pb-6 flex flex-col items-center">
        <hr className="border-t border-dashed border-hair w-full" />
        <ul className="flex flex-wrap justify-start gap-x-3 gap-y-1.5 py-3 list-none m-0 p-0 mono text-[10px] tracking-[0.12em] uppercase text-muted self-stretch">
          <li><Link to="/about" className="text-inherit no-underline hover:text-ink transition-colors duration-200">About</Link></li>
          <li className="text-hair" aria-hidden>·</li>
          <li><Link to="/contribute" className="text-inherit no-underline hover:text-ink transition-colors duration-200">Contribute</Link></li>
          <li className="text-hair" aria-hidden>·</li>
          <li><Link to="/terms" className="text-inherit no-underline hover:text-ink transition-colors duration-200">Terms</Link></li>
          <li className="text-hair" aria-hidden>·</li>
          <li><Link to="/privacy" className="text-inherit no-underline hover:text-ink transition-colors duration-200">Privacy</Link></li>
          <li className="text-hair" aria-hidden>·</li>
          <li><Link to="/legal/dmca" className="text-inherit no-underline hover:text-ink transition-colors duration-200">DMCA</Link></li>
        </ul>
        <hr className="border-t border-hair w-full" />
        <div className="mt-3 flex items-baseline justify-center gap-1.5 text-[11px] text-ink-2 text-center">
          <span>&copy; {new Date().getFullYear()}</span>
          <span className="display italic-d text-[13px]">Wallpaper Exchange</span>
        </div>
      </div>
    </aside>
  );
}

function ArchiveTopbar({
  onOpenDrawer,
  dark,
  setDark,
}: {
  onOpenDrawer: () => void;
  dark: boolean;
  setDark: (d: boolean) => void;
}) {
  const { isAuthenticated, user, logout } = useAuthStore();
  const navigate = useNavigate();

  const [stats, setStats] = useState<{ wallpapers: number; collections: number } | null>(null);
  useEffect(() => {
    // sessionStorage cache: the counts barely move between page loads, and
    // backend caches for 60s anyway, so reusing within a tab is fine.
    const cached = sessionStorage.getItem('wpe_stats');
    if (cached) {
      try { setStats(JSON.parse(cached)); } catch { /* ignore */ }
    }
    getPublicStats().then((r) => {
      setStats(r.data.data);
      sessionStorage.setItem('wpe_stats', JSON.stringify(r.data.data));
    }).catch(() => { /* masthead falls back to em-dashes */ });
  }, []);

  const handleLogout = () => {
    logout();
    navigate('/');
  };

  const initial = (user?.nickname || user?.username || '').charAt(0).toUpperCase();

  return (
    <div className="sticky top-0 z-30 bg-paper border-b border-hair">
      {/* Toolbar row — counts inline on the left, theme + auth on the right.
          The standalone masthead row got merged into this row so the shell
          isn't carrying two header strips for what's essentially one strip
          of metadata. */}
      <div className="px-4 sm:px-8 py-3 flex items-center gap-3 min-h-[64px]">
        <button onClick={onOpenDrawer} className="md:hidden p-2 text-ink rounded-full hover:bg-paper-2" aria-label="Open menu">
          <AiOutlineMenu size={22} />
        </button>

        <div className="flex-1 min-w-0 hidden sm:inline-flex items-center gap-3.5 mono text-[10px] tracking-[0.18em] uppercase text-muted">
          <span>
            <strong className="text-ink-2 font-semibold">
              {stats ? stats.wallpapers.toLocaleString() : '—'}
            </strong> Wallpapers
          </span>
          <span className="opacity-40">·</span>
          <span>
            <strong className="text-ink-2 font-semibold">
              {stats ? stats.collections.toLocaleString() : '—'}
            </strong> Collections
          </span>
        </div>
        {/* Mobile filler — keep the right-side cluster flush to the edge
            on phones where the inline stats are hidden. */}
        <div className="flex-1 sm:hidden" />

        <div className="flex items-center gap-2">
          {/* 2-state segmented theme toggle. Sized to match the row's other
              non-CTA controls (Login/Register ~28px, Admin ghost link ~30px)
              rather than the larger 38px Logout/avatar circles next to it. */}
          <div className="inline-flex items-center p-[3px] gap-0.5 bg-paper-2 border border-hair rounded-full">
            <button
              onClick={() => setDark(false)}
              title="Light mode"
              className={`w-[24px] h-[24px] rounded-full inline-flex items-center justify-center transition-colors ${!dark
                ? 'bg-paper text-ink shadow-[0_1px_0_var(--color-hair),0_0_0_1px_var(--color-hair)]'
                : 'bg-transparent text-muted'}`}
            >
              <BsSun size={12} />
            </button>
            <button
              onClick={() => setDark(true)}
              title="Dark mode"
              className={`w-[24px] h-[24px] rounded-full inline-flex items-center justify-center transition-colors ${dark
                ? 'bg-ink text-paper shadow-[0_1px_0_var(--color-hair),0_0_0_1px_var(--color-ink-2)]'
                : 'bg-transparent text-muted'}`}
            >
              <BsMoon size={12} />
            </button>
          </div>

          {isAuthenticated && user ? (
            <>
              {user.is_admin && (
                <Link
                  to="/admin"
                  title="Admin console"
                  // Match the Logout icon button right next to it: 38px
                  // square, same paper/hair pill chrome. Used to read
                  // "Admin" in text — we're tight on space and the icon
                  // alone is unambiguous given title= surfaces the label
                  // on hover.
                  className="hidden sm:inline-flex w-[38px] h-[38px] rounded-full bg-paper border border-hair text-ink hover:bg-paper-2 transition-colors items-center justify-center"
                >
                  <AiOutlineDashboard size={15} />
                </Link>
              )}
              <button
                onClick={handleLogout}
                title="Log out"
                className="w-[38px] h-[38px] rounded-full bg-paper border border-hair text-ink hover:bg-paper-2 transition-colors inline-flex items-center justify-center"
              >
                <AiOutlineLogout size={15} />
              </button>
              <Link
                to={`/user/${user.username}`}
                title={user.nickname || user.username}
                className="ml-1 inline-flex no-underline"
              >
                {user.avatar_url ? (
                  <img
                    src={user.avatar_url}
                    alt=""
                    className="w-[38px] h-[38px] rounded-full object-cover border border-hair"
                  />
                ) : (
                  <div className="w-[38px] h-[38px] rounded-full bg-paper-2 border border-hair flex items-center justify-center display text-[18px] text-ink">
                    {initial}
                  </div>
                )}
              </Link>
            </>
          ) : (
            <>
              <Link
                to="/login"
                className="inline-flex items-center px-3.5 py-1.5 rounded-full border border-hair text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors no-underline"
              >Log in</Link>
              <Link
                to="/register"
                className="inline-flex items-center px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium hover:bg-ink-2 transition-colors no-underline"
              >Register</Link>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

export default function Layout() {
  const location = useLocation();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [dark, setDark] = useDarkMode();
  usePageView();

  useEffect(() => { setSidebarOpen(false); }, [location.pathname]);

  return (
    <div className="min-h-screen flex bg-paper text-ink font-sans transition-colors duration-200">
      {/* Desktop sidebar */}
      <aside className="hidden md:flex md:flex-col w-[232px] fixed inset-y-0 left-0 z-40">
        <ArchiveSidebar />
      </aside>

      {/* Mobile drawer */}
      {sidebarOpen && (
        <div className="fixed inset-0 z-50 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setSidebarOpen(false)} />
          <div className="relative w-[232px] h-full bg-paper shadow-xl">
            <button
              onClick={() => setSidebarOpen(false)}
              className="absolute top-4 right-4 p-1.5 rounded-lg text-muted hover:bg-paper-2"
              aria-label="Close menu"
            >
              <AiOutlineClose size={20} />
            </button>
            <ArchiveSidebar onCloseDrawer={() => setSidebarOpen(false)} />
          </div>
        </div>
      )}

      {/* Main column */}
      <div className="flex-1 md:ml-[232px] flex flex-col min-h-screen min-w-0">
        <ArchiveTopbar
          onOpenDrawer={() => setSidebarOpen(true)}
          dark={dark}
          setDark={setDark}
        />

        <main className="flex-1 bg-paper relative overflow-x-hidden">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
