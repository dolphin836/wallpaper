import { BrowserRouter, Routes, Route, useLocation, Navigate } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
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
import AdminUsers from './pages/admin/UsersPage';
import AdminReports from './pages/admin/ReportsPage';
import AdminWorkers from './pages/admin/WorkersPage';

function AppRoutes() {
  const location = useLocation();
  const background = (location.state as { background?: Location })?.background;

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
