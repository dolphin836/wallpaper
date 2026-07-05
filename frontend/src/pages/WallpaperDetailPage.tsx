import { useState, useEffect, useMemo, useCallback, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import InAppConfirm from '../components/InAppConfirm';
import {
  AiOutlineLeft,
  AiOutlineInfoCircle,
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
  AiOutlineZoomIn,
  AiOutlineZoomOut,
  AiOutlineRedo,
  AiOutlineReload,
} from 'react-icons/ai';
import { MdPlaylistAdd, MdDesktopMac, MdLaptopMac, MdTabletMac, MdPhoneIphone, MdOutlineRemoveRedEye, MdDevices } from 'react-icons/md';
import toast from 'react-hot-toast';
import { useTranslation, Trans } from 'react-i18next';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User } from '../types';
import DeviceMockup, {
  canShowMockup,
  PhoneFrame, TabletFrame, LaptopFrame, DesktopFrame,
} from '../components/DeviceMockup';
import ReportModal from '../components/ReportModal';
import WallpaperGrid from '../components/WallpaperGrid';
import { useQuery } from '@tanstack/react-query';
import { getSimilarWallpapers } from '../api';
import { useCategories } from '../hooks/useCategories';
import {
  getWallpaper,
  likeWallpaper,
  unlikeWallpaper,
  favoriteWallpaper,
  unfavoriteWallpaper,
  deleteWallpaper,
  downloadWallpaper,
  getMyCoins,
  getWallpaperVariants,
  getWallpaperEngagements,
} from '../api';
import { useAuthStore } from '../store/auth';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';
import ErrorState from '../components/ErrorState';
import AvatarStack from '../components/AvatarStack';
import AddToCollectionModal from '../components/AddToCollectionModal';

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

// Pick the variant whose pixel dimensions best match this screen.
// Two guards keep the match honest:
//   1. Same orientation only — never a landscape variant for a portrait screen, or vice versa.
//   2. Within 5% of the larger screen dimension on L1 distance — handles slight reporting
//      variance across iOS versions / display modes, while still rejecting wrong devices.
// URL availability is a separate concern (the file may or may not have been uploaded yet);
// matching is purely about dimensions.
function ToolbarBtn({
  onClick, label, children,
}: { onClick: () => void; label: string; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className="w-9 h-9 flex items-center justify-center rounded-full text-white/90 hover:text-white hover:bg-white/10 transition-colors"
    >
      {children}
    </button>
  );
}

// Stream a fetch Response into a Blob while reporting percent complete.
// Falls back to indeterminate (null) when the server doesn't send a usable
// Content-Length or streaming isn't available. Caps at 99% mid-stream so the
// caller owns the jump to 100 once the blob is assembled.
async function fetchBlobWithProgress(
  resp: Response,
  onProgress: (pct: number | null) => void,
): Promise<Blob> {
  const total = Number(resp.headers.get('Content-Length')) || 0;
  if (!resp.body || total <= 0) {
    onProgress(null);
    return resp.blob();
  }
  const reader = resp.body.getReader();
  const chunks: BlobPart[] = [];
  let received = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value) {
      chunks.push(value as BlobPart);
      received += value.length;
      onProgress(Math.min(99, Math.round((received / total) * 100)));
    }
  }
  return new Blob(chunks);
}

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

export default function WallpaperDetailPage() {
  const { t } = useTranslation('detail');
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
  const metaTitle = wallpaper ? t('meta.title', { res: `${wallpaper.width}×${wallpaper.height}` }) : t('meta.titleFallback');
  const metaDescription = wallpaper
    ? t(wallpaper.is_dynamic ? 'meta.descriptionDynamic' : 'meta.description', { res: `${wallpaper.width}×${wallpaper.height}` })
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
  const [error, setError] = useState(false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favLoading, setFavLoading] = useState(false);
  const [fullscreen, setFullscreen] = useState(false);
  // Fullscreen viewer transform state: scale (0.5–5), rotation in degrees
  // (always a multiple of 90 here so the image doesn't end up tilted), and
  // a translation offset for panning when zoomed in. Reset on each open
  // via the useEffect below so the next time the user enters fullscreen
  // they start at 1×, 0°, centered.
  const [fsScale, setFsScale] = useState(1);
  const [fsRotation, setFsRotation] = useState(0);
  const [fsPan, setFsPan] = useState({ x: 0, y: 0 });
  const fsDrag = useRef<{ down: boolean; sx: number; sy: number; px: number; py: number; moved: boolean }>({
    down: false, sx: 0, sy: 0, px: 0, py: 0, moved: false,
  });
  useEffect(() => {
    if (!fullscreen) return;
    setFsScale(1);
    setFsRotation(0);
    setFsPan({ x: 0, y: 0 });
  }, [fullscreen]);
  const [mockupVariant, setMockupVariant] = useState<WallpaperVariant | null>(null);
  const [showAddToCollection, setShowAddToCollection] = useState(false);
  const [showReport, setShowReport] = useState(false);
  // Action-bar overlays. Drawer holds the grouped device list
  // (opened from the action bar's Devices · N button); previewOverlay
  // toggles between the bare wallpaper and the Home / Lock chrome
  // painted directly onto the hero image (clock / dock / menu bar —
  // same overlays the discover floating wall uses).
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [infoOpen, setInfoOpen] = useState(false);
  // Recommendation count — always two complete rows of the rec grid.
  // WallpaperGrid sizeMode="md" uses 2/3/4/5 cols at Tailwind's
  // default/sm/md/lg breakpoints, so two rows = 4/6/8/10 cards. We
  // recompute on window resize so the second row never trails an
  // empty cell when the viewport widens.
  const [recCount, setRecCount] = useState(10);
  useEffect(() => {
    const update = () => {
      const w = window.innerWidth;
      const cols = w >= 1024 ? 5 : w >= 768 ? 4 : w >= 640 ? 3 : 2;
      setRecCount(cols * 2);
    };
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, []);
  // 'off' = naked wallpaper, no chrome. plain/home/lock = wallpaper
  // rendered inside the matched-device frame with the corresponding
  // scene (clean / home or desktop / lock).
  const [previewOverlay, setPreviewOverlay] = useState<'off' | 'plain' | 'home' | 'lock'>('off');
  // Categories map wallpaper.category_id (a number) to a display name.
  // Served from the shared TanStack Query cache, so opening detail modals
  // back-to-back doesn't refetch the list per mount.
  const { categories } = useCategories();
  const currentCategory = useMemo(() => {
    if (!wallpaper?.category_id) return undefined;
    return categories.find((c) => c.id === wallpaper.category_id);
  }, [categories, wallpaper?.category_id]);
  const [dlLoading, setDlLoading] = useState(false);
  const [dlDone, setDlDone] = useState(false);
  // null while the server prepares the file (no measurable progress yet),
  // 0-100 once the download stream is reporting bytes.
  const [dlProgress, setDlProgress] = useState<number | null>(null);
  // Bumped each time a download succeeds so a one-shot phosphor signal line
  // sweeps the bottom of the viewport (rendered via createPortal below). The
  // key={tradeFlashTick} forces a fresh DOM node so the CSS animation re-runs.
  const [tradeFlashTick, setTradeFlashTick] = useState(0);
  // Coin CTA state machine: default → confirm → success / insufficient.
  // Insufficient coins is only entered after the server rejects the trade,
  // so a stale local balance cannot block a valid download.
  const [ctaMode, setCtaMode] = useState<'default' | 'confirm' | 'success' | 'insufficient'>('default');
  const [confirmDontAsk, setConfirmDontAsk] = useState(false);
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

  // Variants partitioned by platform, with the matched device pinned to
  // the top of its own group and the rest sorted by total pixels desc.
  // Backend now returns the four canonical platforms (desktop / laptop /
  // tablet / phone) so an unknown value falls through to "other".
  const groupedVariants = useMemo(() => {
    const buckets: Record<string, WallpaperVariant[]> = {
      desktop: [], laptop: [], tablet: [], phone: [], other: [],
    };
    for (const v of variants) {
      const key = buckets[v.platform] !== undefined ? v.platform : 'other';
      buckets[key].push(v);
    }
    for (const list of Object.values(buckets)) {
      list.sort((a, b) => {
        if (matchedVariant) {
          if (a.id === matchedVariant.id) return -1;
          if (b.id === matchedVariant.id) return 1;
        }
        return (b.width * b.height) - (a.width * a.height);
      });
    }
    return buckets;
  }, [variants, matchedVariant]);

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
      .catch((e) => {
        if (!initialWallpaper && e?.response?.status !== 404) setError(true);
      })
      .finally(() => setLoading(false));
    // initialWallpaper is read once from navigation state; intentionally not a dep.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => {
    if (!fullscreen && !mockupVariant && !drawerOpen && previewOverlay === 'off') return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (previewOverlay !== 'off') { setPreviewOverlay('off'); return; }
        if (drawerOpen) { setDrawerOpen(false); return; }
        setFullscreen(false);
        setMockupVariant(null);
      }
    };
    document.addEventListener('keydown', handleEsc);
    if (fullscreen || mockupVariant) document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', handleEsc);
      document.body.style.overflow = '';
    };
  }, [fullscreen, mockupVariant, drawerOpen, previewOverlay]);

  const { data: similar = [] } = useQuery({
    queryKey: ['wallpaper', wallpaper?.id, 'similar'],
    queryFn: async (): Promise<Wallpaper[]> =>
      (await getSimilarWallpapers(wallpaper!.id, 12)).data.data ?? [],
    enabled: !!wallpaper?.id,
    staleTime: 5 * 60 * 1000,
  });

  // Reset the download CTA back to its default whenever the user navigates
  // to a different wallpaper, so a stale "Downloaded" success state doesn't
  // bleed across detail pages. Must live above the `if (!wallpaper) return`
  // guard below — React's rules-of-hooks forbid a hook call from being
  // skipped on any render (Error #310 if it is).
  useEffect(() => {
    setCtaMode('default');
    setConfirmDontAsk(false);
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
      toast.error(t('toast.actionFailed'));
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
      toast.error(t('toast.actionFailed'));
    } finally {
      setFavLoading(false);
    }
  };

  // Downloads always deliver the original upload (2026-07-05 decision:
  // device variants are retired). The devices drawer keeps its preview
  // and per-device browse actions; its "Get" simply downloads the same
  // original file.
  const handleDownload = async () => {
    if (dlLoading) return;
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper) return;
    const isOwnerDl = user?.id === wallpaper.user_id;
    setDlLoading(true);
    setDlProgress(null);
    try {
      const url = downloadWallpaper(wallpaper.id);
      const resp = await fetch(url, {
        headers: { Authorization: `Bearer ${useAuthStore.getState().token}` },
      });
      if (resp.status === 402) {
        setCtaMode('insufficient');
        toast.error(t('toast.insufficientCoins'));
        return;
      }
      if (!resp.ok) {
        toast.error(t('toast.downloadFailed'));
        return;
      }
      const finalUrl = resp.url;
      const blob = await fetchBlobWithProgress(resp, setDlProgress);
      const blobUrl = URL.createObjectURL(blob);
      const ext = finalUrl.split('.').pop()?.split('?')[0] || 'jpg';
      const filename = `wallpaper_${wallpaper.id}_${wallpaper.width}x${wallpaper.height}.${ext}`;
      setDlProgress(100);
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
      setWallpaper({ ...wallpaper, download_count: wallpaper.download_count + 1 });
      setDlDone(true);
      setTradeFlashTick((n) => n + 1);
      if (!isOwnerDl && user) {
        try {
          const coinsResp = await getMyCoins();
          updateCoins(coinsResp.data.data.coins);
        } catch {
          updateCoins(Math.max(user.coins - downloadCost, 0));
        }
      }
      // Promote the CTA to the success state. Replaces the old SetWallpaperGuide
      // popup — the "now what?" message ("Show in Downloads", "Browse more",
      // macOS app cross-promo) is rendered inline in the right column instead
      // of as a separate modal that would compete with the open detail panel.
      setCtaMode('success');
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 402) {
        setCtaMode('insufficient');
        toast.error(t('toast.insufficientCoins'));
      } else {
        toast.error(t('toast.downloadFailed'));
      }
    } finally {
      setDlLoading(false);
      setDlProgress(null);
    }
  };

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const handleDelete = () => {
    if (!wallpaper) return;
    setShowDeleteConfirm(true);
  };
  const doDelete = async () => {
    if (!wallpaper) return;
    setShowDeleteConfirm(false);
    try {
      await deleteWallpaper(wallpaper.id);
      toast.success(t('toast.deleted'));
      navigate('/');
    } catch {
      toast.error(t('toast.deleteFailed'));
    }
  };

  if (loading) return <Spinner />;
  if (!wallpaper && error) return <ErrorState />;
  if (!wallpaper) return <EmptyState message={t('notFound')} />;

  const isOwner = user?.id === wallpaper.user_id;


  // ─── Helpers derived from wallpaper for the editorial spread ─────────
  const palette = (wallpaper.color_palette || '').split(',').map((s) => s.trim()).filter(Boolean);
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
      toast.success(t('toast.copiedHex', { hex: hex.toUpperCase() }));
    } catch {
      toast.error(t('toast.copyFailed'));
    }
  };

  const uploaderInitial = (wallpaper.uploader?.nickname || wallpaper.uploader?.username || '').charAt(0).toUpperCase();
  const heroImg = wallpaper.preview_url || wallpaper.original_url;
  const fileSize = wallpaper.file_size > 0 ? formatFileSize(wallpaper.file_size) : '—';
  const downloadCost = isOwner ? 0 : 1;
  const userBalance = user?.coins ?? 0;
  const isMacUA = /Macintosh|Mac OS X/i.test(navigator.userAgent);

  const ctaState = ctaMode;

  const handleDownloadClick = () => {
    if (!isAuthenticated) { navigate('/login'); return; }
    if (isOwner) { handleDownload(); return; }
    // Skip-confirm flag respected per-session (set inside the confirm UI).
    if (sessionStorage.getItem('wpe_skip_dl_confirm') === '1') {
      handleDownload();
      return;
    }
    setCtaMode('confirm');
  };
  const handleConfirmYes = () => {
    if (confirmDontAsk) {
      sessionStorage.setItem('wpe_skip_dl_confirm', '1');
    }
    handleDownload();
  };
  const handleConfirmCancel = () => {
    setCtaMode('default');
    setConfirmDontAsk(false);
  };
  const handleSuccessDismiss = () => {
    setCtaMode('default');
  };

  // The visitor's platform drives which Home/Lock overlay chrome we
  // paint over the wallpaper (laptop/desktop = menubar+dock+clock,
  // phone = notch+clock, tablet = clock). Falls back to desktop.
  const overlayPlatform: 'desktop' | 'laptop' | 'tablet' | 'phone' =
    matchedVariant?.platform === 'phone' ? 'phone'
    : matchedVariant?.platform === 'tablet' ? 'tablet'
    : matchedVariant?.platform === 'laptop' ? 'laptop'
    : 'desktop';

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

      <InAppConfirm
        open={showDeleteConfirm}
        title={t('delete.title')}
        message={t('delete.message')}
        confirmLabel={t('delete.confirm')}
        destructive
        onConfirm={doDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      {tradeFlashTick > 0 && createPortal(
        <div key={tradeFlashTick} className="trade-flash" aria-hidden />,
        document.body,
      )}

      {/* Download progress is rendered below the preview, matching the
          macOS detail page. */}

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
          onClick={() => {
            if (fsDrag.current.moved) {
              fsDrag.current.moved = false;
              return;
            }
            setFullscreen(false);
          }}
          onWheel={(e) => {
            const next = e.deltaY < 0 ? fsScale * 1.15 : fsScale / 1.15;
            setFsScale(Math.max(0.5, Math.min(5, next)));
          }}
          onMouseDown={(e) => {
            if (fsScale <= 1) return;
            fsDrag.current = {
              down: true, sx: e.clientX, sy: e.clientY,
              px: fsPan.x, py: fsPan.y, moved: false,
            };
          }}
          onMouseMove={(e) => {
            if (!fsDrag.current.down) return;
            const dx = e.clientX - fsDrag.current.sx;
            const dy = e.clientY - fsDrag.current.sy;
            if (Math.abs(dx) + Math.abs(dy) > 4) fsDrag.current.moved = true;
            setFsPan({ x: fsDrag.current.px + dx, y: fsDrag.current.py + dy });
          }}
          onMouseUp={() => { fsDrag.current.down = false; }}
          onMouseLeave={() => { fsDrag.current.down = false; }}
          style={{ touchAction: 'none', cursor: fsScale > 1 ? (fsDrag.current.down ? 'grabbing' : 'grab') : 'default' }}
        >
          <img
            src={matchedVariant?.url || wallpaper.preview_url || wallpaper.original_url}
            alt=""
            loading="eager"
            decoding="async"
            fetchPriority="high"
            onContextMenu={(e) => e.preventDefault()}
            draggable={false}
            className="max-w-full max-h-full object-contain select-none"
            style={{
              WebkitUserDrag: 'none',
              transform: `translate(${fsPan.x}px, ${fsPan.y}px) scale(${fsScale}) rotate(${fsRotation}deg)`,
              transition: fsDrag.current.down ? 'none' : 'transform 120ms ease-out',
              willChange: 'transform',
            } as React.CSSProperties}
          />
          <button
            onClick={(e) => { e.stopPropagation(); setFullscreen(false); }}
            className="fixed top-4 right-4 z-[80] p-2 bg-black/50 text-white rounded-full hover:bg-black/70 transition-colors"
            aria-label={t('fullscreen.close')}
          >
            <AiOutlineClose size={24} />
          </button>
          <div className="absolute bottom-20 left-1/2 -translate-x-1/2 px-4 py-2 bg-black/50 text-white text-sm rounded-lg pointer-events-none">
            {matchedVariant
              ? <>{matchedVariant.brand} {matchedVariant.device_name} &middot; {matchedVariant.width} &times; {matchedVariant.height}</>
              : <>{wallpaper.width} &times; {wallpaper.height}</>
            }
            <span className="ml-3 mono text-[11px] opacity-70">{Math.round(fsScale * 100)}%</span>
          </div>
          <div
            className="absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-1 px-2 py-1.5 bg-black/60 backdrop-blur-sm rounded-full"
            onClick={(e) => e.stopPropagation()}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <ToolbarBtn label={t('fullscreen.zoomOut')} onClick={() => setFsScale((s) => Math.max(0.5, s / 1.25))}>
              <AiOutlineZoomOut size={18} />
            </ToolbarBtn>
            <ToolbarBtn label={t('fullscreen.zoomIn')} onClick={() => setFsScale((s) => Math.min(5, s * 1.25))}>
              <AiOutlineZoomIn size={18} />
            </ToolbarBtn>
            <span className="w-px h-5 bg-white/20 mx-1" aria-hidden />
            <ToolbarBtn label={t('fullscreen.rotate')} onClick={() => setFsRotation((r) => (r + 90) % 360)}>
              <AiOutlineRedo size={18} />
            </ToolbarBtn>
            <span className="w-px h-5 bg-white/20 mx-1" aria-hidden />
            <ToolbarBtn label={t('fullscreen.reset')} onClick={() => { setFsScale(1); setFsRotation(0); setFsPan({ x: 0, y: 0 }); }}>
              <AiOutlineReload size={18} />
            </ToolbarBtn>
          </div>
        </div>,
        document.body,
      )}

      {/* Devices drawer — right-side slide-in. Opens from the action-bar
          "Devices · N ▾" button. Grouped per platform with per-row
          Preview + Get. */}
      {drawerOpen && createPortal(
        <div className="wd-drawer-scrim" onClick={() => setDrawerOpen(false)}>
          <div className="wd-drawer" onClick={(e) => e.stopPropagation()}>
            <div className="wd-drawer-head">
              <div>
                <div className="kicker text-muted">{t('drawer.kicker', { n: variants.length })}</div>
                <h3 className="display text-[20px] leading-tight mt-1">{t('drawer.title')}</h3>
              </div>
              <button onClick={() => setDrawerOpen(false)} className="p-1.5 rounded-full hover:bg-paper-2" aria-label={t('drawer.close')}>
                <AiOutlineClose size={18} />
              </button>
            </div>
            <div className="wd-drawer-body">
              {(['desktop', 'laptop', 'tablet', 'phone', 'other'] as const).map((platform) => {
                const list = groupedVariants[platform];
                if (!list || list.length === 0) return null;
                const label = t(`drawer.platform.${platform}`);
                return (
                  <div key={platform} className="wd-drawer-group">
                    <div className="wd-drawer-grouphead">
                      <span>{label}</span>
                      <span className="mono text-[10px] tracking-[0.14em] text-muted normal-case">{list.length}</span>
                    </div>
                    {list.map((v) => {
                      const isMatched = matchedVariant?.id === v.id;
                      const mockable = canShowMockup(v);
                      const deviceName = [v.brand, v.device_name].filter(Boolean).join(' ').trim() || t('drawer.device');
                      const Icon =
                        v.platform === 'phone' ? MdPhoneIphone
                        : v.platform === 'tablet' ? MdTabletMac
                        : v.platform === 'laptop' ? MdLaptopMac
                        : MdDesktopMac;
                      return (
                        <div key={v.id} className={`wd-drawer-row ${isMatched ? 'is-matched' : ''}`}>
                          <div className="wd-drawer-row-head">
                            <Icon size={20} className="text-ink-2 flex-shrink-0" />
                            <div className="min-w-0 flex-1">
                              <div className="flex items-center gap-1.5 flex-wrap">
                                <span className="text-[14px] font-medium text-ink truncate">{deviceName}</span>
                                {isMatched && (
                                  <span className="mono text-[9px] tracking-[0.14em] px-1.5 py-[1px] bg-ink text-paper rounded">{t('drawer.yourDevice')}</span>
                                )}
                              </div>
                              <div className="mono text-[10px] text-muted mt-0.5">
                                {v.width.toLocaleString()} × {v.height.toLocaleString()}
                                {v.file_size > 0 && <> · {formatFileSize(v.file_size)}</>}
                              </div>
                            </div>
                          </div>
                          {/* 3-button row — preview chassis, browse all
                              wallpapers tailored for this device, get
                              the variant download. Matched device's Get
                              switches to accent so it pops. */}
                          <div className="wd-drawer-row-actions">
                            <button
                              onClick={() => mockable && setMockupVariant(v)}
                              disabled={!mockable}
                              title={mockable ? t('drawer.previewTitle') : t('drawer.noMockup')}
                              className="wd-drawer-action"
                            >
                              <MdOutlineRemoveRedEye size={14} /> {t('drawer.preview')}
                            </button>
                            {v.device_slug ? (
                              <Link
                                to={`/wallpapers-for/${v.device_slug}`}
                                className="wd-drawer-action no-underline"
                                title={t('drawer.browseTitle', { device: deviceName })}
                              >
                                <MdDevices size={14} /> {t('drawer.browse')}
                              </Link>
                            ) : (
                              <span className="wd-drawer-action is-disabled" title={t('drawer.noDevicePage')}>
                                <MdDevices size={14} /> {t('drawer.browse')}
                              </span>
                            )}
                            <button
                              onClick={() => handleDownload()}
                              disabled={dlLoading}
                              title={t('drawer.getTitle')}
                              className={`wd-drawer-action wd-drawer-action-cta ${isMatched ? 'is-matched' : ''}`}
                            >
                              <AiOutlineDownload size={14} /> {t('drawer.get')}
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                );
              })}
            </div>
            <div className="wd-drawer-foot mono text-[10px] tracking-[0.14em] uppercase text-muted">
              {t('drawer.footClose')}{isOwner ? '' : ` · ${t('drawer.footCost', { count: downloadCost || 1 })}`}
            </div>
          </div>
        </div>,
        document.body,
      )}

      <div className="bg-paper text-ink h-full flex flex-col min-h-0 relative wd-root">
        {/* Outer backdrop — blurred preview of the wallpaper itself, full
            bleed behind everything. Combined with a soft scrim above so
            the content stays legible regardless of source brightness. */}
        {heroImg && (
          <div className="wd-backdrop" aria-hidden>
            <img src={heroImg} alt="" decoding="async" />
          </div>
        )}
        <div className="wd-backdrop-scrim" aria-hidden />

        {/* Modal-mode chrome moved to the modal wrapper itself
            (corner-anchored ✕). No header strip here. */}

        <div className="flex-1 min-h-0 overflow-y-auto relative z-10">

          {/* ═══ SCREEN 1 — immersive hero (mirrors the Mac detail page):
              full-bleed wallpaper, back circle top-left, info circle +
              panel top-right, glass toolbar bottom-centre. ═══ */}
          <section className="wd-s1">
            <div className="wd-s1-media" style={{ backgroundColor: wallpaper.dominant_color || undefined }}>
              {frames.length > 1 ? (
                <>
                  {frames.map((url, i) => (
                    <img
                      key={i}
                      src={url}
                      alt=""
                      loading={i === 0 ? 'eager' : 'lazy'}
                      decoding="async"
                      fetchPriority={i === 0 ? 'high' : 'auto'}
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      className={`absolute inset-0 w-full h-full object-cover select-none transition-opacity duration-500 ${frameIdx === i ? 'opacity-100' : 'opacity-0'}`}
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                  ))}
                  <button
                    onClick={(e) => { e.stopPropagation(); setFramePlaying((p) => !p); }}
                    className="absolute top-6 right-24 z-[3] px-3 py-1 bg-black/60 text-white text-[11px] mono rounded-full backdrop-blur-sm"
                  >{framePlaying ? t('hero.pause') : t('hero.play')} · {frameIdx + 1}/{frames.length}</button>
                </>
              ) : (wallpaper.file_type || '').startsWith('video/') && wallpaper.original_url ? (
                <div className="wd-s1-center">
                  <div className="wd-hero-canvas" style={{ aspectRatio: wallpaper.width > 0 && wallpaper.height > 0 ? `${wallpaper.width} / ${wallpaper.height}` : '16 / 9', backgroundColor: wallpaper.dominant_color || undefined }}>
                    <VideoPlayer
                      src={wallpaper.preview_video_url || wallpaper.original_url}
                      poster={wallpaper.preview_url || wallpaper.thumb_url}
                    />
                  </div>
                </div>
              ) : heroImg ? (
                previewOverlay !== 'off' ? (
                  <InlineDeviceMockup
                    imageUrl={heroImg}
                    platform={overlayPlatform}
                    mode={previewOverlay}
                    matched={matchedVariant}
                  />
                ) : (
                  <img
                    src={heroImg}
                    alt=""
                    loading="eager"
                    decoding="async"
                    fetchPriority="high"
                    onContextMenu={(e) => e.preventDefault()}
                    draggable={false}
                    onClick={() => setFullscreen(true)}
                    className="wd-s1-img"
                    style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                  />
                )
              ) : null}
            </div>
            <div className="wd-s1-vignette" aria-hidden />

            {/* Back — top-left floating glass circle. */}
            <button
              type="button"
              className="wd-circle-btn glass-bounce wd-s1-back"
              onClick={() => { if (window.history.length > 1) navigate(-1); else navigate('/'); }}
              aria-label={t('cta.cancel')}
            >
              <AiOutlineLeft size={17} />
            </button>

            {/* Info — top-right floating circle; hover/click opens the
                metadata panel (uploader / about / palette / stats). */}
            <div
              className="wd-s1-info"
              onMouseEnter={() => setInfoOpen(true)}
              onMouseLeave={() => setInfoOpen(false)}
            >
              <button
                type="button"
                className={`wd-circle-btn is-prominent glass-bounce ${infoOpen ? 'is-active' : ''}`}
                onClick={() => setInfoOpen((v) => !v)}
                aria-label="info"
              >
                <AiOutlineInfoCircle size={18} />
              </button>
              {infoOpen && (
                <div className="wd-info-panel">
                  {wallpaper.uploader && (
                    <Link to={`/user/${wallpaper.uploader.username}`} className="wd-ip-row no-underline">
                      <div className="wd-ip-avatar">
                        {wallpaper.uploader.avatar_url
                          ? <img src={wallpaper.uploader.avatar_url} alt="" />
                          : <span className="display">{uploaderInitial}</span>}
                      </div>
                      <div className="min-w-0">
                        <div className="text-[13px] font-medium text-white truncate">@{wallpaper.uploader.username}</div>
                        <div className="mono text-[9px] tracking-[0.14em] uppercase text-white/55">{t('info.viewProfile')} →</div>
                      </div>
                    </Link>
                  )}

                  <div className="wd-ip-block">
                    <div className="wd-ip-kicker">{t('info.about')}</div>
                    {currentCategory ? (
                      <Link to={`/category/${currentCategory.slug}`} className="display text-[18px] text-white no-underline hover:underline">
                        {currentCategory.name}
                      </Link>
                    ) : (
                      <span className="display text-[16px] text-white/55 italic">{t('info.uncategorised')}</span>
                    )}
                    {wallpaper.tags && wallpaper.tags.length > 0 && (
                      <div className="mt-2 flex flex-wrap gap-1.5">
                        {wallpaper.tags.map((tag) => (
                          <span key={tag.id} className="wd-ip-tag">{tag.name}</span>
                        ))}
                      </div>
                    )}
                  </div>

                  {palette.length > 0 && (
                    <div className="wd-ip-block">
                      <div className="wd-ip-kicker">{t('info.paletteKicker')}</div>
                      <div className="flex gap-1.5">
                        {palette.slice(0, 6).map((c, i) => (
                          <button
                            key={`${c}-${i}`}
                            onClick={() => copyHex(c)}
                            className="wd-ip-swatch"
                            style={{ background: c }}
                            title={t('info.copyTitle', { hex: c.toUpperCase() })}
                          />
                        ))}
                      </div>
                    </div>
                  )}

                  <div className="wd-ip-stats">
                    {([
                      [t('stats.downloads'), wallpaper.download_count, engagements?.downloaders ?? []],
                      [t('stats.likes'),     wallpaper.like_count,     engagements?.likers      ?? []],
                      [t('stats.favorited'), wallpaper.favorite_count, engagements?.favoriters  ?? []],
                      [t('stats.views'),     wallpaper.view_count,     []                            ],
                    ] as const).map(([k, v, users]) => (
                      <div key={k}>
                        <div className="wd-ip-kicker">{k}</div>
                        <div className="display text-[18px] leading-none mt-0.5 text-white">{formatNumber(v)}</div>
                        {users.length > 0 && <AvatarStack users={users.slice(0, 5)} total={v} size={16} />}
                      </div>
                    ))}
                  </div>

                  <div className="wd-ip-foot">
                    {isOwner ? (
                      <button onClick={handleDelete} className="inline-flex items-center gap-1.5 text-white/65 hover:text-rose-300 transition-colors">
                        <AiOutlineDelete size={13} /> {t('actions.deleteWallpaper')}
                      </button>
                    ) : isAuthenticated ? (
                      <button onClick={() => setShowReport(true)} className="inline-flex items-center gap-1.5 text-white/65 hover:text-white transition-colors">
                        <AiOutlineFlag size={13} /> {t('actions.report')}
                      </button>
                    ) : <span />}
                    <span className="mono text-[9px] tracking-[0.14em] uppercase text-white/45">
                      №{String(wallpaper.id).padStart(3, '0')}
                    </span>
                  </div>
                </div>
              )}
            </div>

            {/* Bottom-centre column: progress / notices / glass toolbar. */}
            <div className="wd-s1-bottom">
              {dlLoading && <DownloadProgressBar progress={dlProgress} />}

              {ctaState === 'success' ? (
                <div className="wd-notice is-success">
                  <div className="flex justify-between items-center gap-4 flex-wrap">
                    <div className="min-w-0">
                      <div className="wd-notice-kicker inline-flex items-center gap-1.5">
                        <AiOutlineCheckCircle size={11} /> {t('cta.downloadedKicker')}
                      </div>
                      <div className="wd-notice-title">
                        wallpaper_<span className="mono text-[20px] sm:text-[24px]">{String(wallpaper.id).padStart(3, '0')}</span>.jpg
                      </div>
                      <div className="wd-notice-meta">
                        {fileSize}  ·  {t('cta.coinsRemaining', { n: userBalance })}
                      </div>
                    </div>
                    <div className="flex flex-col gap-2 flex-shrink-0">
                      <button
                        onClick={handleSuccessDismiss}
                        className="inline-flex items-center justify-center gap-2 px-5 py-2.5 rounded-full bg-ink text-paper font-medium text-[12px] whitespace-nowrap hover:bg-ink-2 transition-colors"
                      >{t('cta.done')}</button>
                      <Link
                        to="/"
                        className="inline-flex items-center justify-center gap-2 px-5 py-2 rounded-full border border-hair text-ink text-[12px] no-underline whitespace-nowrap hover:bg-paper-2 transition-colors"
                      >{t('cta.browseMore')}</Link>
                    </div>
                  </div>
                  {!isMacUA && (
                    <>
                      <hr className="wd-notice-rule" />
                      <div className="wd-notice-foot">
                        <span>{t('cta.macPromo')}</span>
                        <Link to="/download/mac" className="underline">{t('cta.getIt')}</Link>
                      </div>
                    </>
                  )}
                </div>
              ) : ctaState === 'insufficient' ? (
                <div className="wd-notice is-warning">
                  <div className="flex justify-between items-center gap-4 flex-wrap">
                    <div className="min-w-0">
                      <div className="wd-notice-kicker">{t('cta.insufficientKicker')}</div>
                      <div className="wd-notice-title is-large">
                        <Trans i18nKey="cta.needMore" ns="detail" values={{ need: downloadCost - userBalance }} components={[<span key="0" />]} />
                      </div>
                      <div className="wd-notice-meta">
                        {t('cta.balanceLine', { balance: userBalance, cost: downloadCost })}
                      </div>
                    </div>
                    <Link to="/upload" className="wd-notice-primary">
                      {t('cta.uploadToEarn')}
                    </Link>
                  </div>
                  <hr className="wd-notice-rule" />
                  <div className="wd-notice-foot gap-x-5">
                    <span><Trans i18nKey="cta.earnUpload" ns="detail" components={[<strong className="mono mr-1.5" key="0" />]} /></span>
                    <span><Trans i18nKey="cta.earnDownload" ns="detail" components={[<strong className="mono mr-1.5" key="0" />]} /></span>
                  </div>
                </div>
              ) : ctaState === 'confirm' ? (
                <div className="wd-notice is-confirm">
                  <div className="flex justify-between items-center gap-4 flex-wrap">
                    <div className="min-w-0">
                      <div className="wd-notice-kicker">{t('cta.confirmKicker')}</div>
                      <div className="wd-notice-title is-xl">
                        −{downloadCost} <span className="text-accent">{t('cta.coinWord', { count: downloadCost })}</span>
                      </div>
                      <div className="wd-notice-meta">
                        <Trans
                          i18nKey="cta.confirmBalance"
                          ns="detail"
                          values={{ from: userBalance, to: userBalance - downloadCost }}
                          components={[<span className="text-accent" key="0" />]}
                        />
                      </div>
                      <Link
                        to="/upload"
                        className="wd-notice-refill"
                      >
                        {t('cta.refill')} <span aria-hidden>→</span>
                      </Link>
                    </div>
                    <div className="flex flex-col gap-2 flex-shrink-0">
                      <button
                        onClick={handleConfirmYes}
                        disabled={dlLoading}
                        className="wd-notice-primary"
                      >
                        {dlLoading ? <AiOutlineLoading3Quarters size={14} className="animate-spin" /> : (
                          <>
                            <span className="w-2.5 h-2.5 rounded-full bg-white shadow-[inset_0_-2px_0_oklch(80%_0.18_60),inset_0_1px_0_oklch(98%_0.04_60)]" aria-hidden />
                            {t('cta.yesTrade')}
                          </>
                        )}
                      </button>
                      <button
                        onClick={handleConfirmCancel}
                        disabled={dlLoading}
                        className="wd-notice-secondary"
                      >{t('cta.cancel')}</button>
                    </div>
                  </div>
                  <hr className="wd-notice-rule" />
                  <label className="wd-notice-check">
                    <input
                      type="checkbox"
                      checked={confirmDontAsk}
                      onChange={(e) => setConfirmDontAsk(e.target.checked)}
                      className="appearance-none w-[13px] h-[13px] rounded-sm cursor-pointer checked:bg-accent transition-colors border border-current"
                    />
                    {t('cta.skipConfirm')}
                  </label>
                </div>
              ) : null}

              {/* Bottom-centre glass toolbar — meta | social | preview | get */}
              <div className="wd-bar">
                <div className="wd-bar-meta">
                  <span className="text-[13px] font-semibold text-white leading-none whitespace-nowrap">
                    {wallpaper.width.toLocaleString()} × {wallpaper.height.toLocaleString()}
                  </span>
                  <span className="mono text-[10px] tracking-[0.06em] text-white/65 whitespace-nowrap">
                    {resLabel || '—'} · {(wallpaper.file_type || 'IMAGE').toUpperCase()} · {fileSize}
                    {(wallpaper.is_dynamic || (wallpaper.file_type || '').startsWith('video/')) && <> · {t('pill.live')}</>}
                    {wallpaper.is_ai_generated && <> · AI</>}
                  </span>
                </div>

                <span className="wd-bar-divider" />

                <button
                  onClick={handleLike}
                  disabled={likeLoading}
                  className={`wd-btn ${wallpaper.is_liked ? 'is-liked' : ''}`}
                  title={wallpaper.is_liked ? t('actions.unlike') : t('actions.like')}
                >
                  {likeLoading
                    ? <AiOutlineLoading3Quarters size={14} className="animate-spin" />
                    : wallpaper.is_liked ? <AiFillHeart size={14} /> : <AiOutlineHeart size={14} />}
                  <span className="wd-bar-hidesm">{wallpaper.is_liked ? t('actions.liked') : t('actions.like')}</span>
                  <span className="wd-btn-count">{formatNumber(wallpaper.like_count)}</span>
                </button>
                <button
                  onClick={handleFavorite}
                  disabled={favLoading}
                  className={`wd-btn ${wallpaper.is_favorited ? 'is-favorited' : ''}`}
                  title={wallpaper.is_favorited ? t('actions.unfavorite') : t('actions.favorite')}
                >
                  {favLoading
                    ? <AiOutlineLoading3Quarters size={14} className="animate-spin" />
                    : wallpaper.is_favorited ? <AiFillStar size={14} /> : <AiOutlineStar size={14} />}
                  <span className="wd-bar-hidesm">{wallpaper.is_favorited ? t('actions.saved') : t('actions.favorite')}</span>
                </button>
                <button
                  onClick={() => { if (!isAuthenticated) { navigate('/login'); return; } setShowAddToCollection(true); }}
                  className="wd-btn"
                  title={t('actions.addToCollectionTitle')}
                >
                  <MdPlaylistAdd size={16} />
                  <span className="wd-bar-hidesm">{t('actions.addToList')}</span>
                </button>

                <span className="wd-bar-divider" />

                <div className="wd-actionbar-toggle">
                  {([
                    ['off',   t('preview.off'),   t('preview.offDesc')],
                    ['plain', t('preview.plain'), t('preview.plainDesc')],
                    ['home',  t('preview.home'),  t('preview.homeDesc')],
                    ['lock',  t('preview.lock'),  t('preview.lockDesc')],
                  ] as const).map(([m, label, desc]) => (
                    <button
                      key={m}
                      role="radio"
                      aria-checked={previewOverlay === m}
                      onClick={() => setPreviewOverlay(m)}
                      className={`wd-toggle-pill ${previewOverlay === m ? 'is-on' : ''}`}
                      title={desc}
                    >
                      {label}
                    </button>
                  ))}
                </div>
                <button
                  onClick={() => {
                    if (frames.length > 1 || (wallpaper.file_type || '').startsWith('video/')) {
                      toast(t('toast.useHeroControls'), { icon: 'ℹ️' });
                      return;
                    }
                    setFullscreen(true);
                  }}
                  className="wd-btn wd-btn-icon"
                  title={t('preview.fullscreenTitle')}
                >
                  <AiOutlineFullscreen size={15} />
                </button>

                <span className="wd-bar-divider" />

                {variants.length > 0 && (
                  <button
                    onClick={() => setDrawerOpen(true)}
                    className="wd-btn"
                    title={t('actions.devicesTitle')}
                  >
                    <MdDevices size={16} />
                    <span className="wd-bar-hidesm">{t('actions.devices')}</span>
                    <span className="wd-btn-count">{variants.length}</span>
                  </button>
                )}
                <button
                  onClick={handleDownloadClick}
                  disabled={dlLoading}
                  className="wd-btn-cta"
                  title={isOwner ? t('cta.downloadOriginalTitle') : t('cta.tradeTitle')}
                >
                  {dlLoading ? (
                    <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                  ) : dlDone ? (
                    <><AiOutlineCheckCircle size={15} /> {isOwner ? t('cta.gotIt') : t('cta.traded')}</>
                  ) : isOwner ? (
                    <><AiOutlineDownload size={15} /> {t('cta.download')}</>
                  ) : (
                    <>
                      <span className="w-2 h-2 rounded-full bg-white shadow-[inset_0_-2px_0_oklch(80%_0.18_60),inset_0_1px_0_oklch(98%_0.04_60)]" aria-hidden />
                      {t('cta.tradeFor', { n: downloadCost || 1 })}
                    </>
                  )}
                </button>
              </div>
            </div>
          </section>

          {/* ═══ SCREEN 2 — recommendations ═══ */}
          {similar.length > 0 && (
            <section className="wd-s2">
              <div className="mx-auto max-w-[1600px] px-6 sm:px-10 py-10">
                {(() => {
                  const cols = recCount / 2;
                  const capped = Math.min(similar.length, recCount);
                  const fullRows = Math.floor(capped / cols) * cols;
                  const shown = similar.slice(0, fullRows);
                  if (shown.length === 0) return null;
                  return (
                    <>
                      <div className="wd-similar-head">
                        <div>
                          <div className="kicker text-muted">{t('similar.kicker')}</div>
                          <h2 className="display">{t('similar.title')}</h2>
                        </div>
                        <span className="mono">{t('similar.picks', { n: shown.length })}</span>
                      </div>
                      <WallpaperGrid wallpapers={shown} viewMode="grid" sizeMode="md" />
                    </>
                  );
                })()}
              </div>
            </section>
          )}
        </div>
      </div>

      <SpotlightStyles />
    </>
  );
}

/* In-place device mockup. Renders the wallpaper inside the matched
   device's actual chassis chrome — the same MacBook / iMac / iPhone /
   iPad frames the popup-mockup uses — auto-scaled to fit the hero card.
   When no matched variant exists we synthesise reasonable defaults
   per platform so the preview still makes sense.

   Scene mapping per platform:
     mode = 'plain' → scene 'clean'   (frame only, no overlay)
     mode = 'home'  → scene 'home'  (mobile) / 'desktop' (laptop+desktop)
     mode = 'lock'  → scene 'lock'  (both — desktop got 'lock' added too) */
const DEFAULT_DEVICE_DIMS: Record<'desktop' | 'laptop' | 'tablet' | 'phone', { w: number; h: number }> = {
  desktop: { w: 2560, h: 1440 },
  laptop:  { w: 2560, h: 1600 },
  tablet:  { w: 2048, h: 1536 },
  phone:   { w: 1170, h: 2532 },
};

function InlineDeviceMockup({
  imageUrl,
  platform,
  mode,
  matched,
}: {
  imageUrl: string;
  platform: 'desktop' | 'laptop' | 'tablet' | 'phone';
  mode: 'plain' | 'home' | 'lock';
  matched: WallpaperVariant | null;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ w: 1000, h: 600 });

  useEffect(() => {
    const node = containerRef.current;
    if (!node) return;
    const ro = new ResizeObserver((entries) => {
      const r = entries[0].contentRect;
      setSize({ w: r.width, h: r.height });
    });
    ro.observe(node);
    return () => ro.disconnect();
  }, []);

  // Pick screen pixel dimensions: prefer the matched variant so the
  // visitor sees the wallpaper sized for their actual device; otherwise
  // fall back to a sensible per-platform default.
  const dvW = matched?.platform === platform ? matched.width  : DEFAULT_DEVICE_DIMS[platform].w;
  const dvH = matched?.platform === platform ? matched.height : DEFAULT_DEVICE_DIMS[platform].h;

  // Approximate the chrome outside the screen rect (bezel + stand / hinge / chin).
  const bezel = 24;
  const chromeBelow =
    platform === 'laptop'  ? dvW * 0.07 :
    platform === 'desktop' ? dvW * 0.10 :
    0;
  const totalW = dvW + bezel;
  const totalH = dvH + bezel + chromeBelow;

  // 92% safety margin so the scaled frame never quite touches the
  // hero card edges.
  // Safety margin (0.84) keeps the chassis from crowding the action
  // bar pills below — even a tall portrait phone gets a clear gap
  // between the device's bottom edge and the toggle row.
  const scale = Math.min(size.w / totalW, size.h / totalH) * 0.84;

  let frame: ReactNode;
  if (platform === 'phone') {
    const scene = mode === 'home' ? 'home' : mode === 'lock' ? 'lock' : 'clean';
    frame = <PhoneFrame imageUrl={imageUrl} width={dvW} height={dvH} scene={scene} />;
  } else if (platform === 'tablet') {
    const scene = mode === 'home' ? 'home' : mode === 'lock' ? 'lock' : 'clean';
    frame = <TabletFrame imageUrl={imageUrl} width={dvW} height={dvH} scene={scene} />;
  } else if (platform === 'laptop') {
    const scene = mode === 'home' ? 'desktop' : mode === 'lock' ? 'lock' : 'clean';
    frame = <LaptopFrame imageUrl={imageUrl} width={dvW} height={dvH} scene={scene} />;
  } else {
    const scene = mode === 'home' ? 'desktop' : mode === 'lock' ? 'lock' : 'clean';
    frame = <DesktopFrame imageUrl={imageUrl} width={dvW} height={dvH} scene={scene} />;
  }

  return (
    <div ref={containerRef} className="absolute inset-0 flex items-center justify-center overflow-hidden">
      <div
        style={{
          transform: `scale(${scale})`,
          transformOrigin: 'center center',
          filter: 'drop-shadow(0 20px 36px rgba(0,0,0,0.35))',
        }}
      >
        {frame}
      </div>
    </div>
  );
}

function DownloadProgressBar({ progress }: { progress: number | null }) {
  const { t } = useTranslation('detail');
  const value = progress === null ? 0 : Math.max(0, Math.min(100, progress));
  return (
    <div
      className="wd-download-progress"
      role="progressbar"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={progress === null ? undefined : value}
      aria-label={progress === null ? t('progress.preparingAria') : t('progress.downloadingAria')}
    >
      <div className="wd-download-progress__head">
        <span>{progress === null ? t('progress.preparing') : t('progress.downloading')}</span>
        <span className="tabular-nums">{progress === null ? '…' : `${value}%`}</span>
      </div>
      <div className="wd-download-progress__track" aria-hidden>
        {progress === null ? (
          <span className="wd-download-progress__fill wd-download-progress__fill--indeterminate" />
        ) : (
          <span
            className="wd-download-progress__fill"
            style={{ width: `${Math.max(value, value > 0 ? 4 : 0)}%` }}
          />
        )}
        </div>
    </div>
  );
}

function SpotlightStyles() {
  return (<style>{`
/* ── Immersive two-screen layout (mirrors the Mac detail page) ── */
.wd-s1 { position: relative; height: calc(100dvh - 60px); min-height: 560px; overflow: hidden; }
/* Inside the route modal the panel has its own definite height —
   fill it exactly and drop the info circle below the modal's ✕. */
.wd-in-modal .wd-s1 { height: 100%; min-height: 0; }
.wd-in-modal .wd-s1-info { top: 58px; }
.wd-s1-media { position: absolute; inset: 0; }
.wd-s1-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; cursor: zoom-in; }
.wd-s1-center { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; padding: 72px 24px 140px; }
.wd-s1-center .wd-hero-canvas { max-height: 66dvh; max-width: min(1080px, 92vw); }
/* Mac heroVignette: top 0.36 → clear → bottom 0.68 + extra lower band. */
.wd-s1-vignette { position: absolute; inset: 0; pointer-events: none;
  background:
    linear-gradient(to bottom, rgba(0,0,0,0.36), transparent 32%, transparent 55%, rgba(0,0,0,0.68)),
    linear-gradient(to bottom, transparent 60%, rgba(0,0,0,0.38)); }

/* Floating glass circles — back (top-left) / info (top-right). */
.wd-circle-btn { position: relative; width: 42px; height: 42px; border-radius: 9999px;
  display: inline-flex; align-items: center; justify-content: center;
  color: rgba(255,255,255,0.94); background: rgba(10,10,12,0.44);
  backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(0,0,0,0.30),
              0 2px 3px rgba(0,0,0,0.22), 0 10px 22px rgba(0,0,0,0.30); }
.wd-circle-btn.is-prominent { color: var(--color-ink); background: rgba(255,255,255,0.92);
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.7), 0 0 0 1px oklch(64% 0.21 42 / 0.42),
              0 2px 3px rgba(0,0,0,0.18), 0 10px 22px rgba(0,0,0,0.26); }
.wd-circle-btn.is-active { color: var(--color-accent); }
.wd-s1-back { position: absolute; top: 22px; left: 24px; z-index: 5; }
.wd-s1-info { position: absolute; top: 22px; right: 24px; z-index: 5; display: flex; flex-direction: column; align-items: flex-end; gap: 10px; }

/* Info panel — glass-dark metadata card (Mac detailInfoPanel). */
.wd-info-panel { width: 320px; max-width: 86vw; max-height: calc(100dvh - 120px); overflow-y: auto;
  padding: 16px; border-radius: 18px;
  background: rgba(10,10,12,0.50);
  backdrop-filter: blur(28px) saturate(1.4); -webkit-backdrop-filter: blur(28px) saturate(1.4);
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.20), inset 0 -1px 0 rgba(0,0,0,0.30),
              0 2px 3px rgba(0,0,0,0.22), 0 14px 30px rgba(0,0,0,0.34);
  display: flex; flex-direction: column; gap: 14px;
  animation: wdFadeIn .16s ease; }
.wd-ip-row { display: flex; align-items: center; gap: 10px; }
.wd-ip-avatar { width: 38px; height: 38px; border-radius: 9999px; overflow: hidden; flex-shrink: 0;
  background: rgba(255,255,255,0.14); border: 1px solid rgba(255,255,255,0.25);
  display: flex; align-items: center; justify-content: center; color: #fff; font-size: 16px; }
.wd-ip-avatar img { width: 100%; height: 100%; object-fit: cover; }
.wd-ip-block { border-top: 1px solid rgba(255,255,255,0.14); padding-top: 12px; }
.wd-ip-kicker { font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: rgba(255,255,255,0.50); margin-bottom: 4px; }
.wd-ip-tag { display: inline-flex; padding: 2px 9px; border-radius: 9999px; font-size: 10.5px; font-weight: 500;
  color: rgba(255,255,255,0.85); background: rgba(255,255,255,0.10); border: 1px solid rgba(255,255,255,0.16); }
.wd-ip-swatch { width: 30px; height: 30px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.25); cursor: pointer; transition: transform 160ms var(--ease-out-quart); }
.wd-ip-swatch:hover { transform: scale(1.08); }
.wd-ip-stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px 12px; border-top: 1px solid rgba(255,255,255,0.14); padding-top: 12px; }
.wd-ip-foot { display: flex; align-items: center; justify-content: space-between; gap: 10px; border-top: 1px solid rgba(255,255,255,0.14); padding-top: 10px; font-size: 11.5px; }

/* Bottom-centre column: progress + notices + toolbar. */
.wd-s1-bottom { position: absolute; left: 50%; bottom: 22px; transform: translateX(-50%); z-index: 6;
  display: flex; flex-direction: column; align-items: center; gap: 12px;
  width: max-content; max-width: calc(100vw - 32px); }
.wd-s1-bottom .wd-notice { width: min(560px, calc(100vw - 40px)); }
.wd-s1-bottom .wd-download-progress { width: min(420px, calc(100vw - 40px)); margin-top: 0; }

/* The toolbar itself — dark glass capsule (Mac immersiveToolbar). */
.wd-bar { position: relative; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: center;
  padding: 8px 10px; border-radius: 9999px;
  background: rgba(10,10,12,0.44);
  backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(0,0,0,0.30),
              0 2px 3px rgba(0,0,0,0.22), 0 12px 26px rgba(0,0,0,0.34); }
.wd-bar-meta { display: flex; flex-direction: column; gap: 3px; padding: 0 6px 0 10px; }
.wd-bar-divider { width: 1px; height: 24px; background: rgba(255,255,255,0.22); flex-shrink: 0; }
/* Buttons inside the dark bar: flat white tints (no glass-on-glass). */
.wd-bar .wd-btn { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.14); color: rgba(255,255,255,0.92); box-shadow: none; }
.wd-bar .wd-btn:hover { background: rgba(255,255,255,0.16); border-color: rgba(255,255,255,0.28); }
.wd-bar .wd-btn-count { background: rgba(255,255,255,0.14); color: rgba(255,255,255,0.75); }
.wd-bar .wd-btn.is-liked { color: #ff9e97; border-color: rgba(224,70,58,0.65); background: rgba(224,70,58,0.20); }
.wd-bar .wd-btn.is-favorited { color: #ffd98f; border-color: rgba(216,162,58,0.65); background: rgba(216,162,58,0.20); }
.wd-bar .wd-actionbar-toggle { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.12); }
.wd-bar .wd-toggle-pill { color: rgba(255,255,255,0.60); }
.wd-bar .wd-toggle-pill:hover { color: rgba(255,255,255,0.9); }
.wd-bar .wd-toggle-pill.is-on { background: rgba(255,255,255,0.92); color: var(--color-ink); }
@media (max-width: 900px) { .wd-bar-hidesm { display: none; } .wd-bar-meta { display: none; } }

/* Screen 2 — recommendations on paper. */
.wd-s2 { position: relative; z-index: 1; background: var(--color-paper); border-top: 1px solid var(--color-hair); }

/* ── Outer blurred-wallpaper backdrop ────────────────────────── */
.wd-root { isolation: isolate; }
.wd-backdrop { position: absolute; inset: 0; z-index: 0; overflow: hidden; }
.wd-backdrop img { width: 100%; height: 100%; object-fit: cover; filter: blur(38px) saturate(1.4); transform: scale(1.18); }
.wd-backdrop-scrim { position: absolute; inset: 0; z-index: 0; background: linear-gradient(180deg, rgba(250,247,240,0.42) 0%, rgba(250,247,240,0.7) 100%); pointer-events: none; }

/* ── Stage panel — dominant-color mesh card holds hero + bar ── */
.wd-panel { position: relative; border-radius: 24px; padding: clamp(16px, 2vw, 24px); border: none; overflow: hidden;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.55), inset 0 -1px 0 rgba(0,0,0,0.14), 0 2px 3px rgba(0,0,0,0.18), 0 18px 40px -18px rgba(0,0,0,0.30); }
.wd-panel::before { content: ""; position: absolute; inset: 0; border-radius: inherit; background: linear-gradient(135deg, rgba(255,255,255,0.22), rgba(255,255,255,0.05) 34%, transparent 58%); pointer-events: none; }

/* ── Hero card ─────────────────────────────────────────────── */
/* Transparent stage — visual chrome lives on the image / canvas inside,
   so a wide-short or tall-narrow image doesn't get padded out by an
   empty container background. */
.wd-hero { position: relative; width: 100%; display: flex; justify-content: center; align-items: center; }
.wd-hero-img { display: block; max-width: 100%; max-height: 64vh; width: auto; height: auto; object-fit: contain; border-radius: 18px; box-shadow: 0 18px 48px -18px rgba(0,0,0,0.32); border: 1px solid rgba(255,255,255,0.18); cursor: zoom-in; }
.wd-hero-canvas { position: relative; width: 100%; max-width: 1080px; max-height: 64vh; border-radius: 18px; overflow: hidden; box-shadow: 0 18px 48px -18px rgba(0,0,0,0.32); border: 1px solid rgba(255,255,255,0.18); }
.wd-hero-stage { position: relative; width: 100%; height: 64vh; }
.wd-hero-img-wrap { position: relative; display: inline-block; line-height: 0; border-radius: 18px; max-width: 100%; }

/* Download progress bar */
.wd-download-progress { width: 100%; margin-top: clamp(12px, 1.4vw, 16px); padding: 10px 14px; border-radius: 14px; background: color-mix(in oklch, var(--color-accent) 12%, var(--color-paper) 88%); border: 1px solid color-mix(in oklch, var(--color-accent) 24%, transparent); }
.wd-download-progress__head { display: flex; align-items: center; justify-content: space-between; gap: 14px; margin-bottom: 7px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.14em; color: var(--color-accent); text-transform: uppercase; }
.wd-download-progress__head .tabular-nums { color: var(--color-muted); letter-spacing: 0.08em; }
.wd-download-progress__track { position: relative; height: 6px; border-radius: 999px; overflow: hidden; background: color-mix(in oklch, var(--color-accent) 16%, transparent); }
.wd-download-progress__fill { position: absolute; inset: 0 auto 0 0; display: block; border-radius: inherit; background: linear-gradient(90deg, var(--color-accent), color-mix(in oklch, var(--color-accent) 72%, var(--color-ink) 28%)); transition: width 0.4s cubic-bezier(0.2, 0.8, 0.2, 1); }
.wd-download-progress__fill--indeterminate { width: 28px; min-width: 10%; animation: wd-download-progress-sweep 1.1s cubic-bezier(0.22, 1, 0.36, 1) infinite; }
@keyframes wd-download-progress-sweep {
  0%   { transform: translateX(-120%); }
  100% { transform: translateX(420%); }
}

/* ── Action bar ─────────────────────────────────────────────── */
.wd-actionbar { position: relative; margin-top: clamp(14px, 1.6vw, 18px); padding: 14px clamp(12px, 1.6vw, 16px);
  background: color-mix(in oklab, var(--color-paper) 55%, transparent);
  backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
  border: none; border-radius: 18px;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.55), inset 0 -1px 0 rgba(0,0,0,0.12), 0 2px 3px rgba(0,0,0,0.14), 0 10px 24px -12px rgba(0,0,0,0.24); }
.wd-actionbar::before { content: ""; position: absolute; inset: 0; border-radius: inherit; background: linear-gradient(135deg, rgba(255,255,255,0.20), rgba(255,255,255,0.04) 34%, transparent 58%); pointer-events: none; }
.wd-actionbar-meta { display: flex; align-items: baseline; gap: 12px; padding-bottom: 12px; border-bottom: 1px solid var(--color-hair); margin-bottom: 12px; flex-wrap: wrap; }
.wd-actionbar-meta .display { color: var(--color-ink); font-weight: 500; }
.wd-actionbar-pill { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 999px; background: var(--color-ink); color: var(--color-accent); font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.14em; }
.wd-actionbar-pill.is-ai { background: oklch(50% 0.18 285); color: white; }
.wd-actionbar-rows { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.wd-actionbar-group { display: inline-flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.wd-actionbar-divider { width: 1px; height: 28px; background: var(--color-hair); flex-shrink: 0; }
.wd-actionbar-toggle { background: var(--color-paper-2); padding: 3px; border-radius: 999px; border: 1px solid var(--color-hair); }

.wd-btn { display: inline-flex; align-items: center; gap: 7px; padding: 8px 14px; border-radius: 999px; border: 1px solid var(--color-hair);
  background: color-mix(in oklab, var(--color-paper) 82%, transparent); color: var(--color-ink); font-size: 12px; font-weight: 500; white-space: nowrap;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.5);
  transition: background-color .15s ease, color .15s ease, border-color .15s ease, transform 240ms cubic-bezier(0.34,1.56,0.64,1); }
.wd-btn:not(:disabled):hover { transform: scale(1.05); }
.wd-btn:not(:disabled):active { transform: scale(0.92); }
.wd-btn:hover { background: var(--color-paper-2); border-color: var(--color-ink-2); }
.wd-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.wd-btn-icon { padding: 8px 12px; }
.wd-btn.is-liked { color: oklch(58% 0.20 25); border-color: oklch(58% 0.20 25); background: color-mix(in oklch, oklch(58% 0.20 25) 4%, var(--color-paper)); }
.wd-btn.is-favorited { color: oklch(70% 0.18 65); border-color: oklch(70% 0.18 65); background: color-mix(in oklch, oklch(70% 0.18 65) 5%, var(--color-paper)); }
.wd-btn-count { display: inline-flex; align-items: center; padding: 1px 6px; border-radius: 999px; background: var(--color-paper-2); color: var(--color-muted); font-family: var(--font-mono); font-size: 10px; margin-left: 2px; }

.wd-toggle-pill { padding: 6px 14px; border-radius: 999px; font-size: 12px; font-weight: 500; color: var(--color-muted); transition: all .15s ease; }
.wd-toggle-pill:hover { color: var(--color-ink-2); }
.wd-toggle-pill.is-on { background: var(--color-paper); color: var(--color-ink); box-shadow: inset 0 1px 0 rgba(255,255,255,0.7), 0 1.5px 2px rgba(0,0,0,0.12), 0 3px 6px rgba(0,0,0,0.14); }

.wd-btn-cta { display: inline-flex; align-items: center; gap: 8px; padding: 9px 18px; border-radius: 999px; background: var(--color-accent); color: white; font-size: 13px; font-weight: 600; white-space: nowrap;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.35), 0 4px 8px -2px oklch(64% 0.21 42 / 0.30), 0 8px 16px -6px oklch(64% 0.21 42 / 0.35);
  transition: filter .15s ease, transform 240ms cubic-bezier(0.34,1.56,0.64,1); }
.wd-btn-cta:not(:disabled):hover { transform: scale(1.04); }
.wd-btn-cta:not(:disabled):active { transform: scale(0.94); }
.wd-btn-cta:hover { filter: brightness(1.05); }
.wd-btn-cta:disabled { opacity: 0.7; cursor: not-allowed; }

/* ── Detail notices — trade / download / coin states ─────────── */
.wd-notice { padding: 20px; border-radius: 18px; border: 1px solid; box-shadow: 0 10px 30px -20px rgba(0,0,0,0.28); }
.wd-notice-kicker { font-family: var(--font-mono); font-size: 10px; font-weight: 600; letter-spacing: 0.14em; text-transform: uppercase; }
.wd-notice-title { font-family: var(--font-display); font-size: clamp(24px, 2.4vw, 28px); line-height: 1.05; margin-top: 6px; color: var(--wd-notice-title, currentColor); }
.wd-notice-title.is-large { font-size: clamp(28px, 3vw, 34px); line-height: 1; }
.wd-notice-title.is-xl { font-size: clamp(30px, 3.3vw, 36px); line-height: 1; }
.wd-notice-title span { color: var(--wd-notice-ink, currentColor); }
.wd-notice-meta { margin-top: 8px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.14em; color: var(--wd-notice-ink, currentColor); }
.wd-notice-rule { margin: 14px 0; border: 0; border-top: 1px solid var(--wd-notice-rule, var(--color-hair)); }
.wd-notice-foot { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 8px; font-size: 12px; color: var(--wd-notice-text, currentColor); }
.wd-notice-foot a { color: var(--wd-notice-ink, currentColor); }
.wd-notice-foot strong { color: var(--wd-notice-ink, currentColor); }
.wd-notice-primary,
.wd-notice-secondary { display: inline-flex; align-items: center; justify-content: center; gap: 10px; border-radius: 999px; white-space: nowrap; text-decoration: none; transition: filter .15s ease, background-color .15s ease, color .15s ease, border-color .15s ease; }
.wd-notice-primary { padding: 12px 20px; background: var(--wd-notice-action, var(--color-ink)); color: var(--wd-notice-action-text, var(--color-paper)); font-size: 13px; font-weight: 650; }
.wd-notice-primary:hover { filter: brightness(1.05); }
.wd-notice-primary:disabled { opacity: 0.6; cursor: not-allowed; }
.wd-notice-secondary { padding: 8px 20px; border: 1px solid var(--wd-notice-secondary-border, var(--color-hair)); color: var(--wd-notice-secondary-text, var(--color-ink-2)); font-size: 12px; font-weight: 600; background: transparent; }
.wd-notice-check { display: inline-flex; align-items: center; gap: 8px; font-size: 11px; cursor: pointer; user-select: none; color: var(--wd-notice-muted, var(--color-muted)); }
.wd-notice-refill { margin-top: 6px; display: inline-flex; align-items: center; gap: 4px; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.14em; text-decoration: none; color: var(--wd-notice-muted, var(--color-muted)); transition: color .15s ease; }
.wd-notice-refill:hover { color: var(--color-accent); }
.wd-notice.is-success {
  --wd-notice-ink: oklch(43% 0.09 145);
  --wd-notice-title: oklch(32% 0.08 145);
  --wd-notice-text: oklch(35% 0.07 145);
  --wd-notice-action: var(--color-ink);
  --wd-notice-action-text: var(--color-paper);
  --wd-notice-rule: oklch(43% 0.09 145 / 0.25);
  color: var(--wd-notice-ink);
  background: oklch(95% 0.05 150);
  border-color: oklch(43% 0.09 145 / 0.65);
}
.wd-notice.is-warning {
  --wd-notice-ink: oklch(47% 0.12 72);
  --wd-notice-title: oklch(35% 0.10 72);
  --wd-notice-text: oklch(40% 0.10 72);
  --wd-notice-action: oklch(47% 0.12 72);
  --wd-notice-action-text: white;
  --wd-notice-rule: oklch(47% 0.12 72 / 0.28);
  color: var(--wd-notice-ink);
  background: oklch(96% 0.05 70);
  border-color: oklch(52% 0.13 72 / 0.72);
}
.wd-notice.is-confirm {
  --wd-notice-ink: var(--color-accent);
  --wd-notice-title: var(--color-paper);
  --wd-notice-action: var(--color-accent);
  --wd-notice-action-text: white;
  --wd-notice-secondary-border: rgba(255,255,255,0.18);
  --wd-notice-secondary-text: rgba(255,255,255,0.85);
  --wd-notice-muted: rgba(255,255,255,0.62);
  --wd-notice-rule: rgba(255,255,255,0.12);
  color: var(--color-paper);
  background: var(--color-ink);
  border-color: var(--color-accent);
  border-width: 2px;
}

/* ── Content card (stats + meta + palette) ─────────────────── */
.wd-content-card { background: var(--color-paper); border: 1px solid var(--color-hair); border-radius: 20px; overflow: hidden; box-shadow: 0 8px 28px -16px rgba(0,0,0,0.16); }
.wd-tag-chip { display: inline-flex; align-items: center; gap: 5px; padding: 3px 10px 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 500; border: 1px solid; line-height: 1.4; transition: transform .15s ease; }
.wd-tag-chip:hover { transform: translateY(-1px); }
.wd-tag-chip-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }

.wd-similar-head { display: flex; align-items: end; justify-content: space-between; gap: 18px; padding-bottom: 12px; margin-bottom: 16px; border-bottom: 1px solid var(--color-hair); }
.wd-similar-head h2 { margin-top: 7px; font-size: clamp(28px, 3vw, 36px); line-height: 1; color: var(--color-ink); }
.wd-similar-head .mono { font-size: 10px; letter-spacing: 0.14em; color: var(--color-muted); white-space: nowrap; }

/* ── Devices drawer — right-side slide-in ──────────────────── */
.wd-drawer-scrim { position: fixed; inset: 0; background: rgba(20,18,15,0.42); backdrop-filter: blur(2px); z-index: 60; display: flex; justify-content: flex-end; animation: wdFadeIn .2s ease; }
.wd-drawer { width: 440px; max-width: 92vw; height: 100vh;
  background: color-mix(in oklab, var(--color-paper) 76%, transparent);
  backdrop-filter: blur(28px) saturate(1.4); -webkit-backdrop-filter: blur(28px) saturate(1.4);
  display: flex; flex-direction: column;
  box-shadow: inset 1px 0 0 rgba(255,255,255,0.4), -20px 0 60px -20px rgba(0,0,0,0.30);
  border-left: 1px solid rgba(255,255,255,0.30); animation: wdSlideInRight .28s cubic-bezier(0.2,0.8,0.2,1); }
.wd-drawer-head { padding: 22px 22px 16px; border-bottom: 1px solid var(--color-hair); display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; flex-shrink: 0; }
.wd-drawer-body { flex: 1; overflow-y: auto; padding: 6px 18px 18px; }
.wd-drawer-foot { padding: 12px 22px; border-top: 1px solid var(--color-hair); background: var(--color-paper-2); flex-shrink: 0; }
.wd-drawer-group { margin-top: 14px; }
.wd-drawer-grouphead { display: flex; justify-content: space-between; align-items: baseline; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--color-muted); padding: 0 6px 6px; border-bottom: 1px solid var(--color-hair); margin-bottom: 6px; }
.wd-drawer-row { display: flex; flex-direction: column; gap: 10px; padding: 12px; border-radius: 12px; transition: background-color .15s ease; border: 1px solid transparent; margin-bottom: 4px; }
.wd-drawer-row:hover { background: var(--color-paper-2); border-color: var(--color-hair); }
.wd-drawer-row.is-matched { background: color-mix(in oklch, var(--color-accent) 5%, var(--color-paper)); border-color: color-mix(in oklch, var(--color-accent) 25%, var(--color-hair)); }
.wd-drawer-row-head { display: flex; align-items: center; gap: 12px; }
.wd-drawer-row-actions { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px; }
.wd-drawer-action { display: inline-flex; align-items: center; justify-content: center; gap: 5px; padding: 7px 8px; border-radius: 999px; border: 1px solid var(--color-hair); background: var(--color-paper); color: var(--color-ink-2); font-size: 11px; font-weight: 500; transition: background-color .15s ease, color .15s ease, border-color .15s ease; }
.wd-drawer-action:hover:not(:disabled):not(.is-disabled) { background: var(--color-paper-2); color: var(--color-ink); border-color: var(--color-ink-2); }
.wd-drawer-action:disabled, .wd-drawer-action.is-disabled { opacity: 0.45; cursor: not-allowed; }
.wd-drawer-action-cta { background: var(--color-ink); color: var(--color-paper); border-color: var(--color-ink); }
.wd-drawer-action-cta:hover:not(:disabled) { background: var(--color-ink-2); border-color: var(--color-ink-2); color: var(--color-paper); }
.wd-drawer-action-cta.is-matched { background: var(--color-accent); border-color: var(--color-accent); }
.wd-drawer-action-cta.is-matched:hover:not(:disabled) { filter: brightness(1.05); }

@keyframes wdSlideInRight { from { transform: translateX(20px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
@keyframes wdFadeIn { from { opacity: 0; } to { opacity: 1; } }

@media (max-width: 640px) {
  .wd-actionbar-divider { display: none; }
  .wd-actionbar-rows { gap: 8px; }
  .wd-actionbar-toggle { width: 100%; justify-content: center; }
}
`}</style>);
}

// VideoPlayer: poster + center play button. On the first click we fully
// buffer the clip into a blob (showing a progress bar over the poster) and
// only then start playback, so it can't stall mid-stream on a slow link.
// Phases:
//   idle      — poster only, play icon centered
//   buffering — poster still showing, progress bar replaces the play icon
//   playing   — video crossfades over poster from the in-memory blob;
//               click pauses (pause button shows on hover when playing)
// No bytes are fetched until the user actively chooses to play.
function VideoPlayer({ src, poster }: { src: string; poster?: string }) {
  const { t } = useTranslation('detail');
  const vidRef = useRef<HTMLVideoElement | null>(null);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [progress, setProgress] = useState<number | null>(null); // null = not buffering
  const [buffering, setBuffering] = useState(false);
  const [playing, setPlaying] = useState(false);

  // Release the object URL when it changes or the player unmounts.
  useEffect(() => () => { if (blobUrl) URL.revokeObjectURL(blobUrl); }, [blobUrl]);

  const startBuffering = async () => {
    if (buffering || blobUrl) return;
    setBuffering(true);
    setProgress(0);
    try {
      const resp = await fetch(src);
      if (!resp.ok) throw new Error(`status ${resp.status}`);
      const blob = await fetchBlobWithProgress(resp, setProgress);
      setProgress(100);
      setBlobUrl(URL.createObjectURL(blob)); // the effect below kicks off play
    } catch {
      setBuffering(false);
      setProgress(null);
    }
  };

  const toggle = () => {
    const v = vidRef.current;
    if (!blobUrl) { startBuffering(); return; }
    if (!v) return;
    if (v.paused) v.play().catch(() => {});
    else v.pause();
  };

  // Once the fully-buffered blob is attached, start playback.
  useEffect(() => {
    if (blobUrl && vidRef.current) {
      vidRef.current.play().catch(() => {});
    }
  }, [blobUrl]);

  return (
    <div className="relative w-full h-full bg-black flex items-center justify-center">
      {poster && (
        <img
          src={poster}
          alt=""
          decoding="async"
          draggable={false}
          className={`absolute inset-0 w-full h-full object-contain pointer-events-none transition-opacity duration-300 ${playing ? 'opacity-0' : 'opacity-100'}`}
          style={{ transitionTimingFunction: 'var(--ease-out-quart)' }}
        />
      )}
      <video
        ref={vidRef}
        src={blobUrl ?? undefined}
        loop
        playsInline
        muted
        onPlaying={() => { setPlaying(true); setBuffering(false); }}
        onPause={() => setPlaying(false)}
        className={`relative z-[1] w-full h-full object-contain transition-opacity duration-300 ${playing ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
      />
      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? t('video.pause') : buffering ? t('video.loading') : t('video.play')}
        className="absolute inset-0 z-[2] flex items-center justify-center group"
        disabled={buffering}
      >
        {buffering ? (
          <span className="flex flex-col items-center gap-2.5 rounded-2xl bg-black/55 px-6 py-5 text-white backdrop-blur-md">
            <span className="h-1.5 w-40 overflow-hidden rounded-full bg-white/25">
              <span
                className="block h-full w-full origin-left rounded-full bg-white transition-transform duration-150 ease-out"
                style={{ transform: `scaleX(${(progress ?? 0) / 100})` }}
              />
            </span>
            <span className="mono text-[11px] tracking-wide tabular-nums text-white/90">{progress ?? 0}%</span>
          </span>
        ) : (
          <span
            className={`flex items-center justify-center w-20 h-20 rounded-full bg-black/55 text-white backdrop-blur-md transition-all duration-200 group-hover:scale-110 group-hover:bg-black/70 ${playing ? 'opacity-0 group-hover:opacity-100' : 'opacity-100'}`}
            style={{ transitionTimingFunction: 'var(--ease-out-quart)' }}
          >
            {playing ? (
              <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M6 5h4v14H6zM14 5h4v14h-4z"/></svg>
            ) : (
              <svg width="28" height="28" viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
            )}
          </span>
        )}
      </button>
    </div>
  );
}
