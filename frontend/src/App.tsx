import { BrowserRouter, Routes, Route } from 'react-router-dom';
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
function App() {
  return (
    <BrowserRouter>
      <Toaster position="top-center" />
      <Routes>
        <Route element={<Layout />}>
          <Route path="/" element={<HomePage />} />
          <Route path="/login" element={<LoginPage />} />
          <Route path="/register" element={<RegisterPage />} />
          <Route path="/wallpaper/:id" element={<WallpaperDetailPage />} />
          <Route path="/upload" element={<UploadPage />} />
          <Route path="/user/:id" element={<ProfilePage />} />
          <Route path="/collections" element={<CollectionsPage />} />
          <Route path="/uploaders" element={<UploadersPage />} />
          <Route path="/collections/:id" element={<CollectionDetailPage />} />
          <Route path="/terms" element={<TermsPage />} />
          <Route path="/privacy" element={<PrivacyPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  );
}

export default App;
