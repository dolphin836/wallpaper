import { BrowserRouter, Routes, Route, useLocation } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';
import Layout from './components/Layout';
import HomePage from './pages/HomePage';
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
import DownloadMacPage from './pages/DownloadMacPage';
import WallpaperDetailModal from './components/WallpaperDetailModal';
import AdminLayout from './pages/admin/AdminLayout';
import AdminDashboard from './pages/admin/DashboardPage';
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
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterPage />} />
          <Route path="/wallpaper/:slug" element={<WallpaperDetailPage />} />
          <Route path="/upload" element={<UploadPage />} />
          <Route path="/user/:username" element={<ProfilePage />} />
          <Route path="/collections" element={<CollectionsPage />} />
          <Route path="/uploaders" element={<UploadersPage />} />
          <Route path="/collections/:slug" element={<CollectionDetailPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
          <Route path="/legal/dmca" element={<LegalDmcaPage />} />
          <Route path="/download/mac" element={<DownloadMacPage />} />
        </Route>
        <Route path="/admin" element={<AdminLayout />}>
          <Route index element={<AdminDashboard />} />
          <Route path="wallpapers" element={<AdminWallpapers />} />
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
      <Toaster position="top-center" />
      <AppRoutes />
    </BrowserRouter>
  );
}

export default App;
