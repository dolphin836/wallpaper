import { useEffect } from 'react';
import { BrowserRouter, Routes, Route, useLocation, Navigate } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import toast from 'react-hot-toast';
import { useAuthStore } from './store/auth';
import { getMe } from './api';
import { setAuthExpiredHandler } from './api/client';
import Layout from './components/Layout';
import HomePage from './pages/HomePage';
import DiscoverPage from './pages/DiscoverPage';
import WeeklyArchivePage from './pages/WeeklyArchivePage';
import WeeklyWeekPage from './pages/WeeklyWeekPage';
import LoginPage from './pages/LoginPage';
import RegisterPage from './pages/RegisterPage';
import WallpaperDetailPage from './pages/WallpaperDetailPage';
import UploadPage from './pages/UploadPage';
import ProfilePage from './pages/ProfilePage';
import CollectionsPage from './pages/CollectionsPage';
import CollectionDetailPage from './pages/CollectionDetailPage';
import UploadersPage from './pages/UploadersPage';
import TermsPage from './pages/TermsPage';
import PrivacyPage from './pages/PrivacyPage';
import LegalDmcaPage from './pages/LegalDmcaPage';
import AboutPage from './pages/AboutPage';
import ContributePage from './pages/ContributePage';
import DeviceIndexPage from './pages/DeviceIndexPage';
import DeviceWallpapersPage from './pages/DeviceWallpapersPage';
import DownloadMacPage from './pages/DownloadMacPage';
import WallpaperDetailModal from './components/WallpaperDetailModal';
import AdminLayout from './pages/admin/AdminLayout';
import AdminDashboard from './pages/admin/DashboardPage';
import AdminAnalytics from './pages/admin/AnalyticsPage';
import AdminWallpapers from './pages/admin/WallpapersPage';
import AdminCollections from './pages/admin/CollectionsPage';
import AdminWeeklyPicks from './pages/admin/WeeklyPicksPage';
import AdminUsers from './pages/admin/UsersPage';
import AdminReports from './pages/admin/ReportsPage';
import AdminWorkers from './pages/admin/WorkersPage';

function AppRoutes() {
  const location = useLocation();
  const background = (location.state as { background?: Location })?.background;

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
          <Route path="/download/mac" element={<DownloadMacPage />} />
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
          <Route path="users" element={<AdminUsers />} />
          <Route path="reports" element={<AdminReports />} />
          <Route path="workers" element={<AdminWorkers />} />
        </Route>
      </Routes>

      {background && (
        <Routes>
          <Route path="/wallpaper/:slug" element={<WallpaperDetailModal />} />
        </Routes>
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
