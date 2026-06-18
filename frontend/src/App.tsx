import { lazy, Suspense, useEffect } from 'react';
import { BrowserRouter, Routes, Route, useLocation, Navigate } from 'react-router-dom';
import type { Location as RouterLocation } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import toast from 'react-hot-toast';
import { useAuthStore } from './store/auth';
import { getMe } from './api';
import { setAuthExpiredHandler } from './api/client';
import { routeChanged } from './lib/pageProgress';
import Layout from './components/Layout';

const HomePage = lazy(() => import('./pages/HomePage'));
const DiscoverPage = lazy(() => import('./pages/DiscoverPage'));
const WeeklyArchivePage = lazy(() => import('./pages/WeeklyArchivePage'));
const WeeklyWeekPage = lazy(() => import('./pages/WeeklyWeekPage'));
const LoginPage = lazy(() => import('./pages/LoginPage'));
const RegisterPage = lazy(() => import('./pages/RegisterPage'));
const WallpaperDetailPage = lazy(() => import('./pages/WallpaperDetailPage'));
const UploadPage = lazy(() => import('./pages/UploadPage'));
const ProfilePage = lazy(() => import('./pages/ProfilePage'));
const CollectionsPage = lazy(() => import('./pages/CollectionsPage'));
const CollectionDetailPage = lazy(() => import('./pages/CollectionDetailPage'));
const UploadersPage = lazy(() => import('./pages/UploadersPage'));
const TermsPage = lazy(() => import('./pages/TermsPage'));
const PrivacyPage = lazy(() => import('./pages/PrivacyPage'));
const LegalDmcaPage = lazy(() => import('./pages/LegalDmcaPage'));
const AboutPage = lazy(() => import('./pages/AboutPage'));
const ContributePage = lazy(() => import('./pages/ContributePage'));
const DeviceIndexPage = lazy(() => import('./pages/DeviceIndexPage'));
const DeviceWallpapersPage = lazy(() => import('./pages/DeviceWallpapersPage'));
const DownloadMacPage = lazy(() => import('./pages/DownloadMacPage'));
const WallpaperDetailModal = lazy(() => import('./components/WallpaperDetailModal'));

const AdminLayout = lazy(() => import('./pages/admin/AdminLayout'));
const AdminDashboard = lazy(() => import('./pages/admin/DashboardPage'));
const AdminAnalytics = lazy(() => import('./pages/admin/AnalyticsPage'));
const AdminWallpapers = lazy(() => import('./pages/admin/WallpapersPage'));
const AdminCollections = lazy(() => import('./pages/admin/CollectionsPage'));
const AdminWeeklyPicks = lazy(() => import('./pages/admin/WeeklyPicksPage'));
const AdminIntegrations = lazy(() => import('./pages/admin/IntegrationsPage'));
const AdminUsers = lazy(() => import('./pages/admin/UsersPage'));
const AdminReports = lazy(() => import('./pages/admin/ReportsPage'));
const AdminWorkers = lazy(() => import('./pages/admin/WorkersPage'));

const DevWallpaperDetailPreviewPage = import.meta.env.DEV
  ? lazy(() => import('./pages/dev/WallpaperDetailPreviewPage'))
  : null;

function RouteFallback() {
  return (
    <div
      className="min-h-[55vh] flex items-center justify-center"
      aria-label="Loading page"
    >
      <div className="skeleton-card h-10 w-40 rounded-full" />
    </div>
  );
}

function AppRoutes() {
  const location = useLocation();
  const background = (location.state as { background?: RouterLocation })?.background;

  // Top-edge load bar: start on every navigation; the axios counter in
  // lib/pageProgress keeps it alive until the page's data settles.
  useEffect(() => {
    routeChanged();
  }, [location.pathname, location.search]);

  // ── Session-validity guard ──
  // The client trusts localStorage on first paint, so a token that expired
  // server-side leaves the UI showing "logged in" until the user triggers
  // an authenticated call. Two pieces:
  //   1. Wire a 401 handler that resets the Zustand store + toasts the user
  //      (otherwise the interceptor only wipes localStorage; in-memory
  //      isAuthenticated stays true until a hard reload).
  //   2. On boot, if we claim authenticated, validate with GET /users/me.
  //      A 401 there cascades into the same handler.
  useEffect(() => {
    setAuthExpiredHandler(() => {
      useAuthStore.getState().logout();
      toast.error('Session expired. Please sign in again.');
    });
    if (useAuthStore.getState().isAuthenticated) {
      // 401 already handled by the interceptor; swallow other errors so
      // a transient network blip doesn't sign people out.
      getMe()
        .then((r) => {
          // Refresh cached user payload while we're here — coins / username
          // might have changed in another tab.
          if (r.data?.data) {
            useAuthStore.getState().updateUser(r.data.data);
          }
        })
        .catch(() => { /* handled or network — keep current state */ });
    }
  }, []);

  return (
    <>
      <Suspense fallback={<RouteFallback />}>
        <Routes location={background || location}>
          <Route element={<Layout />}>
            <Route path="/" element={<HomePage />} />
            <Route path="/discover" element={<DiscoverPage />} />
            <Route path="/category/:slug" element={<DiscoverPage />} />
            <Route path="/weekly-picks" element={<WeeklyArchivePage />} />
            <Route path="/weekly-picks/:year/:week" element={<WeeklyWeekPage />} />
            <Route path="/login" element={<LoginPage />} />
            <Route path="/register" element={<RegisterPage />} />
            <Route path="/wallpaper/:slug" element={<WallpaperDetailPage />} />
            <Route path="/upload" element={<UploadPage />} />
            {/* Legacy split-page entry — redirect any saved bookmark
                to the unified /upload form. */}
            <Route path="/upload/video" element={<Navigate to="/upload" replace />} />
            <Route path="/user/:username" element={<ProfilePage />} />
            <Route path="/user/:username/:tab" element={<ProfilePage />} />
            <Route path="/collections" element={<CollectionsPage />} />
            <Route path="/uploaders" element={<UploadersPage />} />
            <Route path="/collections/:slug" element={<CollectionDetailPage />} />
            <Route path="/terms" element={<TermsPage />} />
            <Route path="/privacy" element={<PrivacyPage />} />
            <Route path="/legal/dmca" element={<LegalDmcaPage />} />
            <Route path="/about" element={<AboutPage />} />
            <Route path="/contribute" element={<ContributePage />} />
            <Route path="/wallpapers-for" element={<DeviceIndexPage />} />
            <Route path="/wallpapers-for/:slug" element={<DeviceWallpapersPage />} />
            <Route path="/download" element={<DownloadMacPage />} />
            <Route path="/download/mac" element={<DownloadMacPage />} />
            {DevWallpaperDetailPreviewPage && (
              <Route path="/dev/wp-detail" element={<DevWallpaperDetailPreviewPage />} />
            )}
          </Route>
          <Route path="/admin" element={<AdminLayout />}>
            <Route index element={<AdminDashboard />} />
            <Route path="analytics" element={<AdminAnalytics />} />
            <Route path="wallpapers" element={<AdminWallpapers />} />
            {/* Legacy: review actions are now inline on the main
                /admin/wallpapers list when status=PendingReview. */}
            <Route path="review-queue" element={<Navigate to="/admin/wallpapers?status=5" replace />} />
            <Route path="collections" element={<AdminCollections />} />
            <Route path="weekly-picks" element={<AdminWeeklyPicks />} />
            <Route path="integrations" element={<AdminIntegrations />} />
            <Route path="users" element={<AdminUsers />} />
            <Route path="reports" element={<AdminReports />} />
            <Route path="workers" element={<AdminWorkers />} />
          </Route>
        </Routes>
      </Suspense>

      {background && (
        <Suspense fallback={null}>
          <Routes>
            <Route path="/wallpaper/:slug" element={<WallpaperDetailModal />} />
          </Routes>
        </Suspense>
      )}
    </>
  );
}

function App() {
  return (
    <BrowserRouter>
      <Toaster
        position="top-center"
        toastOptions={{
          duration: 2800,
          style: {
            background: 'var(--color-paper)',
            color: 'var(--color-ink)',
            border: '1px solid var(--color-hair)',
            borderRadius: '8px',
            fontSize: '13px',
            fontFamily: 'var(--font-sans)',
            padding: '10px 14px',
            boxShadow: '0 8px 24px -12px rgba(0,0,0,0.18)',
          },
          success: {
            iconTheme: { primary: '#4a8a5a', secondary: 'var(--color-paper)' },
          },
          error: {
            duration: 4500,
            iconTheme: { primary: '#e0463a', secondary: 'var(--color-paper)' },
          },
        }}
      />
      <AppRoutes />
    </BrowserRouter>
  );
}

export default App;
