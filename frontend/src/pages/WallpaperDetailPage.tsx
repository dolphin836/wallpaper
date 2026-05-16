import { useState, useEffect, useMemo, useCallback } from 'react';
import { createPortal } from 'react-dom';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineDelete,
  AiOutlineFlag,
  AiOutlineFullscreen,
  AiOutlineClose,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import { MdPhoneIphone, MdPlaylistAdd, MdDesktopMac } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User } from '../types';
import DeviceMockup, { canShowMockup } from '../components/DeviceMockup';
import ReportModal from '../components/ReportModal';
import WallpaperCard from '../components/WallpaperCard';
import { getSimilarWallpapers } from '../api';
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
import AddToCollectionModal from '../components/AddToCollectionModal';
import SetWallpaperGuide from '../components/SetWallpaperGuide';

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


// Pick the variant whose pixel dimensions best match this screen.
// Two guards keep the match honest:
//   1. Same orientation only — never a landscape variant for a portrait screen, or vice versa.
//   2. Within 5% of the larger screen dimension on L1 distance — handles slight reporting
//      variance across iOS versions / display modes, while still rejecting wrong devices.
// URL availability is a separate concern (the file may or may not have been uploaded yet);
// matching is purely about dimensions.
function findBestMatch(variants: WallpaperVariant[]): WallpaperVariant | null {
  const dpr = window.devicePixelRatio || 1;
  const sw = Math.round(window.screen.width * dpr);
  const sh = Math.round(window.screen.height * dpr);
  const portrait = sh >= sw;

  let best: WallpaperVariant | null = null;
  let bestDiff = Infinity;
  for (const v of variants) {
    const vPortrait = v.height >= v.width;
    if (vPortrait !== portrait) continue;
    const diff = Math.abs(v.width - sw) + Math.abs(v.height - sh);
    if (diff < bestDiff) {
      bestDiff = diff;
      best = v;
    }
  }

  const tolerance = Math.max(sw, sh) * 0.05;
  if (best && bestDiff > tolerance) return null;
  return best;
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
                const isMatched = v.id === matchedId;
                // Per-variant mockup preview is only meaningful for the user's own device;
                // showing other devices' mockups in a list adds noise but no signal.
                const mockupOk = isMatched && canShowMockup(v);
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
                            title={
                              !isMatched
                                ? 'Only your matched device can be previewed here'
                                : mockupOk ? 'Device mockup' : 'Screen too small'
                            }
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
  const metaTitle = wallpaper ? `${wallpaper.width}×${wallpaper.height} Wallpaper` : 'Wallpaper';
  const metaDescription = wallpaper
    ? `Download this ${wallpaper.width}×${wallpaper.height}${wallpaper.is_dynamic ? ' dynamic' : ''} wallpaper for free on Wallpaper Exchange. HD and 4K wallpapers across multiple categories.`
    : undefined;
  const metaImage = wallpaper?.preview_url || wallpaper?.original_url;
  const jsonLd = wallpaper
    ? {
        '@context': 'https://schema.org',
        '@type': 'ImageObject',
        name: metaTitle,
        contentUrl: wallpaper.original_url,
        thumbnailUrl: wallpaper.thumb_url || wallpaper.preview_url,
        width: wallpaper.width,
        height: wallpaper.height,
        datePublished: wallpaper.created_at,
        ...(wallpaper.uploader
          ? {
              author: {
                '@type': 'Person',
                name: wallpaper.uploader.nickname || wallpaper.uploader.username,
              },
            }
          : {}),
      }
    : undefined;
  const [variants, setVariants] = useState<WallpaperVariant[]>([]);
  const [loading, setLoading] = useState(!initialWallpaper);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favLoading, setFavLoading] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  const [mockupVariant, setMockupVariant] = useState<WallpaperVariant | null>(null);
  const [showAddToCollection, setShowAddToCollection] = useState(false);
  const [showReport, setShowReport] = useState(false);
  const [similar, setSimilar] = useState<Wallpaper[]>([]);
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

  useEffect(() => {
    if (!wallpaper?.id) {
      setSimilar([]);
      return;
    }
    let cancelled = false;
    getSimilarWallpapers(wallpaper.id, 12)
      .then((res) => {
        if (!cancelled) setSimilar(res.data.data || []);
      })
      .catch(() => {
        if (!cancelled) setSimilar([]);
      });
    return () => {
      cancelled = true;
    };
  }, [wallpaper?.id]);

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


  // ─── Helpers derived from wallpaper for the editorial spread ─────────
  const palette = (wallpaper.color_palette || '').split(',').map((s) => s.trim()).filter(Boolean);
  const daysAgo = Math.max(0, Math.floor((Date.now() - new Date(wallpaper.created_at).getTime()) / 86400000));
  const resLabel = (() => {
    const px = Math.max(wallpaper.width, wallpaper.height);
    if (px >= 7680) return '8K';
    if (px >= 3840) return '4K';
    if (px >= 2560) return '2K';
    if (px >= 1920) return '1080P';
    return '';
  })();
  const copyHex = async (hex: string) => {
    try {
      await navigator.clipboard.writeText(hex);
      toast.success(`Copied ${hex.toUpperCase()}`);
    } catch {
      toast.error('Copy failed');
    }
  };

  const uploaderInitial = (wallpaper.uploader?.nickname || wallpaper.uploader?.username || '').charAt(0).toUpperCase();
  const heroImg = wallpaper.preview_url || wallpaper.original_url;
  const fileSize = wallpaper.file_size > 0 ? formatFileSize(wallpaper.file_size) : '—';
  const downloadCost = isOwner ? 0 : 1;
  const userBalance = user?.coins ?? 0;
  const insufficient = !isOwner && isAuthenticated && userBalance < downloadCost;

  return (
    <>
      <PageMeta
        title={metaTitle}
        description={metaDescription}
        image={metaImage}
        type="article"
        jsonLd={jsonLd}
      />
      {showAddToCollection && wallpaper && (
        <AddToCollectionModal wallpaperId={wallpaper.id} onClose={() => setShowAddToCollection(false)} />
      )}

      {showReport && wallpaper && (
        <ReportModal wallpaperId={wallpaper.id} onClose={() => setShowReport(false)} />
      )}

      {showGuide && <SetWallpaperGuide onClose={() => setShowGuide(false)} />}

      {mockupVariant && wallpaper && (
        <DeviceMockup
          imageUrl={mockupVariant.url || wallpaper.preview_url || wallpaper.original_url}
          platform={mockupVariant.platform}
          deviceName={`${mockupVariant.brand} ${mockupVariant.device_name}`}
          deviceWidth={mockupVariant.width}
          deviceHeight={mockupVariant.height}
          dominantColor={wallpaper.dominant_color}
          onClose={() => setMockupVariant(null)}
        />
      )}

      {fullscreen && createPortal(
        <div
          className="fixed inset-0 z-[70] bg-black flex items-center justify-center overflow-hidden"
          onClick={() => setFullscreen(false)}
          style={{ touchAction: 'none' }}
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
            onClick={(e) => { e.stopPropagation(); setFullscreen(false); }}
            className="fixed top-4 right-4 z-[80] p-2 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
            aria-label="Close"
          >
            <AiOutlineClose size={24} />
          </button>
          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 px-4 py-2 bg-black/50 text-white text-sm rounded-lg">
            {matchedVariant
              ? <>{matchedVariant.brand} {matchedVariant.device_name} &middot; {matchedVariant.width} &times; {matchedVariant.height}</>
              : <>{wallpaper.width} &times; {wallpaper.height}</>
            }
          </div>
        </div>,
        document.body,
      )}

      {/* Whole detail surface fills the available height (the modal panel
          in modal mode, or the Layout main slot in full-page mode) and
          provides a fixed header at the top + a scrollable 2-col body
          underneath. Body scroll lives on this inner container only —
          the outer page never grows scrollbars. */}
      <div className="bg-paper text-ink h-full flex flex-col min-h-0">
        {/* Editorial header — title, keyboard hints, close ✕. Only rendered
            when this page is being shown as a modal overlay (location has a
            background route stashed in state); on the full-page route the
            Layout topbar already provides chrome and a second header strip
            would be redundant. */}
        {Boolean((location.state as { background?: unknown } | null)?.background) && (
          <div className="px-5 sm:px-6 py-2.5 border-b border-hair flex justify-between items-center bg-paper flex-shrink-0">
            <span className="mono text-[10px] tracking-[0.18em] uppercase text-muted truncate">
              SPECIMEN №{String(wallpaper.id).padStart(3, '0')}
              <span className="ml-2 text-ink-2 hidden sm:inline">· OVERLAY VIEW</span>
            </span>
            <div className="flex items-center gap-3 sm:gap-4 mono text-[10px] tracking-[0.18em] uppercase text-muted">
              <span className="hidden sm:inline-flex items-center gap-1.5">
                <kbd className="inline-flex items-center justify-center min-w-[26px] h-[18px] px-1.5 border border-hair bg-paper-2 text-ink-2 rounded">ESC</kbd>
                <span>CLOSE</span>
              </span>
              <button
                onClick={() => navigate(-1)}
                title="Close"
                className="w-8 h-8 rounded-full border border-hair bg-paper hover:bg-paper-2 text-ink inline-flex items-center justify-center transition-colors"
              >
                <AiOutlineClose size={14} />
              </button>
            </div>
          </div>
        )}
        <div className="flex-1 min-h-0 overflow-y-auto">
          <div className="mx-auto px-5 sm:px-6 lg:px-8 py-5 lg:py-6 grid gap-6 lg:gap-7 lg:grid-cols-[1.4fr_1fr]">
          {/* ── LEFT COLUMN — plate header, image, stats, more-like-this ── */}
          <div className="min-w-0 flex flex-col">
            <div className="flex justify-between items-baseline mb-3 mono text-[10px] tracking-[0.18em] uppercase text-muted">
              <span>Plate №{String(wallpaper.id).padStart(3, '0')}</span>
              <span className="hidden sm:inline">
                {wallpaper.width}×{wallpaper.height}
                {resLabel ? ` · ${resLabel}` : ''}
                {wallpaper.dominant_color ? ` · dominant ${wallpaper.dominant_color.toUpperCase()}` : ''}
              </span>
            </div>

            {/* Image with corner brackets */}
            <div className="relative">
              <div
                className="relative w-full overflow-hidden bg-paper-3 border border-hair"
                style={{
                  aspectRatio: wallpaper.width > 0 && wallpaper.height > 0
                    ? `${wallpaper.width} / ${wallpaper.height}`
                    : undefined,
                  maxHeight: '78vh',
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
                        className={`absolute inset-0 w-full h-full object-contain select-none transition-opacity duration-500 ${frameIdx === i ? 'opacity-100' : 'opacity-0'}`}
                        style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                      />
                    ))}
                    <button
                      onClick={() => setFramePlaying((p) => !p)}
                      className="absolute bottom-3 right-3 px-3 py-1 bg-black/60 text-white text-[11px] mono rounded backdrop-blur-sm"
                    >{framePlaying ? 'PAUSE' : 'PLAY'} · {frameIdx + 1}/{frames.length}</button>
                  </div>
                ) : (
                  heroImg && (
                    <img
                      src={heroImg}
                      alt=""
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      className="w-full h-full object-contain select-none"
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                  )
                )}
              </div>
              <div className="plate-brackets pointer-events-none">
                <span className="br-tl" />
                <span className="br-tr" />
                <span className="br-bl" />
                <span className="br-br" />
              </div>
            </div>

            {/* Stats strip */}
            <div className="mt-3 grid grid-cols-4 border border-hair border-r-0">
              {[
                ['DOWNLOADS', wallpaper.download_count],
                ['LIKES',     wallpaper.like_count],
                ['FAVORITED', wallpaper.favorite_count],
                ['VIEWS',     wallpaper.view_count],
              ].map(([k, v]) => (
                <div key={String(k)} className="px-3 py-2.5 sm:px-3.5 sm:py-3 border-r border-hair">
                  <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted">{k}</div>
                  <div className="display text-[22px] sm:text-[24px] leading-none mt-1">{formatNumber(v as number)}</div>
                </div>
              ))}
            </div>

            {/* Likers / favoriters avatars (kept from the old page — useful social proof) */}
            {engagements && (engagements.likers?.length || engagements.favoriters?.length || engagements.downloaders?.length) ? (
              <div className="mt-5 flex flex-col gap-2 text-[12px] text-ink-2">
                {engagements.likers?.length > 0 && (
                  <div className="flex items-center gap-3"><AvatarStack users={engagements.likers} total={wallpaper.like_count} /> <span className="mono text-[10px] tracking-wider uppercase text-muted">Liked by</span></div>
                )}
                {engagements.favoriters?.length > 0 && (
                  <div className="flex items-center gap-3"><AvatarStack users={engagements.favoriters} total={wallpaper.favorite_count} /> <span className="mono text-[10px] tracking-wider uppercase text-muted">Favorited by</span></div>
                )}
              </div>
            ) : null}

            {/* More like this */}
            {similar.length > 0 && (
              <>
                <div className="label-rule mt-7 mb-3">
                  More like this · {similar.length}
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                  {similar.slice(0, 8).map((s) => (
                    <WallpaperCard key={s.id} wallpaper={s} fixedAspect hideActions />
                  ))}
                </div>
              </>
            )}

            {/* Variants list — kept for users who need the device-specific
                downloads. Hidden behind a disclosure so it doesn't clutter
                the editorial spread. */}
            {variants.length > 0 && (
              <details className="mt-6 border border-hair">
                <summary className="px-4 py-3 mono text-[10px] tracking-[0.14em] uppercase text-ink-2 cursor-pointer hover:bg-paper-2">
                  Device-specific downloads ({variants.length})
                </summary>
                <div className="p-4 border-t border-hair bg-paper-2">
                  <VariantList
                    variants={variants}
                    matchedId={matchedVariant?.id}
                    onMockup={(v) => setMockupVariant(v)}
                    onDownload={(v) => handleDownload(v)}
                  />
                </div>
              </details>
            )}
          </div>

          {/* ── RIGHT COLUMN — metadata + actions + CoinCTA ── */}
          <div className="flex flex-col gap-5 min-w-0">
            {/* Eyebrow */}
            <div className="kicker text-muted">
              {wallpaper.tags?.length > 0 ? wallpaper.tags[0].name.toUpperCase() : 'WALLPAPER'} · ADDED {daysAgo}D AGO{wallpaper.is_dynamic ? ' · DYNAMIC' : ''}
            </div>

            {/* Uploader row */}
            {wallpaper.uploader && (
              <Link
                to={`/user/${wallpaper.uploader.username}`}
                className="flex items-center gap-3 py-3 border-t border-b border-hair no-underline text-ink"
              >
                <div className="w-10 h-10 rounded-full overflow-hidden bg-paper-2 border border-hair flex items-center justify-center display text-[18px] flex-shrink-0">
                  {wallpaper.uploader.avatar_url
                    ? <img src={wallpaper.uploader.avatar_url} alt="" className="w-full h-full object-cover" />
                    : uploaderInitial}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="display text-[19px] leading-tight truncate">
                    @{wallpaper.uploader.username}
                  </div>
                  {wallpaper.uploader.bio && (
                    <div className="mono text-[10px] tracking-[0.08em] uppercase text-muted truncate">
                      {wallpaper.uploader.bio}
                    </div>
                  )}
                </div>
                <span className="mono text-[10px] tracking-[0.1em] uppercase text-muted whitespace-nowrap">VIEW →</span>
              </Link>
            )}

            {/* Palette */}
            {palette.length > 0 && (
              <section>
                <div className="kicker text-muted">Palette · {palette.length} color{palette.length === 1 ? '' : 's'}</div>
                <div className="grid mt-2.5 gap-2" style={{ gridTemplateColumns: `repeat(${palette.length}, 1fr)` }}>
                  {palette.map((c, i) => (
                    <button key={`${c}-${i}`} onClick={() => copyHex(c)} className="flex flex-col gap-0 bg-transparent border-0 p-0 cursor-pointer">
                      <span className="swatch block h-[52px] rounded-[2px]" style={{ background: c }} title={`${c.toUpperCase()} — click to copy`} />
                      <span className="swatch-hex">{c.toUpperCase()}</span>
                    </button>
                  ))}
                </div>
              </section>
            )}

            {/* Specifications */}
            <section>
              <div className="kicker text-muted">Specifications</div>
              <dl className="grid grid-cols-[90px_1fr] gap-y-2.5 mt-2.5 mono text-[13px]">
                <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">DIM</dt>
                <dd className="m-0 text-ink">{wallpaper.width.toLocaleString()} × {wallpaper.height.toLocaleString()} px</dd>
                <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">RES</dt>
                <dd className="m-0 text-ink">{resLabel || '—'}{wallpaper.is_dynamic && <span className="ml-2 text-accent">● Dynamic</span>}</dd>
                <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">FILE</dt>
                <dd className="m-0 text-ink">{(wallpaper.file_type || 'IMAGE').toUpperCase()} · {fileSize}</dd>
                {wallpaper.dominant_color && (
                  <>
                    <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">DOMINANT</dt>
                    <dd className="m-0 text-ink inline-flex items-center gap-1.5">
                      <span className="inline-block w-2.5 h-2.5 border border-hair" style={{ background: wallpaper.dominant_color }} />
                      {wallpaper.dominant_color.toUpperCase()}
                    </dd>
                  </>
                )}
              </dl>
            </section>

            {/* Actions */}
            <section>
              <div className="kicker text-muted">Actions</div>

              <div className="grid grid-cols-3 gap-2 mt-2.5">
                <button
                  onClick={handleLike}
                  disabled={likeLoading}
                  className={`btn-pill ${wallpaper.is_liked ? 'is-liked' : ''}`}
                >
                  {likeLoading
                    ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                    : wallpaper.is_liked ? <AiFillHeart size={15} /> : <AiOutlineHeart size={15} />}
                  <span className="label">{wallpaper.is_liked ? 'Liked' : 'Like'}</span>
                  <span className="count">{formatNumber(wallpaper.like_count)}</span>
                </button>
                <button
                  onClick={handleFavorite}
                  disabled={favLoading}
                  className={`btn-pill ${wallpaper.is_favorited ? 'is-favorited' : ''}`}
                >
                  {favLoading
                    ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                    : wallpaper.is_favorited ? <AiFillStar size={15} /> : <AiOutlineStar size={15} />}
                  <span className="label">{wallpaper.is_favorited ? 'Favorited' : 'Favorite'}</span>
                </button>
                <button
                  onClick={() => { if (!isAuthenticated) { navigate('/login'); return; } setShowAddToCollection(true); }}
                  className="btn-pill"
                >
                  <MdPlaylistAdd size={17} />
                  <span className="label">Add to list</span>
                </button>
              </div>

              <div className="grid grid-cols-2 gap-2 mt-2">
                <button
                  onClick={() => setFullscreen(true)}
                  className="btn-pill btn-pill--action"
                >
                  <span className="lhs">
                    <span className="glyph"><AiOutlineFullscreen size={15} /></span>
                    <span className="text-left">
                      <div className="text-[13px] font-medium leading-tight">Fullscreen preview</div>
                      <div className="mono text-[10px] tracking-[0.08em] uppercase text-muted mt-0.5">Watermarked · free</div>
                    </span>
                  </span>
                  <span className="arrow">→</span>
                </button>
                <button
                  onClick={() => matchedVariant && canMockupMatched && setMockupVariant(matchedVariant)}
                  disabled={!canMockupMatched}
                  className="btn-pill btn-pill--action"
                >
                  <span className="lhs">
                    <span className="glyph"><MdDesktopMac size={15} /></span>
                    <span className="text-left">
                      <div className="text-[13px] font-medium leading-tight">On device</div>
                      <div className="mono text-[10px] tracking-[0.08em] uppercase text-muted mt-0.5">Mockup preview</div>
                    </span>
                  </span>
                  <span className="arrow">→</span>
                </button>
              </div>
            </section>

            {/* Coin CTA — sits directly under the action buttons so the
                Download CTA is in the user's eyeline after they've parsed
                Like / Favorite / Preview etc., not buried at the bottom
                of the column. Confirm/success states from the spec are
                covered by the existing handleDownload toast + dlDone
                flag in V1. */}
            <div className="pt-1">
              {insufficient ? (
                <div className="p-5 border border-[#b07a1a]" style={{ background: 'oklch(96% 0.05 70)' }}>
                  <div className="flex justify-between items-center gap-4 flex-wrap">
                    <div className="min-w-0">
                      <div className="kicker tracking-[0.14em]" style={{ color: '#9a6a18' }}>INSUFFICIENT COINS</div>
                      <div className="display text-[28px] sm:text-[34px] leading-none mt-1.5" style={{ color: '#5e3f08' }}>
                        Need <span style={{ color: '#9a6a18' }}>{downloadCost - userBalance}</span> more
                      </div>
                      <div className="mono text-[10px] tracking-[0.14em] mt-2" style={{ color: '#9a6a18' }}>
                        YOUR BALANCE · {userBalance} COINS · COST · {downloadCost}
                      </div>
                    </div>
                    <Link to="/upload" className="inline-flex items-center gap-2.5 px-5 py-3 rounded-full text-white font-medium text-[13px] no-underline whitespace-nowrap" style={{ background: '#9a6a18' }}>
                      Upload to earn
                    </Link>
                  </div>
                  <hr className="my-3.5 border-0" style={{ borderTop: '1px solid rgba(154,106,24,0.28)' }} />
                  <div className="flex flex-wrap gap-x-5 gap-y-1 text-[12px]" style={{ color: '#5e3f08' }}>
                    <span><strong className="mono mr-1.5" style={{ color: '#9a6a18' }}>+5</strong>each upload</span>
                    <span><strong className="mono mr-1.5" style={{ color: '#9a6a18' }}>+1</strong>others download yours</span>
                  </div>
                </div>
              ) : (
                <div className="bg-ink text-paper border border-ink p-5 flex justify-between items-center gap-4 flex-wrap">
                  <div className="min-w-0">
                    <div className="mono text-[10px] tracking-[0.14em] uppercase" style={{ color: 'rgba(255,255,255,0.55)' }}>
                      {isOwner ? 'YOUR WALLPAPER' : 'EXCHANGE FOR'}
                    </div>
                    <div className="display text-[34px] sm:text-[40px] leading-none mt-1">
                      {isOwner ? 'Free' : (
                        <>{downloadCost} <span className="text-accent">coin{downloadCost > 1 ? 's' : ''}</span></>
                      )}
                    </div>
                    <div className="mono text-[10px] tracking-[0.14em] uppercase mt-1.5" style={{ color: 'rgba(255,255,255,0.55)' }}>
                      {isAuthenticated
                        ? <>YOUR BALANCE · {userBalance} COINS</>
                        : <>SIGN IN TO DOWNLOAD</>}
                    </div>
                  </div>
                  <button
                    onClick={() => handleDownload()}
                    disabled={dlLoading}
                    className="inline-flex items-center gap-2.5 px-5 py-3 rounded-full text-white font-semibold text-[13px] disabled:opacity-60 whitespace-nowrap"
                    style={{ background: 'var(--color-accent)' }}
                  >
                    {dlLoading
                      ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                      : dlDone
                        ? <><AiOutlineCheckCircle size={15} /> Downloaded</>
                        : <><AiOutlineDownload size={15} /> Download original</>}
                  </button>
                </div>
              )}
            </div>

            {/* Owner / report actions */}
            <div className="flex justify-between items-center pt-3 text-[12px] text-muted">
              {isOwner ? (
                <button onClick={handleDelete} className="inline-flex items-center gap-1.5 hover:text-rose-500 transition-colors">
                  <AiOutlineDelete size={14} /> Delete wallpaper
                </button>
              ) : isAuthenticated ? (
                <button onClick={() => setShowReport(true)} className="inline-flex items-center gap-1.5 hover:text-ink transition-colors">
                  <AiOutlineFlag size={14} /> Report
                </button>
              ) : <span />}
              <span className="mono text-[10px] tracking-[0.14em] uppercase">
                №{String(wallpaper.id).padStart(3, '0')}
              </span>
            </div>
          </div>
          </div>
        </div>
      </div>
    </>
  );
}
