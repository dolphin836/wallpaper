import { useState, useEffect, useMemo } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineDelete,
  AiOutlineFullscreen,
  AiOutlineClose,
} from 'react-icons/ai';
import { MdOpenInNew, MdPhoneIphone } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { WallpaperDetail, WallpaperVariant } from '../types';
import DeviceMockup, { canShowMockup } from '../components/DeviceMockup';
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

function formatTimeAgo(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diff = now - then;
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hour${hours > 1 ? 's' : ''} ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} day${days > 1 ? 's' : ''} ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} month${months > 1 ? 's' : ''} ago`;
  return `${Math.floor(months / 12)} year${Math.floor(months / 12) > 1 ? 's' : ''} ago`;
}

function formatNumber(n: number): string {
  if (n >= 1000000) return `${(n / 1000000).toFixed(1)}M`;
  if (n >= 1000) return `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}K`;
  return n.toLocaleString();
}

function isLightColor(hex: string): boolean {
  const c = hex.replace('#', '');
  const r = parseInt(c.substring(0, 2), 16);
  const g = parseInt(c.substring(2, 4), 16);
  const b = parseInt(c.substring(4, 6), 16);
  return (0.299 * r + 0.587 * g + 0.114 * b) > 150;
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

async function triggerDownload(url: string, filename: string) {
  try {
    const resp = await fetch(url);
    const blob = await resp.blob();
    const blobUrl = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = blobUrl;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(blobUrl);
  } catch {
    toast.error('Download failed');
  }
}

function findBestMatch(variants: WallpaperVariant[]): WallpaperVariant | null {
  const sw = window.screen.width * (window.devicePixelRatio || 1);
  const sh = window.screen.height * (window.devicePixelRatio || 1);

  let best: WallpaperVariant | null = null;
  let bestDiff = Infinity;

  for (const v of variants) {
    const diff = Math.abs(v.width - sw) + Math.abs(v.height - sh);
    if (diff < bestDiff) {
      bestDiff = diff;
      best = v;
    }
  }

  const threshold = Math.max(sw, sh) * 0.3;
  if (best && bestDiff > threshold) return null;
  return best;
}

function MetaItem({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-[11px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-1">
        {label}
      </div>
      <div className="text-lg font-bold text-gray-900 dark:text-white">
        {value}
      </div>
    </div>
  );
}

function VariantList({ variants, onMockup }: { variants: WallpaperVariant[]; onMockup: (v: WallpaperVariant) => void }) {
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
            <h4 className="text-[11px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-2">
              {platformIcons[platform]} {platformLabels[platform] || platform}
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
              {items.map((v) => {
                const mockupOk = canShowMockup(v);
                return (
                  <div
                    key={v.id}
                    className="flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-700 rounded-xl"
                  >
                    <div>
                      <div className="text-sm font-medium text-gray-800 dark:text-gray-100">
                        {v.brand} {v.device_name}
                      </div>
                      <div className="text-xs text-gray-500 dark:text-gray-400">
                        {v.width} &times; {v.height} &middot; {formatFileSize(v.file_size)}
                      </div>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => onMockup(v)}
                        disabled={!mockupOk}
                        className={`p-2 rounded-lg transition-colors ${
                          mockupOk
                            ? 'text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 dark:hover:bg-gray-600'
                            : 'text-gray-200 dark:text-gray-600 cursor-not-allowed'
                        }`}
                        title={mockupOk ? 'Device mockup' : 'Screen too small for this device mockup'}
                      >
                        <MdPhoneIphone size={18} />
                      </button>
                      <button
                        onClick={() => triggerDownload(v.url, `${v.brand}_${v.device_name}_${v.width}x${v.height}.jpg`)}
                        className="p-2 text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 dark:hover:bg-gray-600 rounded-lg transition-colors"
                        title="Download"
                      >
                        <AiOutlineDownload size={18} />
                      </button>
                      <a
                        href={v.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="p-2 text-gray-400 hover:text-indigo-600 hover:bg-indigo-50 dark:hover:bg-gray-600 rounded-lg transition-colors"
                        title="View in new tab"
                      >
                        <MdOpenInNew size={18} />
                      </a>
                    </div>
                  </div>
                );
              })}
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
  const [fullscreen, setFullscreen] = useState(false);
  const [mockupVariant, setMockupVariant] = useState<WallpaperVariant | null>(null);

  const matchedVariant = useMemo(() => findBestMatch(variants), [variants]);
  const canMockupMatched = useMemo(() => matchedVariant ? canShowMockup(matchedVariant) : false, [matchedVariant]);

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

  useEffect(() => {
    if (!fullscreen && !mockupVariant) return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setFullscreen(false);
        setMockupVariant(null);
      }
    };
    document.addEventListener('keydown', handleEsc);
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', handleEsc);
      document.body.style.overflow = '';
    };
  }, [fullscreen, mockupVariant]);

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

  const handleDownload = async () => {
    if (!wallpaper) return;
    const url = downloadWallpaper(wallpaper.id);
    try {
      const resp = await fetch(url);
      const finalUrl = resp.url;
      const blob = await resp.blob();
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = blobUrl;
      const ext = finalUrl.split('.').pop()?.split('?')[0] || 'jpg';
      a.download = `wallpaper_${wallpaper.id}_${wallpaper.width}x${wallpaper.height}.${ext}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
      setWallpaper({ ...wallpaper, download_count: wallpaper.download_count + 1 });
    } catch {
      toast.error('Download failed');
    }
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

  if (loading) return <Spinner />;
  if (!wallpaper) return <EmptyState message="Wallpaper not found." />;

  const isOwner = user?.id === wallpaper.user_id;

  return (
    <>
      {mockupVariant && (
        <DeviceMockup
          imageUrl={mockupVariant.url}
          platform={mockupVariant.platform}
          deviceName={`${mockupVariant.brand} ${mockupVariant.device_name}`}
          deviceWidth={mockupVariant.width}
          deviceHeight={mockupVariant.height}
          onClose={() => setMockupVariant(null)}
        />
      )}

      {fullscreen && (
        <div
          className="fixed inset-0 z-50 bg-black flex items-center justify-center"
          onClick={() => setFullscreen(false)}
        >
          <img
            src={matchedVariant?.url || wallpaper.preview_url || wallpaper.original_url}
            alt=""
            className="w-full h-full object-contain"
          />
          <button
            onClick={() => setFullscreen(false)}
            className="absolute top-4 right-4 p-2 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
          >
            <AiOutlineClose size={24} />
          </button>
          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 px-4 py-2 bg-black/50 text-white text-sm rounded-lg">
            {matchedVariant
              ? <>{matchedVariant.brand} {matchedVariant.device_name} &middot; {matchedVariant.width} &times; {matchedVariant.height}</>
              : <>{wallpaper.width} &times; {wallpaper.height}</>
            }
          </div>
        </div>
      )}

      <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-200 dark:border-gray-700 overflow-hidden">
          {/* Image */}
          <div
            className="w-full flex items-center justify-center bg-gray-100"
            style={{ backgroundColor: wallpaper.dominant_color || undefined }}
          >
            <img
              src={wallpaper.preview_url || wallpaper.original_url}
              alt=""
              className="max-h-[70vh] w-full object-contain"
            />
          </div>

          {/* Info Panel */}
          <div className="p-6 sm:p-8 space-y-8">

            {/* Actions: Download + Like + Favorite + Preview + Mockup */}
            <div className="flex items-center gap-3 flex-wrap">
              <button
                onClick={handleDownload}
                className="flex-1 sm:flex-none flex items-center justify-center gap-3 px-8 py-3.5 text-base font-semibold text-white bg-gray-900 hover:bg-gray-800 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-100 rounded-full transition-colors duration-200"
              >
                <AiOutlineDownload size={20} />
                <span>Download</span>
                <span className="text-sm font-normal opacity-70">
                  {wallpaper.width}&times;{wallpaper.height} &middot; {formatFileSize(wallpaper.file_size)}
                </span>
              </button>

              <button
                onClick={handleLike}
                disabled={likeLoading}
                className={`w-12 h-12 flex items-center justify-center rounded-full border-2 transition-colors duration-200 shrink-0 ${
                  wallpaper.is_liked
                    ? 'border-red-200 bg-red-50 text-red-500'
                    : 'border-gray-200 text-gray-400 hover:border-gray-300 hover:text-gray-500'
                }`}
              >
                {wallpaper.is_liked ? <AiFillHeart size={22} /> : <AiOutlineHeart size={22} />}
              </button>

              <button
                onClick={handleFavorite}
                disabled={favLoading}
                className={`w-12 h-12 flex items-center justify-center rounded-full border-2 transition-colors duration-200 shrink-0 ${
                  wallpaper.is_favorited
                    ? 'border-amber-200 bg-amber-50 text-amber-500'
                    : 'border-gray-200 text-gray-400 hover:border-gray-300 hover:text-gray-500'
                }`}
              >
                {wallpaper.is_favorited ? <AiFillStar size={22} /> : <AiOutlineStar size={22} />}
              </button>

              <button
                onClick={() => matchedVariant && setFullscreen(true)}
                disabled={!matchedVariant}
                title={matchedVariant ? `Fullscreen preview (${matchedVariant.brand} ${matchedVariant.device_name})` : 'No matching resolution for your device'}
                className={`w-12 h-12 flex items-center justify-center rounded-full border-2 transition-colors duration-200 shrink-0 ${
                  matchedVariant
                    ? 'border-gray-200 text-gray-400 hover:border-gray-300 hover:text-gray-500'
                    : 'border-gray-100 text-gray-200 cursor-not-allowed'
                }`}
              >
                <AiOutlineFullscreen size={22} />
              </button>

              <button
                onClick={() => matchedVariant && setMockupVariant(matchedVariant)}
                disabled={!matchedVariant || !canMockupMatched}
                title={
                  !matchedVariant
                    ? 'No matching device'
                    : !canMockupMatched
                      ? 'Screen too small for device mockup'
                      : `Device mockup (${matchedVariant.brand} ${matchedVariant.device_name})`
                }
                className={`w-12 h-12 flex items-center justify-center rounded-full border-2 transition-colors duration-200 shrink-0 ${
                  matchedVariant && canMockupMatched
                    ? 'border-gray-200 text-gray-400 hover:border-gray-300 hover:text-gray-500'
                    : 'border-gray-100 text-gray-200 cursor-not-allowed'
                }`}
              >
                <MdPhoneIphone size={22} />
              </button>
            </div>

            {/* Metadata Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-6">
              <MetaItem label="Resolution" value={`${wallpaper.width}\u00D7${wallpaper.height}`} />
              <MetaItem label="File Size" value={formatFileSize(wallpaper.file_size)} />
              <MetaItem label="Likes" value={formatNumber(wallpaper.like_count)} />
              <MetaItem label="Downloads" value={formatNumber(wallpaper.download_count)} />
              <MetaItem label="Views" value={formatNumber(wallpaper.view_count)} />
              <MetaItem label="Uploaded" value={formatTimeAgo(wallpaper.created_at)} />
            </div>

            {/* Color Palette */}
            {wallpaper.color_palette && (
              <div>
                <h4 className="text-[11px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-3">
                  Palette
                </h4>
                <div className="flex rounded-xl overflow-hidden h-14">
                  {wallpaper.color_palette.split(',').map((hex) => (
                    <div
                      key={hex}
                      className="flex-1 flex items-end justify-center pb-1.5 group relative cursor-pointer"
                      style={{ backgroundColor: hex }}
                      onClick={() => { navigator.clipboard.writeText(hex); toast.success(`Copied ${hex}`); }}
                    >
                      <span className="text-[10px] font-mono font-semibold opacity-80 drop-shadow-sm"
                        style={{ color: isLightColor(hex) ? '#000' : '#fff' }}
                      >
                        {hex}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Uploader */}
            <div className="flex items-center justify-between pt-6 border-t border-gray-100 dark:border-gray-700">
              <Link to={`/user/${wallpaper.uploader.id}`} className="flex items-center gap-3 hover:opacity-80 transition-opacity">
                {wallpaper.uploader.avatar_url ? (
                  <img src={wallpaper.uploader.avatar_url} alt="" className="w-10 h-10 rounded-full object-cover" />
                ) : (
                  <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold text-sm">
                    {(wallpaper.uploader.nickname || wallpaper.uploader.username).charAt(0).toUpperCase()}
                  </div>
                )}
                <div>
                  <div className="text-sm font-semibold text-gray-800 dark:text-gray-100">
                    {wallpaper.uploader.nickname || wallpaper.uploader.username}
                  </div>
                  <div className="text-xs text-gray-400">Uploader</div>
                </div>
              </Link>

              {isOwner && (
                <button
                  onClick={handleDelete}
                  className="flex items-center gap-2 px-4 py-2 text-sm font-medium text-red-500 hover:text-red-600 hover:bg-red-50 rounded-lg transition-colors duration-200"
                >
                  <AiOutlineDelete size={16} />
                  Delete
                </button>
              )}
            </div>

            {/* Device Variants */}
            {variants.length > 0 && (
              <div className="pt-6 border-t border-gray-100 dark:border-gray-700">
                <button
                  onClick={() => setShowVariants(!showVariants)}
                  className="flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200 mb-4 w-full"
                >
                  <MdPhoneIphone size={18} />
                  Available Devices ({variants.length})
                  <svg
                    className={`w-4 h-4 ml-auto transition-transform ${showVariants ? 'rotate-180' : ''}`}
                    fill="none" viewBox="0 0 24 24" stroke="currentColor"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                {showVariants && (
                  <VariantList variants={variants} onMockup={setMockupVariant} />
                )}
              </div>
            )}

          </div>
        </div>
      </div>
    </>
  );
}
