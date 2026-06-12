import { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import { useAuthStore } from '../store/auth';
import LanguageSwitcher from './LanguageSwitcher';
import usePageView from '../hooks/usePageView';
import {
  AiOutlineMenu,
  AiOutlineClose,
  AiOutlineDashboard,
  AiOutlineLogout,
  AiOutlineUser,
  AiOutlineUpload,
  AiOutlineDownload,
  AiOutlineThunderbolt,
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
// Labels are i18n keys under common:nav.
const NAV_ITEMS: { labelKey: string; to: string }[] = [
  { labelKey: 'nav.home',        to: '/' },
  { labelKey: 'nav.discover',    to: '/discover' },
  { labelKey: 'nav.weekly',      to: '/weekly-picks' },
  { labelKey: 'nav.collections', to: '/collections' },
  { labelKey: 'nav.uploaders',   to: '/uploaders' },
  { labelKey: 'nav.devices',     to: '/wallpapers-for' },
  { labelKey: 'nav.macApp',      to: '/download/mac' },
];

function isItemActive(pathname: string, to: string) {
  if (to === '/') return pathname === '/';
  // Category landing pages live under /category/:slug but visually belong
  // to Discover — keep the nav item highlighted there too.
  if (to === '/discover') {
    return (
      pathname === '/discover'
      || pathname.startsWith('/discover/')
      || pathname.startsWith('/category/')
    );
  }
  return pathname === to || pathname.startsWith(to + '/');
}

/* Sliding-underline desktop nav. One absolutely-positioned span tracks
   the active item via translateX + width transitions, so navigating
   Home → Discover shows the bar gliding to the new label (and
   resizing to fit) rather than the old border-b color swap. Re-
   measures on resize so the position stays accurate if fonts load
   late or the viewport changes. */
function NavBar({ location }: { location: { pathname: string } }) {
  const { t, i18n } = useTranslation();
  const navRef = useRef<HTMLElement>(null);
  const itemRefs = useRef<Map<string, HTMLAnchorElement>>(new Map());
  const [indicator, setIndicator] = useState<{ x: number; w: number; visible: boolean }>({
    x: 0, w: 0, visible: false,
  });

  useLayoutEffect(() => {
    const measure = () => {
      const navEl = navRef.current;
      const activeItem = NAV_ITEMS.find((item) => isItemActive(location.pathname, item.to));
      if (!navEl || !activeItem) {
        setIndicator((prev) => (prev.visible ? { ...prev, visible: false } : prev));
        return;
      }
      const el = itemRefs.current.get(activeItem.to);
      if (!el) return;
      const elRect = el.getBoundingClientRect();
      const navRect = navEl.getBoundingClientRect();
      setIndicator({
        x: elRect.left - navRect.left,
        w: elRect.width,
        visible: true,
      });
    };
    measure();
    window.addEventListener('resize', measure);
    return () => window.removeEventListener('resize', measure);
    // i18n.language: label widths change with the language, so re-measure.
  }, [location.pathname, i18n.language]);

  return (
    <nav ref={navRef} className="hidden md:flex items-center gap-7 ml-6 relative">
      {NAV_ITEMS.map((item) => {
        const active = isItemActive(location.pathname, item.to);
        return (
          <Link
            key={item.to}
            ref={(el) => {
              if (el) itemRefs.current.set(item.to, el);
              else itemRefs.current.delete(item.to);
            }}
            to={item.to}
            className={`text-[13.5px] no-underline transition-colors pb-1 ${
              active ? 'text-ink font-medium' : 'text-ink-2 hover:text-ink'
            }`}
          >
            {t(item.labelKey)}
          </Link>
        );
      })}
      <span
        aria-hidden
        className="nav-underline"
        style={{
          transform: `translateX(${indicator.x}px)`,
          width: `${indicator.w}px`,
          opacity: indicator.visible ? 1 : 0,
        }}
      />
    </nav>
  );
}

function TopNav({ dark, setDark }: { dark: boolean; setDark: (d: boolean) => void }) {
  const { t } = useTranslation();
  const { isAuthenticated, user, logout } = useAuthStore();
  const location = useLocation();
  const navigate = useNavigate();

  const [userMenuOpen, setUserMenuOpen] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const userMenuRef = useRef<HTMLDivElement | null>(null);

  // Hover-to-open dropdown with a small grace period on leave so the
  // user can slide the cursor from the avatar down to the menu items
  // without the menu snapping shut mid-traverse.
  const hoverCloseTimerRef = useRef<number | null>(null);
  const cancelHoverClose = () => {
    if (hoverCloseTimerRef.current !== null) {
      clearTimeout(hoverCloseTimerRef.current);
      hoverCloseTimerRef.current = null;
    }
  };
  const onAvatarEnter = () => {
    cancelHoverClose();
    setUserMenuOpen(true);
  };
  const onAvatarLeave = () => {
    cancelHoverClose();
    hoverCloseTimerRef.current = window.setTimeout(() => {
      setUserMenuOpen(false);
      hoverCloseTimerRef.current = null;
    }, 180);
  };
  useEffect(() => () => cancelHoverClose(), []);

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
        {/* Brand — real PNG mark (two image frames + exchange arrows) +
            stacked editorial wordmark (serif "Wallpaper" / mono uppercase
            "EXCHANGE · live-dot"). The synthesized black W square was a
            placeholder; this restores the original brand. */}
        <Link to="/" className="flex items-center gap-3 text-ink no-underline shrink-0 group">
          <img
            src="/logo-192.png"
            alt=""
            decoding="async"
            className="w-9 h-9 shrink-0 transition-transform duration-300 group-hover:rotate-[8deg]"
          />
          <div className="hidden sm:block leading-none">
            <div className="display text-[20px] leading-none tracking-[-0.01em]">Wallpaper</div>
            <div className="mono text-[9px] tracking-[0.20em] uppercase text-muted mt-1 inline-flex items-center gap-1.5">
              Exchange
              <span className="live-dot" title={t('header.systemOnline')} />
            </div>
          </div>
          {/* Mobile-only: just the live dot floats next to the icon since
              the wordmark is hidden at < sm. */}
          <span className="live-dot sm:hidden" title={t('header.systemOnline')} />
        </Link>

        {/* Primary nav — desktop only. Sliding underline indicator:
            one absolutely-positioned span rides across the nav as the
            active route changes, translateX + width transitioning in
            tandem so the bar both moves and resizes to the target
            label. Beats per-link border-b's, which would just swap
            colors instantly between siblings. */}
        <NavBar location={location} />

        <div className="flex-1" />

        {/* Right cluster: theme + balance + auth */}
        <div className="flex items-center gap-2 sm:gap-3 shrink-0">
          {/* Theme toggle — single button, icon shows the *destination*
              mode (moon while light, sun while dark). Smaller footprint
              than the previous 2-state pill and matches the original
              demo's single-affordance treatment. */}
          <button
            onClick={() => setDark(!dark)}
            title={dark ? t('header.switchToLight') : t('header.switchToDark')}
            aria-label={dark ? t('header.switchToLight') : t('header.switchToDark')}
            className="w-[34px] h-[34px] rounded-full inline-flex items-center justify-center bg-paper-2 border border-hair text-ink-2 hover:text-ink hover:border-ink-2 transition-colors"
          >
            {dark ? <BsSun size={13} /> : <BsMoon size={13} />}
          </button>

          <LanguageSwitcher />

          {isAuthenticated && user ? (
            <>
              {/* Balance pill — warm-tinted gradient with a real coin
                  glyph (gradient disc, not the old generic accent
                  dot). Hover flips the coin on its Y-axis and lights
                  a warm halo around the pill; the pill itself lifts
                  -2px. mx-2 separates it from the theme button and
                  avatar so the balance reads as the main affordance
                  of the right cluster, not blended with chrome. */}
              <Link
                to={`/user/${user.username}/ledger`}
                title={t('header.coinLedger')}
                className="balance-pill hidden sm:inline-flex mx-2"
              >
                <span className="balance-pill__coin" aria-hidden />
                <span className="balance-pill__num">
                  <AnimatedNumber value={user.coins ?? 0} />
                </span>
                <span className="balance-pill__label">{t('header.coins')}</span>
              </Link>

              {/* User menu — hover-to-open with an accent-ring avatar.
                  Always-rendered menu drives the open/close transition
                  in CSS (translateY + scale + opacity); the conditional
                  mount of the past wouldn't transition on entry. */}
              <div
                className="avatar-shell relative"
                ref={userMenuRef}
                onMouseEnter={onAvatarEnter}
                onMouseLeave={onAvatarLeave}
              >
                <button
                  onClick={() => setUserMenuOpen((o) => !o)}
                  aria-label={t('header.openUserMenu')}
                  aria-expanded={userMenuOpen}
                  className="avatar-btn"
                >
                  {user.avatar_url ? (
                    <img src={user.avatar_url} alt="" decoding="async" className="avatar-img" />
                  ) : (
                    <div className="avatar-img avatar-img--fallback">{initial}</div>
                  )}
                </button>
                <UserMenu
                  user={user}
                  isOpen={userMenuOpen}
                  isAdmin={!!user.is_admin}
                  skipDlConfirm={skipDlConfirm}
                  onResetSkip={() => {
                    window.sessionStorage.removeItem('wpe_skip_dl_confirm');
                    setSkipDlConfirm(false);
                  }}
                  onLogout={handleLogout}
                  onClose={() => setUserMenuOpen(false)}
                />
              </div>
            </>
          ) : (
            <>
              <Link
                to="/login"
                className="hidden sm:inline-flex items-center px-3.5 py-1.5 rounded-full border border-hair text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors no-underline"
              >{t('header.logIn')}</Link>
              <Link
                to="/register"
                className="hidden sm:inline-flex items-center px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium hover:bg-ink-2 transition-colors no-underline"
              >{t('header.register')}</Link>
            </>
          )}

          {/* Mobile hamburger */}
          <button
            onClick={() => setMobileOpen((o) => !o)}
            aria-label={mobileOpen ? t('header.closeMenu') : t('header.openMenu')}
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
                  {t(item.labelKey)}
                </Link>
              );
            })}
            {!isAuthenticated && (
              <div className="flex gap-2 mt-2 mb-3">
                <Link
                  to="/login"
                  className="flex-1 inline-flex items-center justify-center px-3.5 py-2 rounded-full border border-hair text-ink text-[13px] font-medium no-underline"
                >{t('header.logIn')}</Link>
                <Link
                  to="/register"
                  className="flex-1 inline-flex items-center justify-center px-3.5 py-2 rounded-full bg-ink text-paper text-[13px] font-medium no-underline"
                >{t('header.register')}</Link>
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
  user, isOpen, isAdmin, skipDlConfirm, onResetSkip, onLogout, onClose,
}: {
  user: { username: string; coins?: number };
  isOpen: boolean;
  isAdmin: boolean;
  skipDlConfirm: boolean;
  onResetSkip: () => void;
  onLogout: () => void;
  onClose: () => void;
}) {
  const { t } = useTranslation();
  const item = 'flex items-center gap-2.5 px-3 py-2.5 rounded-md text-[13px] no-underline hover:bg-paper-2 transition-colors';
  return (
    <div
      role="menu"
      aria-hidden={!isOpen}
      className={`user-menu${isOpen ? ' is-open' : ''}`}
    >
      {/* Upload — accent-colored, the "supply side" CTA. */}
      <Link to="/upload" onClick={onClose} className={`${item} text-accent font-semibold`}>
        <AiOutlineUpload size={16} />
        {t('userMenu.upload')}
      </Link>

      <hr className="my-1.5 border-t border-hair-soft" />

      {/* My profile = uploads tab by default — no separate "My uploads"
          link since it pointed to the same view. Downloads + Coin
          ledger get explicit entries because they're owner-only and
          aren't surfaced anywhere else. */}
      <Link to={`/user/${user.username}`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineUser size={16} />
        {t('userMenu.myProfile')}
      </Link>
      <Link to={`/user/${user.username}/downloads`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineDownload size={16} />
        {t('userMenu.myDownloads')}
      </Link>
      <Link to={`/user/${user.username}/ledger`} onClick={onClose} className={`${item} text-ink`}>
        <AiOutlineThunderbolt size={16} />
        {t('userMenu.coinLedger')}
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
          <span className="mono text-[10px] tracking-[0.16em] uppercase text-muted">{t('header.coins')}</span>
        </div>
        <div className="mt-1 text-[11px] text-muted">
          <Trans i18nKey="userMenu.uploadToEarn" components={[<span key="0" className="text-accent font-semibold" />]} />
        </div>
        {skipDlConfirm && (
          <button
            onClick={onResetSkip}
            className="mt-2 text-[10px] mono tracking-[0.14em] uppercase text-muted hover:text-accent transition-colors block cursor-pointer text-left"
          >
            {t('userMenu.reEnableDlConfirm')}
          </button>
        )}
      </div>

      {(isAdmin) && (
        <>
          <hr className="my-1.5 border-t border-hair-soft" />
          <Link to="/admin" onClick={onClose} className={`${item} text-ink`}>
            <AiOutlineDashboard size={16} />
            {t('userMenu.adminConsole')}
          </Link>
        </>
      )}

      <hr className="my-1.5 border-t border-hair-soft" />

      <button onClick={onLogout} className={`${item} text-ink w-full text-left`}>
        <AiOutlineLogout size={16} />
        {t('userMenu.signOut')}
      </button>
    </div>
  );
}

/* ───────────────────────── Footer ───────────────────────── */

function Footer() {
  const { t } = useTranslation();
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
          {t('footer.tagline')}
        </div>
        <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted inline-flex gap-3 items-center flex-wrap">
          <span><strong className="text-ink-2 font-semibold tabular-nums">
            {stats ? stats.wallpapers.toLocaleString() : '—'}
          </strong> {t('footer.wallpapers')}</span>
          <span className="opacity-40">·</span>
          <span><strong className="text-ink-2 font-semibold tabular-nums">
            {stats ? stats.collections.toLocaleString() : '—'}
          </strong> {t('footer.collections')}</span>
        </div>
        <nav className="flex flex-wrap gap-x-4 gap-y-1 mono text-[10px] tracking-[0.14em] uppercase text-muted">
          <Link to="/about" className="hover:text-ink transition-colors no-underline">{t('footer.about')}</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/contribute" className="hover:text-ink transition-colors no-underline">{t('footer.contribute')}</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/terms" className="hover:text-ink transition-colors no-underline">{t('footer.terms')}</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/privacy" className="hover:text-ink transition-colors no-underline">{t('footer.privacy')}</Link>
          <span className="text-hair" aria-hidden>·</span>
          <Link to="/legal/dmca" className="hover:text-ink transition-colors no-underline">{t('footer.dmca')}</Link>
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
  // Collapse all routes that resolve to the same page component into one
  // key so React doesn't unmount + remount the page on intra-page nav.
  // Without this, clicking a Discover category (e.g. /discover → /category/foo)
  // remounted DiscoverPage, blowing away its `categories` state — the chip
  // strip would flicker (all chips disappear, refetch, reappear) every
  // time the user filtered. The animate-route-in still plays for real
  // route transitions (Home → Discover, Detail → Profile, etc.).
  const stableKey = (() => {
    const p = location.pathname;
    if (p === '/discover' || p.startsWith('/discover/') || p.startsWith('/category/')) return 'discover';
    // Profile tab routes: /user/:username and /user/:username/:tab map to
    // the same component. Collapsing the key here means switching tabs
    // doesn't remount ProfilePage (would blow away loaded lists).
    const userMatch = p.match(/^\/user\/([^/]+)(?:\/.*)?$/);
    if (userMatch) return `user:${userMatch[1]}`;
    return p;
  })();
  const routeKey = background?.pathname ?? stableKey;

  return (
    <div className="min-h-screen flex flex-col bg-paper text-ink font-sans transition-colors duration-200">
      <TopNav dark={dark} setDark={setDark} />

      {/* overflow-x:clip (not hidden) clips horizontal overflow without
          becoming a scroll container — `hidden` was reserving a vertical
          scrollbar gutter in the middle of the page even when nothing
          actually overflowed. */}
      <main className="flex-1 bg-paper relative overflow-x-clip">
        <div key={routeKey} className="animate-route-in">
          <Outlet />
        </div>
      </main>

      <Footer />
    </div>
  );
}
