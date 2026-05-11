import { useState, useEffect, useMemo, useCallback } from 'react';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineDelete,
  AiOutlineFullscreen,
  AiOutlineClose,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import { MdPhoneIphone, MdPlaylistAdd } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User } from '../types';
import DeviceMockup, { canShowMockup } from '../components/DeviceMockup';
import {
  getWallpaper,
  likeWallpaper,
  unlikeWallpaper,
  favoriteWallpaper,
  unfavoriteWallpaper,
  deleteWallpaper,
  downloadWallpaper,
  downloadVariant,
  getWallpaperVariants,
  getWallpaperEngagements,
} from '../api';
import { useAuthStore } from '../store/auth';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';
import AvatarStack from '../components/AvatarStack';
import { MdDesktopMac } from 'react-icons/md';
import AddToCollectionModal from '../components/AddToCollectionModal';
import SetWallpaperGuide from '../components/SetWallpaperGuide';

function isMacOS(): boolean {
  return /Macintosh|Mac OS X/i.test(navigator.userAgent);
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
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

function VariantList({ variants, matchedId, onMockup, onDownload }: { variants: WallpaperVariant[]; matchedId?: number; onMockup: (v: WallpaperVariant) => void; onDownload: (v: WallpaperVariant) => void }) {
  const grouped = variants.reduce<Record<string, WallpaperVariant[]>>((acc, v) => {
    const key = v.platform;
    if (!acc[key]) acc[key] = [];
    acc[key].push(v);
    return acc;
  }, {});

  const platformOrder = ['desktop', 'laptop', 'tablet', 'phone'];

  return (
    <div className="space-y-6">
      {platformOrder.map((platform) => {
        const items = grouped[platform];
        if (!items || items.length === 0) return null;
        return (
          <div key={platform}>
            <h4 className="text-[11px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500 mb-3">
              {platformIcons[platform]} {platformLabels[platform] || platform}
            </h4>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {items.map((v) => {
                const mockupOk = canShowMockup(v);
                const isMatched = v.id === matchedId;
                return (
                  <div
                    key={v.id}
                    className={`relative rounded-xl border transition-colors ${
                      isMatched
                        ? 'border-indigo-300 bg-indigo-50/50 dark:border-indigo-500/40 dark:bg-indigo-950/20'
                        : 'border-gray-100 bg-gray-50/50 dark:border-gray-700 dark:bg-gray-800/50'
                    }`}
                  >
                    {isMatched && (
                      <span className="absolute -top-2.5 left-3 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider bg-indigo-500 text-white rounded-full">
                        Your Device
                      </span>
                    )}
                    <div className="px-4 py-3.5">
                      <div className="flex items-center justify-between mb-2">
                        <div className="text-sm font-semibold text-gray-800 dark:text-gray-100">
                          {v.brand} {v.device_name}
                        </div>
                      </div>
                      <div className="grid grid-cols-3 gap-2 mb-3">
                        <div>
                          <div className="text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Resolution</div>
                          <div className="text-sm font-bold text-gray-700 dark:text-gray-200">{v.width}&times;{v.height}</div>
                        </div>
                        <div>
                          <div className="text-[10px] font-semibold uppercase tracking-wider text-gray-400 dark:text-gray-500">Size</div>
                          <div className="text-sm font-bold text-gray-700 dark:text-gray-200">{formatFileSize(v.file_size)}</div>
                        </div>
                        <div className="flex items-end justify-end gap-1">
                          <button
                            onClick={() => onMockup(v)}
                            disabled={!mockupOk}
                            className={`p-1.5 rounded-lg transition-colors ${
                              mockupOk
                                ? 'text-gray-400 hover:text-indigo-600 hover:bg-indigo-100 dark:hover:bg-gray-600'
                                : 'text-gray-200 dark:text-gray-600 cursor-not-allowed'
                            }`}
                            title={mockupOk ? 'Device mockup' : 'Screen too small'}
                          >
                            <MdPhoneIphone size={16} />
                          </button>
                          <button
                            onClick={() => onDownload(v)}
                            className="p-1.5 text-gray-400 hover:text-indigo-600 hover:bg-indigo-100 dark:hover:bg-gray-600 rounded-lg transition-colors"
                            title="Download"
                          >
                            <AiOutlineDownload size={16} />
                          </button>
                        </div>
                      </div>
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
  const { slug: id } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const { isAuthenticated, user, updateCoins } = useAuthStore();
  const initialWallpaper = (location.state as { initialWallpaper?: Wallpaper } | null)?.initialWallpaper;
  // Hydrate from list snapshot so the preview renders immediately; uploader/tags are filled in by the detail fetch.
  const [wallpaper, setWallpaper] = useState<WallpaperDetail | null>(() =>
    initialWallpaper
      ? ({ ...initialWallpaper, tags: [], uploader: undefined as unknown as User } as WallpaperDetail)
      : null
  );
  usePageTitle(wallpaper ? `${wallpaper.width}×${wallpaper.height} Wallpaper` : 'Wallpaper');
  const [variants, setVariants] = useState<WallpaperVariant[]>([]);
  const [loading, setLoading] = useState(!initialWallpaper);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favLoading, setFavLoading] = useState(false);
  const [showVariants, setShowVariants] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [mockupVariant, setMockupVariant] = useState<WallpaperVariant | null>(null);
  const [showAddToCollection, setShowAddToCollection] = useState(false);
  const [showGuide, setShowGuide] = useState(false);
  const [dlLoading, setDlLoading] = useState(false);
  const [dlDone, setDlDone] = useState(false);
  const [frameIdx, setFrameIdx] = useState(0);
  const [framePlaying, setFramePlaying] = useState(true);
  const [engagements, setEngagements] = useState<Engagements | null>(null);

  const frames = useMemo(() => {
    if (!wallpaper?.frame_urls) return [];
    return wallpaper.frame_urls.split(',').filter(Boolean);
  }, [wallpaper?.frame_urls]);

  const nextFrame = useCallback(() => {
    setFrameIdx((prev) => (prev + 1) % (frames.length || 1));
  }, [frames.length]);

  useEffect(() => {
    if (!framePlaying || frames.length < 2) return;
    const timer = setInterval(nextFrame, 2500);
    return () => clearInterval(timer);
  }, [framePlaying, frames.length, nextFrame]);

  const matchedVariant = useMemo(() => findBestMatch(variants), [variants]);
  const canMockupMatched = useMemo(() => matchedVariant ? canShowMockup(matchedVariant) : false, [matchedVariant]);

  useEffect(() => {
    if (!id) return;
    getWallpaper(id)
      .then(async (wpRes) => {
        const wp = wpRes.data.data;
        setWallpaper(wp);
        setDlDone(wp.is_downloaded ?? false);
        try {
          const varRes = await getWallpaperVariants(wp.id);
          setVariants(varRes.data.data || []);
        } catch { /* variants optional */ }
        getWallpaperEngagements(wp.id)
          .then((res) => setEngagements(res.data.data))
          .catch(() => { /* non-critical */ });
      })
      .catch(() => {
        if (!initialWallpaper) toast.error('Failed to load wallpaper');
      })
      .finally(() => setLoading(false));
    // initialWallpaper is read once from navigation state; intentionally not a dep.
    // eslint-disable-next-line react-hooks/exhaustive-deps
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

  const handleDownload = async (variant?: WallpaperVariant) => {
    if (dlLoading) return;
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper) return;
    const isOwnerDl = user?.id === wallpaper.user_id;
    if (!isOwnerDl && user && user.coins <= 0) {
      toast.error('Insufficient coins. Upload wallpapers to earn more!');
      return;
    }
    const useVariant = wallpaper.is_dynamic ? null : (variant || matchedVariant);
    setDlLoading(true);
    try {
      let blobUrl: string;
      let filename: string;
      if (useVariant) {
        const apiResp = await downloadVariant(wallpaper.id, useVariant.id);
        const dlUrl = apiResp.data.data?.url;
        if (!dlUrl) { toast.error('Download failed'); return; }
        const resp = await fetch(dlUrl);
        const blob = await resp.blob();
        blobUrl = URL.createObjectURL(blob);
        filename = `wallpaper_${wallpaper.id}_${useVariant.width}x${useVariant.height}.jpg`;
      } else {
        const url = downloadWallpaper(wallpaper.id);
        const resp = await fetch(url, {
          headers: { Authorization: `Bearer ${useAuthStore.getState().token}` },
        });
        if (resp.status === 402) {
          toast.error('Insufficient coins. Upload wallpapers to earn more!');
          return;
        }
        if (!resp.ok) {
          toast.error('Download failed');
          return;
        }
        const finalUrl = resp.url;
        const blob = await resp.blob();
        blobUrl = URL.createObjectURL(blob);
        const ext = finalUrl.split('.').pop()?.split('?')[0] || 'jpg';
        filename = `wallpaper_${wallpaper.id}_${wallpaper.width}x${wallpaper.height}.${ext}`;
      }
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
      setWallpaper({ ...wallpaper, download_count: wallpaper.download_count + 1 });
      setDlDone(true);
      if (!isOwnerDl && user) {
        const remaining = user.coins - 1;
        updateCoins(remaining);
        if (remaining <= 3 && remaining > 0) {
          toast(`${remaining} coin${remaining === 1 ? '' : 's'} left. Upload wallpapers to earn more!`, { icon: '💡' });
        }
      }
      setShowGuide(true);
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 402) {
        toast.error('Insufficient coins. Upload wallpapers to earn more!');
      } else {
        toast.error('Download failed');
      }
    } finally {
      setDlLoading(false);
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
      {showAddToCollection && wallpaper && (
        <AddToCollectionModal wallpaperId={wallpaper.id} onClose={() => setShowAddToCollection(false)} />
      )}

      {showGuide && <SetWallpaperGuide onClose={() => setShowGuide(false)} />}

      {mockupVariant && wallpaper && (
        <DeviceMockup
          imageUrl={wallpaper.preview_url || wallpaper.original_url}
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
            onContextMenu={(e) => e.preventDefault()}
            draggable={false}
            className="w-full h-full object-contain select-none"
            style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
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

      <div className="max-w-5xl mx-auto px-6 py-6">
        <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-sm border border-gray-200 dark:border-gray-700 overflow-hidden">
          {/* Image / Dynamic Slideshow */}
          <div className="relative">
            <div
              className="relative w-full flex items-center justify-center bg-gray-100 overflow-hidden mx-auto"
              style={{
                aspectRatio: wallpaper.width > 0 && wallpaper.height > 0
                  ? `${wallpaper.width} / ${wallpaper.height}`
                  : undefined,
                maxHeight: '70vh',
                backgroundColor: wallpaper.dominant_color || undefined,
              }}
            >
              {frames.length > 1 ? (
                <div className="relative w-full h-full">
                  {frames.map((url, i) => (
                    <img
                      key={i}
                      src={url}
                      alt=""
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      className={`absolute inset-0 w-full h-full object-contain select-none transition-opacity duration-1000 ${
                        i === frameIdx ? 'opacity-100' : 'opacity-0'
                      }`}
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                  ))}
                </div>
              ) : (
                <img
                  src={wallpaper.preview_url || wallpaper.original_url}
                  alt=""
                  onContextMenu={(e) => e.preventDefault()}
                  draggable={false}
                  className="w-full h-full object-contain select-none"
                  style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                />
              )}
              <div className="absolute inset-0 z-[1]" onContextMenu={(e) => e.preventDefault()} />
            </div>

            {wallpaper.is_dynamic && (
              <span className="absolute top-3 left-3 flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold rounded-full bg-black/60 text-white backdrop-blur-sm shadow-lg">
                <svg width="14" height="14" viewBox="0 0 384 512" fill="currentColor"><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
                macOS
              </span>
            )}

            {frames.length > 1 && (
              <div className="absolute bottom-3 left-1/2 -translate-x-1/2 flex items-center gap-2 px-3 py-1.5 rounded-full bg-black/50 backdrop-blur-sm">
                <button
                  onClick={() => setFramePlaying((p) => !p)}
                  className="text-white/80 hover:text-white transition-colors"
                  title={framePlaying ? 'Pause' : 'Play'}
                >
                  {framePlaying ? (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>
                  ) : (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><polygon points="5,3 19,12 5,21"/></svg>
                  )}
                </button>
                <div className="flex gap-1.5">
                  {frames.map((_, i) => (
                    <button
                      key={i}
                      onClick={() => { setFrameIdx(i); setFramePlaying(false); }}
                      className={`w-1.5 h-1.5 rounded-full transition-all ${
                        i === frameIdx ? 'bg-white scale-125' : 'bg-white/40 hover:bg-white/60'
                      }`}
                    />
                  ))}
                </div>
                <span className="text-[10px] text-white/60 font-mono ml-1">
                  {frameIdx + 1}/{frames.length}
                </span>
              </div>
            )}
          </div>

          {/* Info Panel */}
          <div className="p-6 sm:p-8 space-y-8">

            {/* Actions: Download + Like + Favorite + Preview + Mockup */}
            <div className="flex items-center gap-3 flex-wrap">
              {wallpaper.is_dynamic && !isMacOS() ? (
                <div className="flex-1 sm:flex-none flex items-center gap-3 px-6 py-3 text-sm rounded-full bg-gray-100 dark:bg-gray-700 text-gray-500 dark:text-gray-400">
                  <MdDesktopMac size={20} />
                  <span>Dynamic wallpapers are only supported on macOS</span>
                </div>
              ) : (
                <button
                  onClick={() => handleDownload()}
                  disabled={dlLoading}
                  className={`flex-1 sm:flex-none flex items-center justify-center gap-3 px-8 py-3.5 text-base font-semibold rounded-full transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed ${
                    dlDone
                      ? 'text-white bg-green-600 hover:bg-green-700'
                      : 'text-white bg-gray-900 hover:bg-gray-800 dark:bg-white dark:text-gray-900 dark:hover:bg-gray-100'
                  }`}
                >
                  {dlLoading ? <AiOutlineLoading3Quarters size={20} className="animate-spin" /> : dlDone ? <AiOutlineCheckCircle size={20} /> : <AiOutlineDownload size={20} />}
                  <span>Download</span>
                  <span className="text-sm font-normal opacity-70">
                    {wallpaper.is_dynamic
                      ? `${wallpaper.width}\u00D7${wallpaper.height} \u00B7 ${formatFileSize(wallpaper.file_size)}`
                      : matchedVariant
                        ? `${matchedVariant.width}\u00D7${matchedVariant.height}`
                        : `${wallpaper.width}\u00D7${wallpaper.height} \u00B7 ${formatFileSize(wallpaper.file_size)}`
                    }
                  </span>
                </button>
              )}

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

              {!wallpaper.is_dynamic && (
                <>
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
                </>
              )}

              {isAuthenticated && (
                <button
                  onClick={() => setShowAddToCollection(true)}
                  title="Add to collection"
                  className="w-12 h-12 flex items-center justify-center rounded-full border-2 border-gray-200 text-gray-400 hover:border-gray-300 hover:text-gray-500 transition-colors duration-200 shrink-0"
                >
                  <MdPlaylistAdd size={22} />
                </button>
              )}
            </div>

            {isAuthenticated && user && !isOwner && user.coins <= 3 && (
              <Link
                to="/upload"
                className="flex items-center gap-2.5 px-4 py-2.5 rounded-lg bg-amber-50 dark:bg-amber-900/10 border border-amber-200/60 dark:border-amber-700/30 text-sm text-amber-700 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/20 transition-colors"
              >
                <span className="text-base">💡</span>
                {user.coins <= 0
                  ? 'No coins left — upload a wallpaper to earn coins and keep downloading.'
                  : `Only ${user.coins} coin${user.coins === 1 ? '' : 's'} remaining. Share your wallpapers to earn more!`}
              </Link>
            )}

            {/* Metadata Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-8 gap-y-6">
              <MetaItem label="Resolution" value={`${wallpaper.width}\u00D7${wallpaper.height}`} />
              <MetaItem label="File Size" value={formatFileSize(wallpaper.file_size)} />
              <div>
                <MetaItem label="Likes" value={formatNumber(wallpaper.like_count)} />
                {engagements && <AvatarStack users={engagements.likers} total={wallpaper.like_count} />}
              </div>
              <div>
                <MetaItem label="Downloads" value={formatNumber(wallpaper.download_count)} />
                {engagements && <AvatarStack users={engagements.downloaders} total={wallpaper.download_count} />}
              </div>
              <div>
                <MetaItem label="Favorites" value={formatNumber(wallpaper.favorite_count)} />
                {engagements && <AvatarStack users={engagements.favoriters} total={wallpaper.favorite_count} />}
              </div>
              <MetaItem label="Views" value={formatNumber(wallpaper.view_count)} />
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
            {wallpaper.uploader && (
              <div className="flex items-center justify-between pt-6 border-t border-gray-100 dark:border-gray-700">
                <Link to={`/user/${wallpaper.uploader.username}`} className="flex items-center gap-3 hover:opacity-80 transition-opacity">
                  {wallpaper.uploader.avatar_url ? (
                    <img src={wallpaper.uploader.avatar_url} alt="" className="w-10 h-10 rounded-full object-cover" />
                  ) : (
                    <div className="w-10 h-10 rounded-full bg-indigo-100 text-indigo-600 flex items-center justify-center font-semibold text-sm">
                      {(wallpaper.uploader.nickname || wallpaper.uploader.username).charAt(0).toUpperCase()}
                    </div>
                  )}
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-gray-800 dark:text-gray-100">
                        {wallpaper.uploader.nickname || wallpaper.uploader.username}
                      </span>
                      <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-gradient-to-r from-amber-50 to-yellow-50 dark:from-amber-900/20 dark:to-yellow-900/20 border border-amber-200/50 dark:border-amber-700/30">
                        <span className="text-xs">💰</span>
                        <span className="text-xs font-bold bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{wallpaper.uploader.coins ?? 0}</span>
                      </span>
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
            )}

            {/* Device Variants (hidden for dynamic wallpapers — no variants generated) */}
            {!wallpaper.is_dynamic && variants.length > 0 && (
              <div className="pt-6 border-t border-gray-100 dark:border-gray-700">
                <button
                  onClick={() => setShowVariants(!showVariants)}
                  className="flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-gray-200 mb-4 w-full"
                >
                  Available Devices ({variants.length})
                  <svg
                    className={`w-4 h-4 ml-auto transition-transform ${showVariants ? 'rotate-180' : ''}`}
                    fill="none" viewBox="0 0 24 24" stroke="currentColor"
                  >
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                  </svg>
                </button>
                {showVariants && (
                  <VariantList variants={variants} matchedId={matchedVariant?.id} onMockup={setMockupVariant} onDownload={(v) => handleDownload(v)} />
                )}
              </div>
            )}

          </div>
        </div>
      </div>
    </>
  );
}
