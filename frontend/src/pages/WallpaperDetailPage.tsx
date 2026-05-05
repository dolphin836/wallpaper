import { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineEye,
  AiOutlineDelete,
} from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { WallpaperDetail, WallpaperVariant } from '../types';
import {
  getWallpaper,
  likeWallpaper,
  unlikeWallpaper,
  favoriteWallpaper,
  unfavoriteWallpaper,
  deleteWallpaper,
  downloadWallpaper,
  getWallpaperVariants,
} from '../api';
import { useAuthStore } from '../store/auth';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

const platformLabels: Record<string, string> = {
  desktop: 'Desktop',
  laptop: 'Laptop',
  tablet: 'Tablet',
  phone: 'Phone',
};

const platformIcons: Record<string, string> = {
  desktop: '🖥',
  laptop: '💻',
  tablet: '📱',
  phone: '📲',
};

function VariantList({ variants }: { variants: WallpaperVariant[] }) {
  const grouped = variants.reduce<Record<string, WallpaperVariant[]>>((acc, v) => {
    const key = v.platform;
    if (!acc[key]) acc[key] = [];
    acc[key].push(v);
    return acc;
  }, {});

  const platformOrder = ['desktop', 'laptop', 'tablet', 'phone'];

  return (
    <div className="space-y-4">
      {platformOrder.map((platform) => {
        const items = grouped[platform];
        if (!items || items.length === 0) return null;
        return (
          <div key={platform}>
            <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-2">
              {platformIcons[platform]} {platformLabels[platform] || platform}
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {items.map((v) => (
                <a
                  key={v.id}
                  href={v.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-700 hover:bg-indigo-50 dark:hover:bg-gray-600 rounded-lg transition-colors duration-200 group"
                >
                  <div>
                    <div className="text-sm font-medium text-gray-800 dark:text-gray-100 group-hover:text-indigo-600 dark:group-hover:text-indigo-400">
                      {v.brand} {v.device_name}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400">
                      {v.width} &times; {v.height} &middot; {formatFileSize(v.file_size)}
                    </div>
                  </div>
                  <AiOutlineDownload size={18} className="text-gray-400 group-hover:text-indigo-600 dark:group-hover:text-indigo-400 shrink-0" />
                </a>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function WallpaperDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { isAuthenticated, user } = useAuthStore();
  const [wallpaper, setWallpaper] = useState<WallpaperDetail | null>(null);
  const [variants, setVariants] = useState<WallpaperVariant[]>([]);
  const [loading, setLoading] = useState(true);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favLoading, setFavLoading] = useState(false);
  const [showVariants, setShowVariants] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    const numId = Number(id);
    Promise.all([
      getWallpaper(numId),
      getWallpaperVariants(numId),
    ])
      .then(([wpRes, varRes]) => {
        setWallpaper(wpRes.data.data);
        setVariants(varRes.data.data || []);
      })
      .catch(() => toast.error('Failed to load wallpaper'))
      .finally(() => setLoading(false));
  }, [id]);

  const handleLike = async () => {
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper || likeLoading) return;
    setLikeLoading(true);
    try {
      if (wallpaper.is_liked) {
        await unlikeWallpaper(wallpaper.id);
        setWallpaper({ ...wallpaper, is_liked: false, like_count: wallpaper.like_count - 1 });
      } else {
        await likeWallpaper(wallpaper.id);
        setWallpaper({ ...wallpaper, is_liked: true, like_count: wallpaper.like_count + 1 });
      }
    } catch {
      toast.error('Action failed');
    } finally {
      setLikeLoading(false);
    }
  };

  const handleFavorite = async () => {
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper || favLoading) return;
    setFavLoading(true);
    try {
      if (wallpaper.is_favorited) {
        await unfavoriteWallpaper(wallpaper.id);
        setWallpaper({ ...wallpaper, is_favorited: false, favorite_count: wallpaper.favorite_count - 1 });
      } else {
        await favoriteWallpaper(wallpaper.id);
        setWallpaper({ ...wallpaper, is_favorited: true, favorite_count: wallpaper.favorite_count + 1 });
      }
    } catch {
      toast.error('Action failed');
    } finally {
      setFavLoading(false);
    }
  };

  const handleDownload = () => {
    if (!wallpaper) return;
    window.open(downloadWallpaper(wallpaper.id), '_blank');
  };

  const handleDelete = async () => {
    if (!wallpaper) return;
    if (!confirm('Delete this wallpaper?')) return;
    try {
      await deleteWallpaper(wallpaper.id);
      toast.success('Wallpaper deleted');
      navigate('/');
    } catch {
      toast.error('Delete failed');
    }
  };

  if (loading) {
    return <Spinner />;
  }

  if (!wallpaper) {
    return <EmptyState message="Wallpaper not found." />;
  }

  const isOwner = user?.id === wallpaper.user_id;

  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-200 dark:border-gray-700 overflow-hidden">
        <div
          className="w-full flex items-center justify-center bg-gray-100"
          style={{ backgroundColor: wallpaper.dominant_color || undefined }}
        >
          <img
            src={wallpaper.preview_url || wallpaper.original_url}
            alt={wallpaper.title}
            className="max-h-[70vh] w-full object-contain"
          />
        </div>

        <div className="p-6 sm:p-8">
          <div className="flex flex-col sm:flex-row sm:items-start justify-between gap-4 mb-6">
            <div>
              <h1 className="text-2xl font-bold text-gray-900 dark:text-white">{wallpaper.title}</h1>
              {wallpaper.description && (
                <p className="mt-2 text-gray-600 dark:text-gray-400">{wallpaper.description}</p>
              )}
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <button
                onClick={handleLike}
                disabled={likeLoading}
                className={`flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
                  wallpaper.is_liked
                    ? 'bg-red-50 text-red-600 hover:bg-red-100'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {wallpaper.is_liked ? <AiFillHeart size={18} /> : <AiOutlineHeart size={18} />}
                {wallpaper.like_count}
              </button>
              <button
                onClick={handleFavorite}
                disabled={favLoading}
                className={`flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg transition-colors duration-200 ${
                  wallpaper.is_favorited
                    ? 'bg-amber-50 text-amber-600 hover:bg-amber-100'
                    : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                }`}
              >
                {wallpaper.is_favorited ? <AiFillStar size={18} /> : <AiOutlineStar size={18} />}
                {wallpaper.favorite_count}
              </button>
              <button
                onClick={handleDownload}
                className="flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors duration-200"
              >
                <AiOutlineDownload size={18} />
                Download
              </button>
            </div>
          </div>

          <div className="flex items-center gap-3 mb-6">
            <Link to={`/user/${wallpaper.uploader.id}`} className="flex items-center gap-3 hover:opacity-80 transition-opacity">
              {wallpaper.uploader.avatar_url ? (
                <img src={wallpaper.uploader.avatar_url} alt="" className="w-10 h-10 rounded-full object-cover" />
              ) : (
                <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold">
                  {(wallpaper.uploader.nickname || wallpaper.uploader.username).charAt(0).toUpperCase()}
                </div>
              )}
              <span className="text-sm font-medium text-gray-700 dark:text-gray-200">
                {wallpaper.uploader.nickname || wallpaper.uploader.username}
              </span>
            </Link>
          </div>

          {wallpaper.tags.length > 0 && (
            <div className="flex flex-wrap gap-2 mb-6">
              {wallpaper.tags.map((tag) => (
                <span
                  key={tag.id}
                  className="px-3 py-1 text-xs font-medium bg-indigo-50 text-indigo-600 rounded-full"
                >
                  {tag.name}
                </span>
              ))}
            </div>
          )}

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 py-4 border-t border-gray-100 dark:border-gray-700">
            <div className="text-center">
              <div className="flex items-center justify-center gap-1 text-gray-400 mb-1">
                <AiOutlineEye size={16} />
              </div>
              <div className="text-lg font-semibold text-gray-900 dark:text-white">{wallpaper.view_count}</div>
              <div className="text-xs text-gray-500 dark:text-gray-400">Views</div>
            </div>
            <div className="text-center">
              <div className="text-lg font-semibold text-gray-900 dark:text-white">
                {wallpaper.width} &times; {wallpaper.height}
              </div>
              <div className="text-xs text-gray-500 dark:text-gray-400">Resolution</div>
            </div>
            <div className="text-center">
              <div className="text-lg font-semibold text-gray-900 dark:text-white">{formatFileSize(wallpaper.file_size)}</div>
              <div className="text-xs text-gray-500 dark:text-gray-400">File Size</div>
            </div>
            <div className="text-center">
              <div className="text-lg font-semibold text-gray-900 dark:text-white">{wallpaper.download_count}</div>
              <div className="text-xs text-gray-500 dark:text-gray-400">Downloads</div>
            </div>
          </div>

          {variants.length > 0 && (
            <div className="mt-6 pt-6 border-t border-gray-100 dark:border-gray-700">
              <button
                onClick={() => setShowVariants(!showVariants)}
                className="flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200 mb-4"
              >
                <AiOutlineDownload size={18} />
                Download for your device ({variants.length} resolutions)
                <svg
                  className={`w-4 h-4 transition-transform ${showVariants ? 'rotate-180' : ''}`}
                  fill="none" viewBox="0 0 24 24" stroke="currentColor"
                >
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                </svg>
              </button>
              {showVariants && (
                <VariantList variants={variants} />
              )}
            </div>
          )}

          {isOwner && (
            <div className="mt-6 pt-6 border-t border-gray-100 dark:border-gray-700">
              <button
                onClick={handleDelete}
                className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-red-600 bg-red-50 hover:bg-red-100 rounded-lg transition-colors duration-200"
              >
                <AiOutlineDelete size={18} />
                Delete Wallpaper
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
