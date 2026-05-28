import { useState, useEffect, useRef } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { useAuthStore } from '../store/auth';
import usePageView from '../hooks/usePageView';
import {
  AiOutlineMenu,
  AiOutlineClose,
  AiOutlineDashboard,
  AiOutlineLogout,
  AiOutlineUser,
  AiOutlineUpload,
  AiOutlineDownload,
} from 'react-icons/ai';
import { BsSun, BsMoon } from 'react-icons/bs';
import { getPublicStats } from '../api';
import AnimatedNumber from './AnimatedNumber';

/**
 * Layout — v3 top-nav shell. Replaces the old left sidebar + top-bar
 * pair with a single sticky top nav, a user dropdown that holds account
 * actions, and a footer for stats + legal. Mobile collapses the primary
 * links into a dropdown panel under the bar (no left drawer).
 *
 * Preserved from the previous shell:
 *  - All routes/links (Home / Discover / Collections / Uploaders /
 *    Devices / Mac App + Upload + Admin)
 *  - Theme toggle (light/dark) via useDarkMode + localStorage
 *  - Auth states: signed-in shows avatar + balance pill + user menu;
 *    signed-out shows Log in / Register
 *  - AnimatedNumber on the coin balance, brand live-dot, Re-enable
 *    download confirm link (only when the skip flag is set)
 *  - usePageView for route-change analytics
 *  - Route fade-in animation keyed on background-pathname so the
 *    wallpaper-detail modal-overlay pattern doesn't remount the page
 *    underneath
 */

function useDarkMode() {
  const [dark, setDark] = useState(() => {
    if (typeof window === 'undefined') return false;
    const saved = localStorage.getItem('wpe_theme');
    if (saved === 'dark' || saved === 'light') return saved === 'dark';
    return window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
  });
  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark);
    localStorage.setItem('wpe_theme', dark ? 'dark' : 'light');
  }, [dark]);
  return [dark, setDark] as const;
}

// Primary destinations (top-nav row). Order matches the previous sidebar.
const NAV_ITEMS: { label: string; to: string }[] = [
  { label: 'Home',        to: '/' },
  { label: 'Discover',    to: '/discover' },
  { label: 'Collections', to: '/collections' },
  { label: 'Uploaders',   to: '/uploaders' },
  { label: 'Devices',     to: '/wallpapers-for' },
  { label: 'Mac App',     to: '/download/mac' },
];

function isItemActive(pathname: string, to: string) {
  if (to === '/') return pathname === '/';
  return pathname === to || pathname.startsWith(to + '/');
}

function TopNav({ dark, setDark }: { dark: boolean; setDark: (d: boolean) => void }) {
  const { isAuthenticated, user, logout } = useAuthStore();
  const location = useLocation();
  const navigate = useNavigate();

  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement | null>(null);

  // Close menus on route change so the user doesn't have to.
  useEffect(() => {
    setUserMenuOpen(false);
    setMobileOpen(false);
  }, [location.pathname]);

  // Click-outside + ESC for the user dropdown.
  useEffect(() => {
    if (!userMenuOpen) return;
    const onDoc = (e: MouseEvent) => {
      if (userMenuRef.current && !userMenuRef.current.contains(e.target as Node)) {
        setUserMenuOpen(false);
      }
    };
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') setUserMenuOpen(false); };
    document.addEventListener('mousedown', onDoc);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDoc);
      document.removeEventListener('keydown', onKey);
    };
  }, [userMenuOpen]);

  // Per-session "skip download confirm" flag — surface a reset link inside
  // the user menu when it's set. Re-check on navigation since sessionStorage
  // doesn't fire events for the same window.
  const [skipDlConfirm, setSkipDlConfirm] = useState(
    () => typeof window !== 'undefined' && window.sessionStorage.getItem('wpe_skip_dl_confirm') === '1',
  );
  useEffect(() => {
    setSkipDlConfirm(window.sessionStorage.getItem('wpe_skip_dl_confirm') === '1');
  }, [location.pathname]);

  const handleLogout = () => {
    logout();
    setUserMenuOpen(false);
    navigate('/');
  };

  const initial = (user?.nickname || user?.username || '').charAt(0).toUpperCase();

  return (
    <header className="sticky top-0 z-40 bg-paper/85 border-b border-hair backdrop-blur-md">
      <div className="max-w-[1600px] mx-auto flex items-center gap-3 px-4 sm:px-8 py-3 min-h-[60px]">
        {/* Brand */}
        <Link to="/" className="flex items-center gap-2.5 text-ink no-underline shrink-0">
          <span className="w-7 h-7 rounded-lg bg-ink text-paper display italic-d text-[18px] flex items-center justify-center leading-none">
            W
          </span>
          <span className="hidden sm:inline font-semibold text-[15px] tracking-[-0.01em]">
            Wallpaper Exchange
          </span>
          {/* Live-system signal — small phosphor breathing dot, signals
              "the system is running" on every page. */}
          <span className="live-dot ml-1" title="System online" />
        </Link>

        {/* Primary nav — desktop only */}
        <nav className="hidden md:flex items-center gap-7 ml-6">
          {NAV_ITEMS.map((item) => {
            const active = isItemActive(location.pathname, item.to);
            return (
              <Link
                key={item.to}
                to={item.to}
                className={`text-[13.5px] no-underline transition-colors pb-1 border-b ${
                  active
                    ? 'text-ink border-ink font-medium'
                    : 'text-ink-2 border-transparent hover:text-ink'
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex-1" />

        {/* Right cluster: theme + balance + auth */}
        <div className="flex items-center gap-2 sm:gap-3 shrink-0">
          {/* Theme toggle — same 2-state segmented pill as before */}
          <div className="inline-flex items-center p-[3px] gap-0.5 bg-paper-2 border border-hair rounded-full">
            <button
              onClick={() => setDark(false)}
              title="Light mode"
              aria-label="Light mode"
              className={`w-[24px] h-[24px] rounded-full inline-flex items-center justify-center transition-colors ${!dark
                ? 'bg-paper text-ink shadow-[0_1px_0_var(--color-hair),0_0_0_1px_var(--color-hair)]'
                : 'bg-transparent text-muted'}`}
            >
              <BsSun size={12} />
            </button>
            <button
              onClick={() => setDark(true)}
              title="Dark mode"
              aria-label="Dark mode"
              className={`w-[24px] h-[24px] rounded-full inline-flex items-center justify-center transition-colors ${dark
                ? 'bg-ink text-paper shadow-[0_1px_0_var(--color-hair),0_0_0_1px_var(--color-ink-2)]'
                : 'bg-transparent text-muted'}`}
            >
              <BsMoon size={12} />
            </button>
          </div>

          {isAuthenticated && user ? (
            <>
              {/* Balance pill — links to profile (same as before). The
                  AnimatedNumber smooths +1/-1 jumps so coin changes feel
                  metered rather than jumpy. */}
              <Link
                to={`/user/${user.username}`}
                title="Your balance"
                className="hidden sm:inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-full bg-paper-2 border border-hair text-ink text-[13px] font-semibold no-underline hover:bg-paper-3 transition-colors mono tabular-nums"
              >
                <span className="w-2.5 h-2.5 rounded-full bg-accent shadow-[inset_0_-2px_0_oklch(48%_0.16_42),inset_0_1px_0_oklch(80%_0.16_60)]" />
                <AnimatedNumber value={user.coins ?? 0} />
              </Link>

              {/* User menu */}
              <div className="relative" ref={userMenuRef}>
                <button
                  onClick={() => setUserMenuOpen((o) => !o)}
                  aria-label="Open user menu"
                  aria-expanded={userMenuOpen}
                  className="inline-flex items-center gap-1.5 p-0.5 rounded-full border border-hair bg-paper hover:bg-paper-2 transition-colors"
                >
                  {user.avatar_url ? (
                    <img src={user.avatar_url} alt="" className="w-[32px] h-[32px] rounded-full object-cover" />
                  ) : (
                    <div className="w-[32px] h-[32px] rounded-full bg-paper-2 flex items-center justify-center display text-[16px] text-ink leading-none">
                      {initial}
                    </div>
                  )}
                </button>
                {userMenuOpen && (
                  <UserMenu
                    user={user}
                    isAdmin={!!user.is_admin}
                    skipDlConfirm={skipDlConfirm}
                    onResetSkip={() => {
                      window.sessionStorage.removeItem('wpe_skip_dl_confirm');
                      setSkipDlConfirm(false);
                    }}
                    onLogout={handleLogout}
                    onClose={() => setUserMenuOpen(false)}
                  />
                )}
              </div>
            </>
          ) : (
            <>
              <Link
                to="/login"
                className="hidden sm:inline-flex items-center px-3.5 py-1.5 rounded-full border border-hair text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors no-underline"
              >Log in</Link>
              <Link
                to="/register"
                className="hidden sm:inline-flex items-center px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium hover:bg-ink-2 transition-colors no-underline"
              >Register</Link>
            </>
          )}

          {/* Mobile hamburger */}
          <button
            onClick={() => setMobileOpen((o) => !o)}
            aria-label={mobileOpen ? 'Close menu' : 'Open menu'}
            className="md:hidden w-[34px] h-[34px] inline-flex items-center justify-center rounded-full text-ink hover:bg-paper-2 transition-colors"
          >
            {mobileOpen ? <AiOutlineClose size={20} /> : <AiOutlineMenu size={20} />}
          </button>
        </div>
      </div>

      {/* Mobile dropdown panel */}
      {mobileOpen && (
        <div className="md:hidden border-t border-hair bg-paper">
          <nav className="flex flex-col px-4 py-2">
            {NAV_ITEMS.map((item) => {
              const active = isItemActive(location.pathname, item.to);
              return (
                <Link
                  key={item.to}
                  to={item.to}
                  className={`py-2.5 text-[14px] no-underline ${
                    active ? 'text-ink font-medium' : 'text-ink-2'
                  }`}
                >
                  {item.label}
                </Link>
              );
            })}
            {!isAuthenticated && (
              <div className="flex gap-2 mt-2 mb-3">
                <Link
                  to="/login"
                  className="flex-1 inline-flex items-center justify-center px-3.5 py-2 rounded-full border border-hair text-ink text-[13px] font-medium no-underline"
                >Log in</Link>
                <Link
                  to="/register"
                  className="flex-1 inline-flex items-center justify-center px-3.5 py-2 rounded-full bg-ink text-paper text-[13px] font-medium no-underline"
                >Register</Link>
              </div>
            )}
          </nav>
        </div>
      )}
    </header>
  );
}

/* ───────────────────────── User dropdown ───────────────────────── */

function UserMenu({
  user, isAdmin, skipDlConfirm, onResetSkip, onLogout, onClose,
}: {
  user: { username: string; coins?: number };
  isAdmin: boolean;
  skipDlConfirm: boolean;
  onResetSkip: () => void;
  onLogout: () => void;
  onClose: () => void;
}) {
  const item = 'flex items-center gap-2.5 px-3 py-2.5 rounded-md text-[13px] no-underline hover:bg-paper-2 transition-colors';
  return (
    <div
      role="menu"
      className="absolute right-0 top-[calc(100%+8px)] w-[260px] bg-paper border border-hair rounded-xl shadow-[0_12px_36px_-10px_oklch(0%_0_0_/_0.25)] py-1.5 px-1.5 z-50"
    >
      {/* Upload — accent-colored, the "supply side" CTA. */}
      <Link to="/upload" onClick={onClose} className={`${item} text-accent font-semibold`}>
        <AiOutlineUpload size={16} />
        Upload a wallpaper
      </Link>

      <hr className="my-1.5 border-t border-hair-soft" />

      <Link to={`/user/${user.username}`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineUser size={16} />
        My profile
      </Link>
      <Link to={`/user/${user.username}?tab=uploads`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineUpload size={16} />
        My uploads
      </Link>
      <Link to={`/user/${user.username}?tab=downloads`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineDownload size={16} />
        My downloads
      </Link>

      <hr className="my-1.5 border-t border-hair-soft" />

      {/* Balance — inline (no separate balance card needed since the
          pill in the top nav already shows the number; this is detail). */}
      <div className="px-3 py-2 text-[12px] text-ink-2">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-accent" />
          <span className="font-semibold text-ink mono tabular-nums">
            <AnimatedNumber value={user.coins ?? 0} />
          </span>
          <span className="mono text-[10px] tracking-[0.16em] uppercase text-muted">coins</span>
        </div>
        <div className="mt-1 text-[11px] text-muted">
          Upload to earn <span className="text-accent font-semibold">+1</span>.
        </div>
        {skipDlConfirm && (
          <button
            onClick={onResetSkip}
            className="mt-2 text-[10px] mono tracking-[0.14em] uppercase text-muted hover:text-accent transition-colors block cursor-pointer text-left"
          >
            Re-enable download confirm →
          </button>
        )}
      </div>

      {(isAdmin) && (
        <>
          <hr className="my-1.5 border-t border-hair-soft" />
          <Link to="/admin" onClick={onClose} className={`${item} text-ink`}>
            <AiOutlineDashboard size={16} />
            Admin console
          </Link>
        </>
      )}

      <hr className="my-1.5 border-t border-hair-soft" />

      <button onClick={onLogout} className={`${item} text-ink w-full text-left`}>
        <AiOutlineLogout size={16} />
        Sign out
      </button>
    </div>
  );
}

/* ───────────────────────── Footer ───────────────────────── */

function Footer() {
  const [stats, setStats] = useState<{ wallpapers: number; collections: number } | null>(null);
  useEffect(() => {
    const cached = sessionStorage.getItem('wpe_stats');
    if (cached) { try { setStats(JSON.parse(cached)); } catch { /* ignore */ } }
    getPublicStats().then((r) => {
      setStats(r.data.data);
      sessionStorage.setItem('wpe_stats', JSON.stringify(r.data.data));
    }).catch(() => { /* keep em-dashes */ });
  }, []);

  return (
    <footer className="border-t border-hair bg-paper/60 backdrop-blur-sm mt-auto relative z-10">
      <div className="max-w-[1600px] mx-auto px-4 sm:px-8 py-8 flex flex-col sm:flex-row items-start sm:items-center gap-4 sm:gap-6 justify-between">
        <div className="display italic-d text-[14px] text-ink-2">
          Wallpaper Exchange · trade wallpapers, share more.
        </div>
        <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted inline-flex gap-3 items-center flex-wrap">
          <span><strong className="text-ink-2 font-semibold tabular-nums">
            {stats ? stats.wallpapers.toLocaleString() : '—'}
          </strong> Wallpapers</span>
          <span className="opacity-40">·</span>
          <span><strong className="text-ink-2 font-semibold tabular-nums">
            {stats ? stats.collections.toLocaleString() : '—'}
          </strong> Collections</span>
        </div>
        <nav className="flex flex-wrap gap-x-4 gap-y-1 mono text-[10px] tracking-[0.14em] uppercase text-muted">
          <Link to="/about" className="hover:text-ink transition-colors no-underline">About</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/contribute" className="hover:text-ink transition-colors no-underline">Contribute</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/terms" className="hover:text-ink transition-colors no-underline">Terms</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/privacy" className="hover:text-ink transition-colors no-underline">Privacy</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/legal/dmca" className="hover:text-ink transition-colors no-underline">DMCA</Link>
        </nav>
        <div className="text-[11px] text-muted mono tracking-wide">© {new Date().getFullYear()}</div>
      </div>
    </footer>
  );
}

/* ───────────────────────── Layout root ───────────────────────── */

export default function Layout() {
  const location = useLocation();
  const [dark, setDark] = useDarkMode();
  usePageView();

  // Route-transition key — see AppRoutes for the background-location
  // pattern that overlays the wallpaper-detail modal on a previous page.
  const background = (location.state as { background?: { pathname: string } } | null)?.background;
  const routeKey = background?.pathname ?? location.pathname;

  return (
    <div className="min-h-screen flex flex-col bg-paper text-ink font-sans transition-colors duration-200">
      <TopNav dark={dark} setDark={setDark} />

      <main className="flex-1 bg-paper relative overflow-x-hidden">
        <div key={routeKey} className="animate-route-in">
          <Outlet />
        </div>
      </main>

      <Footer />
    </div>
  );
}
