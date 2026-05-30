import { useState, useEffect, useMemo, useCallback, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import InAppConfirm from '../components/InAppConfirm';
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
  AiOutlineZoomIn,
  AiOutlineZoomOut,
  AiOutlineRedo,
  AiOutlineReload,
} from 'react-icons/ai';
import { MdPlaylistAdd, MdDesktopMac, MdLaptopMac, MdTabletMac, MdPhoneIphone, MdOutlineRemoveRedEye, MdDevices } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User, Category } from '../types';
import DeviceMockup, {
  canShowMockup,
  PhoneFrame, TabletFrame, LaptopFrame, DesktopFrame,
} from '../components/DeviceMockup';
import ReportModal from '../components/ReportModal';
import WallpaperGrid from '../components/WallpaperGrid';
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
  getCategories,
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
  const [similar, setSimilar] = useState<Wallpaper[]>([]);
  // Cache the full category list so we can map wallpaper.category_id (a
  // number) to a display name without a per-detail fetch. List is tiny
  // (10 rows) and stable across pages, so one fetch per mount is fine.
  const [categories, setCategories] = useState<Category[]>([]);
  useEffect(() => {
    getCategories()
      .then((r) => setCategories(r.data.data || []))
      .catch(() => setCategories([]));
  }, []);
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
  // Coin CTA state machine: default → confirm → (success | insufficient)
  // 'insufficient' is computed from balance + cost rather than tracked
  // separately so a fresh page-load with balance < cost lands directly
  // on the warning state.
  const [ctaMode, setCtaMode] = useState<'default' | 'confirm' | 'success'>('default');
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
    // The top "Download" button is meant to deliver the original upload —
    // designers, editors, and people archiving the file expect the source,
    // not a re-encoded screen-sized JPEG. Variant downloads happen *only*
    // when the user clicks a row in the variant list, which passes the
    // variant in explicitly. Dynamic HEICs always come back as the
    // original regardless (variants can't represent multi-frame HEIC).
    const useVariant = wallpaper.is_dynamic ? null : variant;
    setDlLoading(true);
    setDlProgress(null);
    try {
      let blobUrl: string;
      let filename: string;
      if (useVariant) {
        // POST first: on a cold variant the server resizes the original
        // before answering, so keep the bar indeterminate until then.
        const apiResp = await downloadVariant(wallpaper.id, useVariant.id);
        const dlUrl = apiResp.data.data?.url;
        if (!dlUrl) { toast.error('Download failed'); return; }
        const resp = await fetch(dlUrl);
        const blob = await fetchBlobWithProgress(resp, setDlProgress);
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
        const blob = await fetchBlobWithProgress(resp, setDlProgress);
        blobUrl = URL.createObjectURL(blob);
        const ext = finalUrl.split('.').pop()?.split('?')[0] || 'jpg';
        filename = `wallpaper_${wallpaper.id}_${wallpaper.width}x${wallpaper.height}.${ext}`;
      }
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
        const remaining = user.coins - 1;
        updateCoins(remaining);
      }
      // Promote the CTA to the success state. Replaces the old SetWallpaperGuide
      // popup — the "now what?" message ("Show in Downloads", "Browse more",
      // macOS app cross-promo) is rendered inline in the right column instead
      // of as a separate modal that would compete with the open detail panel.
      setCtaMode('success');
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response?.status;
      if (status === 402) {
        toast.error('Insufficient coins. Upload wallpapers to earn more!');
      } else {
        toast.error('Download failed');
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
      toast.success('Wallpaper deleted');
      navigate('/');
    } catch {
      toast.error('Delete failed');
    }
  };

  if (loading) return <Spinner />;
  if (!wallpaper && error) return <ErrorState />;
  if (!wallpaper) return <EmptyState message="Wallpaper not found." />;

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
  const isMacUA = /Macintosh|Mac OS X/i.test(navigator.userAgent);

  // Resolve the visible CTA state. Order matters: success comes first because
  // it should stick after a successful download even if we re-render with a
  // newly-zero balance; insufficient is computed from the balance and forces
  // the warning surface regardless of any explicit transition the user kicked
  // off; confirm/default come from the explicit ctaMode state.
  const ctaState: 'default' | 'confirm' | 'success' | 'insufficient' =
    ctaMode === 'success' ? 'success'
    : insufficient ? 'insufficient'
    : ctaMode === 'confirm' ? 'confirm'
    : 'default';

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
        title="Delete this wallpaper?"
        message="This removes the wallpaper and all its generated variants permanently. This action cannot be undone."
        confirmLabel="Delete"
        destructive
        onConfirm={doDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      {tradeFlashTick > 0 && createPortal(
        <div key={tradeFlashTick} className="trade-flash" aria-hidden />,
        document.body,
      )}

      {dlLoading && createPortal(
        <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/45 px-6">
          <div className="w-full max-w-sm rounded-2xl border border-hair bg-paper p-6 shadow-2xl">
            <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">
              {dlProgress === null ? 'Preparing' : 'Downloading'}
            </div>
            <div className="mt-1 display text-[20px] leading-tight text-ink truncate">
              {wallpaper?.title?.trim() || `Wallpaper #${wallpaper?.id}`}
            </div>
            <div className="mt-5 h-1.5 w-full overflow-hidden rounded-full bg-paper-3">
              {dlProgress === null ? (
                <div className="dl-indeterminate h-full w-1/3 rounded-full bg-accent" />
              ) : (
                <div
                  className="h-full w-full origin-left rounded-full bg-accent transition-transform duration-200 ease-out"
                  style={{ transform: `scaleX(${dlProgress / 100})` }}
                />
              )}
            </div>
            <div className="mt-2 flex items-center justify-between mono text-[11px] text-ink-2">
              <span>{dlProgress === null ? 'Generating your size' : 'Saving to your device'}</span>
              <span className="tabular-nums">{dlProgress === null ? '' : `${dlProgress}%`}</span>
            </div>
          </div>
        </div>,
        document.body,
      )}

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
            aria-label="Close"
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
            <ToolbarBtn label="Zoom out" onClick={() => setFsScale((s) => Math.max(0.5, s / 1.25))}>
              <AiOutlineZoomOut size={18} />
            </ToolbarBtn>
            <ToolbarBtn label="Zoom in" onClick={() => setFsScale((s) => Math.min(5, s * 1.25))}>
              <AiOutlineZoomIn size={18} />
            </ToolbarBtn>
            <span className="w-px h-5 bg-white/20 mx-1" aria-hidden />
            <ToolbarBtn label="Rotate 90°" onClick={() => setFsRotation((r) => (r + 90) % 360)}>
              <AiOutlineRedo size={18} />
            </ToolbarBtn>
            <span className="w-px h-5 bg-white/20 mx-1" aria-hidden />
            <ToolbarBtn label="Reset" onClick={() => { setFsScale(1); setFsRotation(0); setFsPan({ x: 0, y: 0 }); }}>
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
                <div className="kicker text-muted">All devices · {variants.length}</div>
                <h3 className="display text-[20px] leading-tight mt-1">Pick the right size</h3>
              </div>
              <button onClick={() => setDrawerOpen(false)} className="p-1.5 rounded-full hover:bg-paper-2" aria-label="Close drawer">
                <AiOutlineClose size={18} />
              </button>
            </div>
            <div className="wd-drawer-body">
              {(['desktop', 'laptop', 'tablet', 'phone', 'other'] as const).map((platform) => {
                const list = groupedVariants[platform];
                if (!list || list.length === 0) return null;
                const label = { desktop: 'Desktop', laptop: 'Laptop', tablet: 'Tablet', phone: 'Phone', other: 'Other' }[platform];
                return (
                  <div key={platform} className="wd-drawer-group">
                    <div className="wd-drawer-grouphead">
                      <span>{label}</span>
                      <span className="mono text-[10px] tracking-[0.14em] text-muted normal-case">{list.length}</span>
                    </div>
                    {list.map((v) => {
                      const isMatched = matchedVariant?.id === v.id;
                      const mockable = canShowMockup(v);
                      const deviceName = [v.brand, v.device_name].filter(Boolean).join(' ').trim() || 'Device';
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
                                  <span className="mono text-[9px] tracking-[0.14em] px-1.5 py-[1px] bg-ink text-paper rounded">YOUR DEVICE</span>
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
                              title={mockable ? 'Preview in this device' : 'Mockup not available for this device'}
                              className="wd-drawer-action"
                            >
                              <MdOutlineRemoveRedEye size={14} /> Preview
                            </button>
                            {v.device_slug ? (
                              <Link
                                to={`/wallpapers-for/${v.device_slug}`}
                                className="wd-drawer-action no-underline"
                                title={`Browse all wallpapers for the ${deviceName}`}
                              >
                                <MdDevices size={14} /> Browse
                              </Link>
                            ) : (
                              <span className="wd-drawer-action is-disabled" title="No device page available">
                                <MdDevices size={14} /> Browse
                              </span>
                            )}
                            <button
                              onClick={() => handleDownload(v)}
                              disabled={dlLoading}
                              title="Download this variant"
                              className={`wd-drawer-action wd-drawer-action-cta ${isMatched ? 'is-matched' : ''}`}
                            >
                              <AiOutlineDownload size={14} /> Get
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
              ESC OR CLICK OUTSIDE TO CLOSE{isOwner ? '' : ` · ${downloadCost || 1} COIN PER DOWNLOAD`}
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
            <img src={heroImg} alt="" />
          </div>
        )}
        <div className="wd-backdrop-scrim" aria-hidden />

        {/* Modal-mode chrome moved to the modal wrapper itself
            (corner-anchored ✕). No header strip here. */}

        <div className="flex-1 min-h-0 overflow-y-auto relative z-10">
          <div className="mx-auto max-w-[1280px] px-4 sm:px-6 lg:px-8 py-6 lg:py-8">

            {/* ─── STAGE PANEL — dominant-color mesh card holds the hero
                + the action bar. Rounded all around so the harsh
                rectangle from the previous iteration is gone. */}
            <div
              className="wd-panel"
              style={{
                background: wallpaper.dominant_color
                  ? `radial-gradient(120% 80% at 20% 0%, ${wallpaper.dominant_color}88 0%, transparent 55%),
                     radial-gradient(100% 70% at 100% 100%, ${wallpaper.dominant_color}66 0%, transparent 50%),
                     linear-gradient(180deg, ${wallpaper.dominant_color}33 0%, var(--color-paper) 80%)`
                  : 'var(--color-paper)',
              }}
            >
              {/* Hero card.
                  - 'off' mode uses the wallpaper's intrinsic aspect ratio
                    (and lets clicking the image enter the fullscreen
                    viewer).
                  - plain / home / lock all render the wallpaper inside
                    the matched-device chrome via InlineDeviceMockup,
                    which auto-scales to fit. Aspect is dropped in this
                    mode and a fixed-ish height takes over so the frame
                    has room for its stand / chin / bezel.
                  - Video and dynamic-HEIC always render their natural
                    surfaces regardless of preview mode; the frame
                    toggles are not meaningful for those formats. */}
              {/* Hero stage — transparent flex container that centers the
                  image (or canvas) horizontally. The visual chrome (rounded
                  corners, shadow) lives on the image / canvas itself, so the
                  container shrinks to its content and never paints an empty
                  background strip around wide-short or tall-narrow wallpapers. */}
              <div className="wd-hero">
                {frames.length > 1 ? (
                  <div className="wd-hero-canvas" style={{ aspectRatio: wallpaper.width > 0 && wallpaper.height > 0 ? `${wallpaper.width} / ${wallpaper.height}` : '16 / 9', backgroundColor: wallpaper.dominant_color || undefined }}>
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
                      onClick={(e) => { e.stopPropagation(); setFramePlaying((p) => !p); }}
                      className="absolute bottom-3 right-3 px-3 py-1 bg-black/60 text-white text-[11px] mono rounded backdrop-blur-sm"
                    >{framePlaying ? 'PAUSE' : 'PLAY'} · {frameIdx + 1}/{frames.length}</button>
                  </div>
                ) : (wallpaper.file_type || '').startsWith('video/') && wallpaper.original_url ? (
                  <div className="wd-hero-canvas" style={{ aspectRatio: wallpaper.width > 0 && wallpaper.height > 0 ? `${wallpaper.width} / ${wallpaper.height}` : '16 / 9', backgroundColor: wallpaper.dominant_color || undefined }}>
                    <VideoPlayer
                      src={wallpaper.preview_video_url || wallpaper.original_url}
                      poster={wallpaper.preview_url || wallpaper.thumb_url}
                    />
                  </div>
                ) : heroImg ? (
                  previewOverlay !== 'off' ? (
                    /* Frame mode — transparent fixed-size stage purely
                        for layout. No rounded card, no shadow, no
                        background — the device chassis is the visual
                        and any chrome around it would compete. */
                    <div className="wd-hero-stage">
                      <InlineDeviceMockup
                        imageUrl={heroImg}
                        platform={overlayPlatform}
                        mode={previewOverlay}
                        matched={matchedVariant}
                      />
                    </div>
                  ) : (
                    /* Off mode — image sizes itself, container shrinks to it */
                    <img
                      src={heroImg}
                      alt=""
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      onClick={() => setFullscreen(true)}
                      className="wd-hero-img"
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                  )
                ) : null}
              </div>

              {/* ─── ACTION BAR ─── */}
              <div className="wd-actionbar">
                {/* Meta strip — was the top-right specs box before */}
                <div className="wd-actionbar-meta">
                  <span className="display text-[15px] leading-none">
                    {wallpaper.width.toLocaleString()}<span className="text-muted"> × </span>{wallpaper.height.toLocaleString()}
                  </span>
                  <span className="mono text-[11px] tracking-[0.06em] text-muted">
                    {resLabel || '—'} · {(wallpaper.file_type || 'IMAGE').toUpperCase()} · {fileSize}
                  </span>
                  {wallpaper.is_dynamic && <span className="wd-actionbar-pill">● DYNAMIC</span>}
                  {wallpaper.is_ai_generated && <span className="wd-actionbar-pill is-ai">✦ AI</span>}
                </div>

                {/* Buttons — 3 groups separated by dividers. Wraps on
                    narrow viewports so groups stay together. */}
                <div className="wd-actionbar-rows">
                  {/* Group A — social */}
                  <div className="wd-actionbar-group">
                    <button
                      onClick={handleLike}
                      disabled={likeLoading}
                      className={`wd-btn ${wallpaper.is_liked ? 'is-liked' : ''}`}
                      title={wallpaper.is_liked ? 'Unlike' : 'Like'}
                    >
                      {likeLoading
                        ? <AiOutlineLoading3Quarters size={14} className="animate-spin" />
                        : wallpaper.is_liked ? <AiFillHeart size={14} /> : <AiOutlineHeart size={14} />}
                      <span>{wallpaper.is_liked ? 'Liked' : 'Like'}</span>
                      <span className="wd-btn-count">{formatNumber(wallpaper.like_count)}</span>
                    </button>
                    <button
                      onClick={handleFavorite}
                      disabled={favLoading}
                      className={`wd-btn ${wallpaper.is_favorited ? 'is-favorited' : ''}`}
                      title={wallpaper.is_favorited ? 'Unfavorite' : 'Favorite'}
                    >
                      {favLoading
                        ? <AiOutlineLoading3Quarters size={14} className="animate-spin" />
                        : wallpaper.is_favorited ? <AiFillStar size={14} /> : <AiOutlineStar size={14} />}
                      <span>{wallpaper.is_favorited ? 'Saved' : 'Favorite'}</span>
                    </button>
                    <button
                      onClick={() => { if (!isAuthenticated) { navigate('/login'); return; } setShowAddToCollection(true); }}
                      className="wd-btn"
                      title="Add to a collection"
                    >
                      <MdPlaylistAdd size={16} />
                      <span>Add to list</span>
                    </button>
                  </div>

                  <div className="wd-actionbar-divider" />

                  {/* Group B — preview modes. Off paints just the wallpaper;
                      Plain / Home / Lock render the wallpaper inside the
                      matched-device chrome (frame + optional overlay).
                      Fullscreen is a sibling action. */}
                  <div className="wd-actionbar-group wd-actionbar-toggle">
                    {([
                      ['off',   'Wallpaper', 'Wallpaper only (no device chrome)'],
                      ['plain', 'Plain',     'Wallpaper inside the device — no overlay'],
                      ['home',  'Home',      'Device with dock + menu bar / app icons'],
                      ['lock',  'Lock',      'Device with clock + date'],
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
                    <button
                      onClick={() => {
                        if (frames.length > 1 || (wallpaper.file_type || '').startsWith('video/')) {
                          toast('Use the hero controls for video / dynamic previews', { icon: 'ℹ️' });
                          return;
                        }
                        setFullscreen(true);
                      }}
                      className="wd-btn wd-btn-icon"
                      title="Open fullscreen viewer"
                    >
                      <AiOutlineFullscreen size={15} />
                      <span className="hidden sm:inline">Fullscreen</span>
                    </button>
                  </div>

                  <div className="wd-actionbar-divider" />

                  {/* Group C — get */}
                  <div className="wd-actionbar-group">
                    {variants.length > 0 && (
                      <button
                        onClick={() => setDrawerOpen(true)}
                        className="wd-btn"
                        title="Browse all device sizes"
                      >
                        <MdDevices size={16} />
                        <span>Devices</span>
                        <span className="wd-btn-count">{variants.length}</span>
                      </button>
                    )}
                    <button
                      onClick={handleDownloadClick}
                      disabled={dlLoading}
                      className="wd-btn-cta"
                      title={isOwner ? 'Download original' : 'Trade coins for download'}
                    >
                      {dlLoading ? (
                        <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                      ) : dlDone ? (
                        <><AiOutlineCheckCircle size={15} /> {isOwner ? 'Got it' : 'Traded'}</>
                      ) : isOwner ? (
                        <><AiOutlineDownload size={15} /> Download</>
                      ) : (
                        <>
                          <span className="w-2 h-2 rounded-full bg-white shadow-[inset_0_-2px_0_oklch(80%_0.18_60),inset_0_1px_0_oklch(98%_0.04_60)]" aria-hidden />
                          Trade for {downloadCost || 1}
                        </>
                      )}
                    </button>
                  </div>
                </div>
              </div>
            </div>

            {/* ─── COIN CTA inline bar — confirm / success / insufficient ─── */}
            {(ctaState !== 'default') && (
              <div className="mt-5">
                {ctaState === 'success' ? (
                  <div
                    className="p-5 rounded-2xl"
                    style={{ background: 'oklch(95% 0.05 150)', border: '1px solid #2f6b3e', color: 'var(--color-ink)' }}
                  >
                    <div className="flex justify-between items-center gap-4 flex-wrap">
                      <div className="min-w-0">
                        <div className="kicker tracking-[0.14em] inline-flex items-center gap-1.5" style={{ color: '#2f6b3e' }}>
                          <AiOutlineCheckCircle size={11} /> DOWNLOADED
                        </div>
                        <div className="display text-[24px] sm:text-[28px] leading-tight mt-1.5" style={{ color: '#1f4827' }}>
                          wallpaper_<span className="mono text-[20px] sm:text-[24px]">{String(wallpaper.id).padStart(3, '0')}</span>.jpg
                        </div>
                        <div className="mono text-[10px] tracking-[0.14em] mt-2" style={{ color: '#2f6b3e' }}>
                          {fileSize}  ·  {userBalance} COINS REMAINING
                        </div>
                      </div>
                      <div className="flex flex-col gap-2 flex-shrink-0">
                        <button
                          onClick={handleSuccessDismiss}
                          className="inline-flex items-center justify-center gap-2 px-5 py-2.5 rounded-full bg-ink text-paper font-medium text-[12px] whitespace-nowrap hover:bg-ink-2 transition-colors"
                        >Done</button>
                        <Link
                          to="/"
                          className="inline-flex items-center justify-center gap-2 px-5 py-2 rounded-full border border-hair text-ink text-[12px] no-underline whitespace-nowrap hover:bg-paper-2 transition-colors"
                        >Browse more →</Link>
                      </div>
                    </div>
                    {!isMacUA && (
                      <>
                        <hr className="my-3.5 border-0" style={{ borderTop: '1px solid rgba(47,107,62,0.25)' }} />
                        <div className="flex flex-wrap gap-x-2 gap-y-1 items-center text-[12px]" style={{ color: '#1f4827' }}>
                          <span>🍎 On macOS? Use the menu-bar app to set this as your wallpaper in one click.</span>
                          <Link to="/download/mac" className="underline" style={{ color: '#2f6b3e' }}>Get it →</Link>
                        </div>
                      </>
                    )}
                  </div>
                ) : ctaState === 'insufficient' ? (
                  <div className="p-5 rounded-2xl border border-[#b07a1a]" style={{ background: 'oklch(96% 0.05 70)' }}>
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
                      <span><strong className="mono mr-1.5" style={{ color: '#9a6a18' }}>+1</strong>each upload</span>
                      <span><strong className="mono mr-1.5" style={{ color: '#9a6a18' }}>+1</strong>others download yours</span>
                    </div>
                  </div>
                ) : ctaState === 'confirm' ? (
                  <div className="bg-ink text-paper p-5 rounded-2xl" style={{ border: '2px solid var(--color-accent)' }}>
                    <div className="flex justify-between items-center gap-4 flex-wrap">
                      <div className="min-w-0">
                        <div className="kicker tracking-[0.14em] text-accent">CONFIRM EXCHANGE</div>
                        <div className="display text-[30px] sm:text-[36px] leading-none mt-1.5">
                          −{downloadCost} <span className="text-accent">coin{downloadCost > 1 ? 's' : ''}</span>
                        </div>
                        <div className="mono text-[10px] tracking-[0.14em] mt-2" style={{ color: 'rgba(255,255,255,0.55)' }}>
                          {userBalance} <span className="text-accent">→</span> {userBalance - downloadCost} COINS REMAINING
                        </div>
                        <Link
                          to="/upload"
                          className="mono text-[10px] tracking-[0.14em] mt-1.5 inline-flex items-center gap-1 no-underline transition-colors duration-200 hover:text-accent"
                          style={{ color: 'rgba(255,255,255,0.4)' }}
                        >
                          UPLOAD ONE TO REFILL <span aria-hidden>→</span>
                        </Link>
                      </div>
                      <div className="flex flex-col gap-2 flex-shrink-0">
                        <button
                          onClick={handleConfirmYes}
                          disabled={dlLoading}
                          className="inline-flex items-center justify-center gap-2 px-5 py-3 rounded-full text-white font-semibold text-[13px] disabled:opacity-60 whitespace-nowrap"
                          style={{ background: 'var(--color-accent)' }}
                        >
                          {dlLoading ? <AiOutlineLoading3Quarters size={14} className="animate-spin" /> : (
                            <>
                              <span className="w-2.5 h-2.5 rounded-full bg-white shadow-[inset_0_-2px_0_oklch(80%_0.18_60),inset_0_1px_0_oklch(98%_0.04_60)]" aria-hidden />
                              Yes, trade
                            </>
                          )}
                        </button>
                        <button
                          onClick={handleConfirmCancel}
                          disabled={dlLoading}
                          className="inline-flex items-center justify-center gap-2 px-5 py-2 rounded-full font-medium text-[12px] whitespace-nowrap transition-colors disabled:opacity-60"
                          style={{ background: 'transparent', color: 'rgba(255,255,255,0.85)', border: '1px solid rgba(255,255,255,0.18)' }}
                        >Cancel</button>
                      </div>
                    </div>
                    <hr className="my-3.5 border-0" style={{ borderTop: '1px solid rgba(255,255,255,0.12)' }} />
                    <label className="inline-flex items-center gap-2 text-[11px] cursor-pointer select-none" style={{ color: 'rgba(255,255,255,0.65)' }}>
                      <input
                        type="checkbox"
                        checked={confirmDontAsk}
                        onChange={(e) => setConfirmDontAsk(e.target.checked)}
                        className="appearance-none w-[13px] h-[13px] rounded-sm cursor-pointer checked:bg-accent transition-colors"
                        style={{ border: '1px solid rgba(255,255,255,0.4)' }}
                      />
                      Skip confirm next time
                    </label>
                  </div>
                ) : null}
              </div>
            )}

            {/* ─── Stats / Metadata / Palette / Recommendations ─────── */}
            <div className="wd-content-card mt-6">
              {/* Stats strip */}
              <div className="grid grid-cols-2 sm:grid-cols-4 divide-x divide-hair">
                {([
                  ['DOWNLOADS', wallpaper.download_count, engagements?.downloaders ?? []],
                  ['LIKES',     wallpaper.like_count,     engagements?.likers      ?? []],
                  ['FAVORITED', wallpaper.favorite_count, engagements?.favoriters  ?? []],
                  ['VIEWS',     wallpaper.view_count,     []                            ],
                ] as const).map(([k, v, users]) => (
                  <div key={k} className="px-4 py-3.5">
                    <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted">{k}</div>
                    <div className="display text-[22px] leading-none mt-1">{formatNumber(v)}</div>
                    {users.length > 0 && (
                      <AvatarStack users={users.slice(0, 5)} total={v} size={18} />
                    )}
                  </div>
                ))}
              </div>

              {/* Three even columns. The dim/res/file specs that used to
                  sit here are dropped — the action bar's meta strip
                  already shows them, so repeating them was waste.
                  What's left: who made it, what it's about, what it
                  looks like. Category gets a big serif headline, tags
                  become chips tinted by palette colors (so the same
                  tag doesn't fade into the page), uploader is its own
                  column with a generous avatar. */}
              <div className="border-t border-hair grid grid-cols-1 md:grid-cols-3 gap-x-8 gap-y-7 p-5 lg:p-6">
                {/* Uploader column */}
                {wallpaper.uploader ? (
                  <section className="min-w-0">
                    <div className="kicker text-muted mb-3">Uploaded by</div>
                    <Link
                      to={`/user/${wallpaper.uploader.username}`}
                      className="inline-flex items-center gap-3 no-underline text-ink group"
                    >
                      <div className="w-14 h-14 rounded-full overflow-hidden bg-paper-2 border border-hair flex items-center justify-center display text-[22px] flex-shrink-0">
                        {wallpaper.uploader.avatar_url
                          ? <img src={wallpaper.uploader.avatar_url} alt="" className="w-full h-full object-cover" />
                          : uploaderInitial}
                      </div>
                      <div className="min-w-0">
                        <div className="display text-[20px] leading-tight truncate group-hover:underline">@{wallpaper.uploader.username}</div>
                        {wallpaper.uploader.bio && (
                          <div className="mono text-[10px] tracking-[0.04em] text-muted truncate mt-1">{wallpaper.uploader.bio}</div>
                        )}
                        <div className="mono text-[10px] tracking-[0.14em] text-muted mt-1.5 inline-flex items-center gap-1">
                          VIEW PROFILE <span aria-hidden>→</span>
                        </div>
                      </div>
                    </Link>
                  </section>
                ) : <div />}

                {/* Category + Tags column — the "what is this about" axis.
                    Big serif headline for the category, tags below as
                    pill chips. Each tag tints itself using a different
                    palette color (rotated through the list) so the
                    chips have visual differentiation and reinforce the
                    wallpaper's palette without being noisy. */}
                <section className="min-w-0">
                  <div className="kicker text-muted mb-3">About</div>
                  {currentCategory ? (
                    <Link to={`/category/${currentCategory.slug}`} className="no-underline">
                      <h3 className="display text-[clamp(24px,2.4vw,30px)] leading-none tracking-[-0.01em] text-ink hover:text-accent transition-colors">
                        {currentCategory.name}
                      </h3>
                    </Link>
                  ) : (
                    <h3 className="display text-[clamp(22px,2vw,28px)] leading-none text-muted italic">Uncategorised</h3>
                  )}
                  {wallpaper.tags && wallpaper.tags.length > 0 && (
                    <div className="mt-4 flex flex-wrap gap-1.5">
                      {wallpaper.tags.map((t, i) => {
                        // Use the palette in rotation; fall back to muted ink
                        // when no palette is available.
                        const c = palette.length > 0 ? palette[i % palette.length] : 'var(--color-ink-2)';
                        return (
                          <span
                            key={t.id}
                            className="wd-tag-chip"
                            style={{
                              borderColor: c,
                              background: `color-mix(in oklch, ${c} 12%, var(--color-paper))`,
                              color: `color-mix(in oklch, ${c} 60%, var(--color-ink))`,
                            }}
                          >
                            <span className="wd-tag-chip-dot" style={{ background: c }} />
                            {t.name}
                          </span>
                        );
                      })}
                    </div>
                  )}
                </section>

                {/* Palette column */}
                {palette.length > 0 ? (
                  <section className="min-w-0">
                    <div className="kicker text-muted mb-3">Palette · click to copy</div>
                    <div className="grid gap-1.5" style={{ gridTemplateColumns: `repeat(${Math.min(palette.length, 5)}, 1fr)` }}>
                      {palette.map((c, i) => (
                        <button
                          key={`${c}-${i}`}
                          onClick={() => copyHex(c)}
                          className="flex flex-col gap-1 bg-transparent border-0 p-0 cursor-pointer text-left group"
                        >
                          <span
                            className="block h-[60px] rounded-lg border border-hair transition-transform group-hover:scale-[1.04] group-hover:shadow-md"
                            style={{ background: c }}
                            title={`${c.toUpperCase()} — click to copy`}
                          />
                          <span className="mono text-[10px] tracking-[0.06em] text-muted">{c.toUpperCase()}</span>
                        </button>
                      ))}
                    </div>
                    {wallpaper.dominant_color && (
                      <div className="mt-3 inline-flex items-center gap-2 mono text-[10px] tracking-[0.12em] uppercase text-muted">
                        <span className="inline-block w-3 h-3 rounded-sm border border-hair" style={{ background: wallpaper.dominant_color }} />
                        Dominant · {wallpaper.dominant_color.toUpperCase()}
                      </div>
                    )}
                  </section>
                ) : <div />}
              </div>
            </div>

            {/* ─── More like this — discover-style grid ─────────────── */}
            {similar.length > 0 && (
              <section className="mt-8">
                {(() => {
                  const cols = recCount / 2;
                  const capped = Math.min(similar.length, recCount);
                  const fullRows = Math.floor(capped / cols) * cols;
                  const shown = similar.slice(0, fullRows);
                  if (shown.length === 0) return null;
                  return (
                    <>
                      <div className="label-rule mb-4">More like this · {shown.length}</div>
                      <WallpaperGrid wallpapers={shown} viewMode="grid" sizeMode="md" />
                    </>
                  );
                })()}
              </section>
            )}

            {/* ─── Owner / report row ───────────────────────────────── */}
            <div className="flex justify-between items-center pt-5 mt-6 border-t border-hair/60 text-[12px] text-muted">
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
  const scale = Math.min(size.w / totalW, size.h / totalH) * 0.92;

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

function SpotlightStyles() {
  return (<style>{`
/* ── Outer blurred-wallpaper backdrop ────────────────────────── */
.wd-root { isolation: isolate; }
.wd-backdrop { position: absolute; inset: 0; z-index: 0; overflow: hidden; }
.wd-backdrop img { width: 100%; height: 100%; object-fit: cover; filter: blur(38px) saturate(1.4); transform: scale(1.18); }
.wd-backdrop-scrim { position: absolute; inset: 0; z-index: 0; background: linear-gradient(180deg, rgba(250,247,240,0.42) 0%, rgba(250,247,240,0.7) 100%); pointer-events: none; }

/* ── Stage panel — dominant-color mesh card holds hero + bar ── */
.wd-panel { position: relative; border-radius: 24px; padding: clamp(16px, 2vw, 24px); border: 1px solid rgba(255,255,255,0.4); box-shadow: 0 24px 56px -28px rgba(0,0,0,0.28), inset 0 1px 0 rgba(255,255,255,0.5); overflow: hidden; }

/* ── Hero card ─────────────────────────────────────────────── */
/* Transparent stage — visual chrome lives on the image / canvas inside,
   so a wide-short or tall-narrow image doesn't get padded out by an
   empty container background. */
.wd-hero { position: relative; width: 100%; display: flex; justify-content: center; align-items: center; }
.wd-hero-img { display: block; max-width: 100%; max-height: 64vh; width: auto; height: auto; object-fit: contain; border-radius: 18px; box-shadow: 0 18px 48px -18px rgba(0,0,0,0.32); border: 1px solid rgba(255,255,255,0.18); cursor: zoom-in; }
.wd-hero-canvas { position: relative; width: 100%; max-width: 1080px; max-height: 64vh; border-radius: 18px; overflow: hidden; box-shadow: 0 18px 48px -18px rgba(0,0,0,0.32); border: 1px solid rgba(255,255,255,0.18); }
.wd-hero-stage { position: relative; width: 100%; height: 64vh; }

/* ── Action bar ─────────────────────────────────────────────── */
.wd-actionbar { margin-top: clamp(14px, 1.6vw, 18px); padding: 14px clamp(12px, 1.6vw, 16px); background: rgba(250,247,240,0.82); backdrop-filter: blur(16px) saturate(1.2); border: 1px solid rgba(0,0,0,0.06); border-radius: 18px; box-shadow: 0 12px 32px -16px rgba(0,0,0,0.22); }
.wd-actionbar-meta { display: flex; align-items: baseline; gap: 12px; padding-bottom: 12px; border-bottom: 1px solid var(--color-hair); margin-bottom: 12px; flex-wrap: wrap; }
.wd-actionbar-meta .display { color: var(--color-ink); font-weight: 500; }
.wd-actionbar-pill { display: inline-flex; align-items: center; gap: 4px; padding: 2px 8px; border-radius: 999px; background: var(--color-ink); color: var(--color-accent); font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.14em; }
.wd-actionbar-pill.is-ai { background: oklch(50% 0.18 285); color: white; }
.wd-actionbar-rows { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.wd-actionbar-group { display: inline-flex; align-items: center; gap: 6px; flex-wrap: wrap; }
.wd-actionbar-divider { width: 1px; height: 28px; background: var(--color-hair); flex-shrink: 0; }
.wd-actionbar-toggle { background: var(--color-paper-2); padding: 3px; border-radius: 999px; border: 1px solid var(--color-hair); }

.wd-btn { display: inline-flex; align-items: center; gap: 7px; padding: 8px 14px; border-radius: 999px; border: 1px solid var(--color-hair); background: var(--color-paper); color: var(--color-ink); font-size: 12px; font-weight: 500; transition: background-color .15s ease, color .15s ease, border-color .15s ease; white-space: nowrap; }
.wd-btn:hover { background: var(--color-paper-2); border-color: var(--color-ink-2); }
.wd-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.wd-btn-icon { padding: 8px 12px; }
.wd-btn.is-liked { color: oklch(58% 0.20 25); border-color: oklch(58% 0.20 25); background: color-mix(in oklch, oklch(58% 0.20 25) 4%, var(--color-paper)); }
.wd-btn.is-favorited { color: oklch(70% 0.18 65); border-color: oklch(70% 0.18 65); background: color-mix(in oklch, oklch(70% 0.18 65) 5%, var(--color-paper)); }
.wd-btn-count { display: inline-flex; align-items: center; padding: 1px 6px; border-radius: 999px; background: var(--color-paper-2); color: var(--color-muted); font-family: var(--font-mono); font-size: 10px; margin-left: 2px; }

.wd-toggle-pill { padding: 6px 14px; border-radius: 999px; font-size: 12px; font-weight: 500; color: var(--color-muted); transition: all .15s ease; }
.wd-toggle-pill:hover { color: var(--color-ink-2); }
.wd-toggle-pill.is-on { background: var(--color-paper); color: var(--color-ink); box-shadow: 0 1px 3px rgba(0,0,0,0.08); }

.wd-btn-cta { display: inline-flex; align-items: center; gap: 8px; padding: 9px 18px; border-radius: 999px; background: var(--color-accent); color: white; font-size: 13px; font-weight: 600; white-space: nowrap; box-shadow: 0 6px 14px -6px oklch(72% 0.18 55 / 0.5); transition: filter .15s ease; }
.wd-btn-cta:hover { filter: brightness(1.05); }
.wd-btn-cta:disabled { opacity: 0.7; cursor: not-allowed; }

/* ── Content card (stats + meta + palette) ─────────────────── */
.wd-content-card { background: var(--color-paper); border: 1px solid var(--color-hair); border-radius: 20px; overflow: hidden; box-shadow: 0 8px 28px -16px rgba(0,0,0,0.16); }
.wd-tag-chip { display: inline-flex; align-items: center; gap: 5px; padding: 3px 10px 3px 8px; border-radius: 999px; font-size: 11px; font-weight: 500; border: 1px solid; line-height: 1.4; transition: transform .15s ease; }
.wd-tag-chip:hover { transform: translateY(-1px); }
.wd-tag-chip-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }

/* ── Devices drawer — right-side slide-in ──────────────────── */
.wd-drawer-scrim { position: fixed; inset: 0; background: rgba(20,18,15,0.42); backdrop-filter: blur(2px); z-index: 60; display: flex; justify-content: flex-end; animation: wdFadeIn .2s ease; }
.wd-drawer { width: 440px; max-width: 92vw; height: 100vh; background: var(--color-paper); display: flex; flex-direction: column; box-shadow: -20px 0 60px -20px rgba(0,0,0,0.28); border-left: 1px solid var(--color-hair); animation: wdSlideInRight .28s cubic-bezier(0.2,0.8,0.2,1); }
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
        aria-label={playing ? 'Pause video' : buffering ? 'Loading' : 'Play video'}
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
