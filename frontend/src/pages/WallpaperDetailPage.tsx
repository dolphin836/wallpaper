import { useState, useEffect, useMemo, useCallback, useRef } from 'react';
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
  AiOutlineEye,
} from 'react-icons/ai';
import { MdPlaylistAdd, MdDesktopMac, MdLaptopMac, MdTabletMac, MdPhoneIphone, MdOutlineRemoveRedEye, MdDevices } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User, Category } from '../types';
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
  // Spotlight-layout overlays. Drawer holds the full grouped
  // device list opened from the dock; the preview menu is the
  // little split-button popover (Fullscreen vs In-device).
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [previewMenuOpen, setPreviewMenuOpen] = useState(false);
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
  const canMockupMatched = useMemo(() => matchedVariant ? canShowMockup(matchedVariant) : false, [matchedVariant]);

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
    if (!fullscreen && !mockupVariant && !drawerOpen && !previewMenuOpen) return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (previewMenuOpen) { setPreviewMenuOpen(false); return; }
        if (drawerOpen) { setDrawerOpen(false); return; }
        setFullscreen(false);
        setMockupVariant(null);
      }
    };
    document.addEventListener('keydown', handleEsc);
    // Only lock body scroll for the true overlays. The drawer / popover
    // are within the page flow and don't need it.
    if (fullscreen || mockupVariant) document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', handleEsc);
      document.body.style.overflow = '';
    };
  }, [fullscreen, mockupVariant, drawerOpen, previewMenuOpen]);

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

      {/* Trade-success phosphor sweep — 800ms one-shot, keyed by the
          tick so successive trades re-run the animation cleanly. */}
      {tradeFlashTick > 0 && createPortal(
        <div key={tradeFlashTick} className="trade-flash" aria-hidden />,
        document.body,
      )}

      {/* Streaming-download progress modal. Indeterminate slide while
          the server prepares the file; then real percent once bytes
          start flowing. */}
      {dlLoading && createPortal(
        <div className="fixed inset-0 z-[80] flex items-center justify-center bg-black/45 px-6">
          <div className="w-full max-w-sm rounded-xl border border-hair bg-paper p-6 shadow-2xl">
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

      {/* Device mockup — wallpaper rendered inside a real device chassis */}
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

      {/* Fullscreen viewer — wheel-zoom, drag-pan, rotate. Preserved
          from the previous layout because the interaction is solid;
          only the affordance to enter it is now the centered hero. */}
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

      {/* Devices drawer — right-side slide-in with grouped per-device
          list. Opened from the dock "Devices · N ▾" button. Always
          shown grouped by platform so the user can scan a long list
          (12+) without scrolling through one giant flat array. */}
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
                const label = {
                  desktop: 'Desktop',
                  laptop: 'Laptop',
                  tablet: 'Tablet',
                  phone: 'Phone',
                  other: 'Other',
                }[platform];
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
                          <Icon size={18} className="text-ink-2 flex-shrink-0" />
                          <div className="min-w-0">
                            {v.device_slug ? (
                              <Link
                                to={`/wallpapers-for/${v.device_slug}`}
                                className="text-[13px] font-medium text-ink truncate no-underline hover:underline"
                              >
                                {deviceName}
                              </Link>
                            ) : (
                              <span className="text-[13px] font-medium text-ink truncate">{deviceName}</span>
                            )}
                            {isMatched && (
                              <span className="ml-1.5 mono text-[9px] tracking-[0.14em] px-1.5 py-[1px] bg-ink text-paper rounded">YOUR DEVICE</span>
                            )}
                            <div className="mono text-[10px] text-muted mt-0.5">
                              {v.width.toLocaleString()} × {v.height.toLocaleString()}
                              {v.file_size > 0 && <> · {formatFileSize(v.file_size)}</>}
                            </div>
                          </div>
                          <div className="flex items-center gap-1.5 flex-shrink-0">
                            <button
                              onClick={() => mockable && setMockupVariant(v)}
                              disabled={!mockable}
                              title={mockable ? 'Preview on device' : 'Mockup not available'}
                              className={`p-1.5 rounded-full ${mockable ? 'text-ink-2 hover:text-ink hover:bg-paper-2' : 'text-muted-2 cursor-not-allowed'}`}
                              aria-label="Preview on device"
                            >
                              <MdOutlineRemoveRedEye size={16} />
                            </button>
                            <button
                              onClick={() => handleDownload(v)}
                              disabled={dlLoading}
                              title="Download this variant"
                              className={`inline-flex items-center gap-1 px-3 py-1 rounded-full text-paper text-[11px] font-medium disabled:opacity-60 ${isMatched ? 'bg-accent' : 'bg-ink'}`}
                            >
                              <AiOutlineDownload size={12} /> Get
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

      <div className="bg-paper text-ink h-full flex flex-col min-h-0">
        {/* Modal-mode chrome — only when overlaid on top of another route.
            On the full-page route the Layout topbar already provides chrome. */}
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
          <div className="mx-auto max-w-[1400px] px-4 sm:px-6 lg:px-8 py-5 lg:py-6">

            {/* ─── SPOTLIGHT STAGE — hero on dominant-color mesh + dock ─── */}
            <div
              className="wd-stage"
              style={{
                background: wallpaper.dominant_color
                  ? `linear-gradient(135deg, ${wallpaper.dominant_color}, var(--color-paper))`
                  : 'linear-gradient(135deg, var(--color-paper-2), var(--color-paper))',
              }}
            >
              {/* Top-left: kicker (category · age · flags) */}
              <div className="wd-stage-tl">
                <div className="kicker text-paper/85">
                  {currentCategory?.name?.toUpperCase() || (wallpaper.tags?.[0]?.name.toUpperCase() ?? 'WALLPAPER')}
                  {' · ADDED '}{daysAgo}D AGO
                  {wallpaper.is_dynamic && ' · DYNAMIC'}
                  {wallpaper.is_ai_generated && ' · AI'}
                </div>
              </div>

              {/* Top-right: specs box */}
              <div className="wd-stage-tr">
                <div>
                  <div className="display text-[20px] leading-none">
                    {wallpaper.width.toLocaleString()}<span className="text-paper/55"> × </span>{wallpaper.height.toLocaleString()}
                  </div>
                  <div className="mono text-[10px] tracking-[0.14em] text-paper/70 mt-1.5">
                    {resLabel || '—'} · {(wallpaper.file_type || 'IMAGE').toUpperCase()} · {fileSize}
                  </div>
                </div>
              </div>

              {/* Centered hero — preserves the frames / video / image
                  branching from the previous layout. */}
              <div
                className="wd-hero"
                style={{
                  aspectRatio: wallpaper.width > 0 && wallpaper.height > 0
                    ? `${wallpaper.width} / ${wallpaper.height}`
                    : '16 / 9',
                  backgroundColor: wallpaper.dominant_color || undefined,
                }}
                onClick={() => {
                  // Only enter fullscreen if it's a still image (not video/frames)
                  if (frames.length > 1) return;
                  if ((wallpaper.file_type || '').startsWith('video/')) return;
                  setFullscreen(true);
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
                      onClick={(e) => { e.stopPropagation(); setFramePlaying((p) => !p); }}
                      className="absolute bottom-3 right-3 px-3 py-1 bg-black/60 text-white text-[11px] mono rounded backdrop-blur-sm"
                    >{framePlaying ? 'PAUSE' : 'PLAY'} · {frameIdx + 1}/{frames.length}</button>
                  </div>
                ) : (wallpaper.file_type || '').startsWith('video/') && wallpaper.original_url ? (
                  <VideoPlayer
                    src={wallpaper.preview_video_url || wallpaper.original_url}
                    poster={wallpaper.preview_url || wallpaper.thumb_url}
                  />
                ) : heroImg ? (
                  <>
                    <img
                      src={heroImg}
                      alt=""
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      className="w-full h-full object-contain select-none"
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                    <div className="wd-hero-hint">
                      <AiOutlineFullscreen size={12} /> Click to fullscreen
                    </div>
                  </>
                ) : null}
              </div>

              {/* Floating glass dock — primary surface. Uploader, palette,
                  social actions, Preview menu, Devices drawer button, CTA. */}
              <div className="wd-dock">
                {wallpaper.uploader && (
                  <Link
                    to={`/user/${wallpaper.uploader.username}`}
                    className="wd-dock-uploader no-underline text-inherit"
                    title={`@${wallpaper.uploader.username}`}
                  >
                    <div className="wd-dock-avatar">
                      {wallpaper.uploader.avatar_url
                        ? <img src={wallpaper.uploader.avatar_url} alt="" className="w-full h-full object-cover" />
                        : uploaderInitial}
                    </div>
                    <div className="min-w-0 hidden sm:block">
                      <div className="text-[13px] font-medium leading-tight truncate">@{wallpaper.uploader.username}</div>
                      {wallpaper.uploader.bio && (
                        <div className="mono text-[10px] text-muted truncate">{wallpaper.uploader.bio}</div>
                      )}
                    </div>
                  </Link>
                )}

                {palette.length > 0 && (
                  <>
                    <div className="wd-dock-divider" />
                    <div className="wd-dock-palette" title="Click to copy hex">
                      {palette.slice(0, 5).map((c, i) => (
                        <button
                          key={`${c}-${i}`}
                          onClick={() => copyHex(c)}
                          className="block w-5 h-5 rounded-md border border-hair p-0"
                          style={{ background: c }}
                          aria-label={`Copy ${c}`}
                        />
                      ))}
                    </div>
                  </>
                )}

                <div className="wd-dock-divider" />

                <button
                  onClick={handleLike}
                  disabled={likeLoading}
                  className={`wd-dock-icon ${wallpaper.is_liked ? 'is-liked' : ''}`}
                  title={wallpaper.is_liked ? 'Unlike' : 'Like'}
                  aria-label="Like"
                >
                  {likeLoading
                    ? <AiOutlineLoading3Quarters size={17} className="animate-spin" />
                    : wallpaper.is_liked ? <AiFillHeart size={17} /> : <AiOutlineHeart size={17} />}
                </button>
                <button
                  onClick={handleFavorite}
                  disabled={favLoading}
                  className={`wd-dock-icon ${wallpaper.is_favorited ? 'is-favorited' : ''}`}
                  title={wallpaper.is_favorited ? 'Unfavorite' : 'Favorite'}
                  aria-label="Favorite"
                >
                  {favLoading
                    ? <AiOutlineLoading3Quarters size={17} className="animate-spin" />
                    : wallpaper.is_favorited ? <AiFillStar size={17} /> : <AiOutlineStar size={17} />}
                </button>
                <button
                  onClick={() => { if (!isAuthenticated) { navigate('/login'); return; } setShowAddToCollection(true); }}
                  className="wd-dock-icon"
                  title="Add to collection"
                  aria-label="Add to collection"
                >
                  <MdPlaylistAdd size={19} />
                </button>

                <div className="wd-dock-divider" />

                {/* Preview split — Fullscreen vs In-device chrome */}
                <div className="wd-dock-pop">
                  <button
                    className="wd-dock-pill"
                    onClick={() => setPreviewMenuOpen((v) => !v)}
                    aria-expanded={previewMenuOpen}
                  >
                    <AiOutlineEye size={15} /> Preview <span className="opacity-50 text-[10px]">▾</span>
                  </button>
                  {previewMenuOpen && (
                    <>
                      {/* Scrim — outside-click close, without blocking the dock above */}
                      <div className="wd-popover-scrim" onClick={() => setPreviewMenuOpen(false)} />
                      <div className="wd-popover">
                        <button
                          onClick={() => {
                            setPreviewMenuOpen(false);
                            // Skip fullscreen for video / dynamic frames; the hero
                            // itself is the right surface for those.
                            if (frames.length > 1 || (wallpaper.file_type || '').startsWith('video/')) {
                              toast('Use the hero controls for video / dynamic previews', { icon: 'ℹ️' });
                              return;
                            }
                            setFullscreen(true);
                          }}
                        >
                          <AiOutlineFullscreen size={14} />
                          <span>
                            <strong>Fullscreen</strong>
                            <span>Just the image · ESC to close</span>
                          </span>
                        </button>
                        <button
                          onClick={() => {
                            setPreviewMenuOpen(false);
                            if (matchedVariant && canMockupMatched) {
                              setMockupVariant(matchedVariant);
                            } else {
                              toast('Pick a device from the drawer to preview', { icon: 'ℹ️' });
                              setDrawerOpen(true);
                            }
                          }}
                        >
                          <MdDesktopMac size={16} />
                          <span>
                            <strong>In device</strong>
                            <span>
                              {matchedVariant && canMockupMatched
                                ? `See it on ${matchedVariant.brand} ${matchedVariant.device_name}`
                                : 'Pick a device from the drawer'}
                            </span>
                          </span>
                        </button>
                      </div>
                    </>
                  )}
                </div>

                {variants.length > 0 && (
                  <button
                    onClick={() => setDrawerOpen(true)}
                    className="wd-dock-pill"
                    title="Browse all device sizes"
                  >
                    <MdDevices size={16} /> Devices · {variants.length} <span className="opacity-50 text-[10px]">▾</span>
                  </button>
                )}

                <div className="wd-dock-divider" />

                {/* CTA — same primary action button across all states. The
                    rich 4-state surface lives in the inline bar below; the
                    dock button stays small so the dock height never shifts. */}
                <button
                  onClick={handleDownloadClick}
                  disabled={dlLoading}
                  className="wd-dock-cta"
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

              {/* Quick-match card under the dock — one-tap download path
                  for the user's own device without opening the drawer. */}
              {matchedVariant && !isOwner && (
                <div className="wd-quickmatch">
                  <span className="kicker text-paper/70">YOUR DEVICE</span>
                  <div className="wd-quickmatch-card">
                    {(() => {
                      const Icon =
                        matchedVariant.platform === 'phone' ? MdPhoneIphone
                        : matchedVariant.platform === 'tablet' ? MdTabletMac
                        : matchedVariant.platform === 'laptop' ? MdLaptopMac
                        : MdDesktopMac;
                      return <Icon size={18} />;
                    })()}
                    <div className="min-w-0">
                      <div className="text-[12px] font-medium leading-tight truncate">
                        {[matchedVariant.brand, matchedVariant.device_name].filter(Boolean).join(' ').trim() || 'Your device'}
                      </div>
                      <div className="mono text-[10px] text-paper/65">
                        {matchedVariant.width}×{matchedVariant.height}
                        {matchedVariant.file_size > 0 && <> · {formatFileSize(matchedVariant.file_size)}</>}
                      </div>
                    </div>
                    <button
                      onClick={() => handleDownload(matchedVariant)}
                      disabled={dlLoading}
                      className="wd-quickmatch-dl"
                    >
                      <AiOutlineDownload size={13} /> Get
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* ─── COIN CTA INLINE BAR — rich 4-state surface ─────────
                Renders the confirm sheet, success message, and the
                insufficient-coin warning. Default state is intentionally
                blank because the dock CTA above already carries the
                "Trade for N" affordance. */}
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

            {/* ─── Stats strip — 4 metrics + avatar stacks ──────────── */}
            <div className="mt-7 grid grid-cols-2 sm:grid-cols-4 border border-hair border-r-0 rounded-lg overflow-hidden bg-paper">
              {([
                ['DOWNLOADS', wallpaper.download_count,  engagements?.downloaders ?? []],
                ['LIKES',     wallpaper.like_count,      engagements?.likers      ?? []],
                ['FAVORITED', wallpaper.favorite_count,  engagements?.favoriters  ?? []],
                ['VIEWS',     wallpaper.view_count,      []                            ],
              ] as const).map(([k, v, users]) => (
                <div key={k} className="px-4 py-3 border-r border-hair">
                  <div className="mono text-[9px] tracking-[0.14em] uppercase text-muted">{k}</div>
                  <div className="display text-[22px] sm:text-[24px] leading-none mt-1">{formatNumber(v)}</div>
                  {users.length > 0 && (
                    <AvatarStack users={users.slice(0, 5)} total={v} size={18} />
                  )}
                </div>
              ))}
            </div>

            {/* ─── Details row — Specs/Tags + extended palette ────────── */}
            <div className="mt-7 grid grid-cols-1 lg:grid-cols-[1.3fr_1fr] gap-6 lg:gap-10">
              <section>
                <div className="kicker text-muted">Specifications</div>
                <dl className="grid grid-cols-[100px_1fr] gap-y-2.5 mt-3 mono text-[13px]">
                  <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">DIM</dt>
                  <dd className="m-0 text-ink">{wallpaper.width.toLocaleString()} × {wallpaper.height.toLocaleString()} px</dd>
                  <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">RES</dt>
                  <dd className="m-0 text-ink">
                    {resLabel || '—'}
                    {(wallpaper.file_type || '').startsWith('video/') && (
                      <span className="ml-2 inline-flex items-center gap-1 px-1.5 py-0.5 text-[10px] font-semibold rounded bg-ink text-paper">
                        <svg width="9" height="9" viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
                        VIDEO
                      </span>
                    )}
                    {wallpaper.is_dynamic && <span className="ml-2 text-accent">● Dynamic</span>}
                    {wallpaper.is_ai_generated && <span className="ml-2 text-violet-600">✦ AI</span>}
                  </dd>
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
                  {currentCategory && (
                    <>
                      <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">CATEGORY</dt>
                      <dd className="m-0 text-ink">
                        <Link to={`/category/${currentCategory.slug}`} className="text-ink hover:underline">
                          {currentCategory.name}
                        </Link>
                      </dd>
                    </>
                  )}
                  {wallpaper.tags && wallpaper.tags.length > 0 && (
                    <>
                      <dt className="mono text-[10px] tracking-[0.12em] uppercase text-muted pt-0.5">TAGS</dt>
                      <dd className="m-0 text-ink">
                        <div className="flex flex-wrap gap-1.5">
                          {wallpaper.tags.map((t) => (
                            <span
                              key={t.id}
                              className="inline-block px-2 py-0.5 text-[11px] border border-hair rounded bg-paper-2 text-ink-2"
                            >
                              {t.name}
                            </span>
                          ))}
                        </div>
                      </dd>
                    </>
                  )}
                </dl>
              </section>

              {palette.length > 0 && (
                <section>
                  <div className="kicker text-muted">Palette · {palette.length} color{palette.length === 1 ? '' : 's'} · click to copy</div>
                  <div className="grid mt-3 gap-2" style={{ gridTemplateColumns: `repeat(${Math.min(palette.length, 5)}, 1fr)` }}>
                    {palette.map((c, i) => (
                      <button
                        key={`${c}-${i}`}
                        onClick={() => copyHex(c)}
                        className="flex flex-col gap-0 bg-transparent border-0 p-0 cursor-pointer text-left"
                      >
                        <span className="swatch block h-[64px] rounded-md border border-hair" style={{ background: c }} title={`${c.toUpperCase()} — click to copy`} />
                        <span className="swatch-hex">{c.toUpperCase()}</span>
                      </button>
                    ))}
                  </div>
                </section>
              )}
            </div>

            {/* ─── More like this ───────────────────────────────────── */}
            {similar.length > 0 && (
              <section className="mt-10">
                <div className="flex items-end justify-between mb-3">
                  <div className="label-rule flex-1">More like this · {similar.length}</div>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
                  {similar.slice(0, 8).map((s) => (
                    <WallpaperCard key={s.id} wallpaper={s} fixedAspect hideActions />
                  ))}
                </div>
              </section>
            )}

            {/* ─── Owner / report row ───────────────────────────────── */}
            <div className="flex justify-between items-center pt-6 mt-8 border-t border-hair text-[12px] text-muted">
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

/* Inline CSS for the Spotlight detail page. Kept here (rather than in
   index.css) so the classes are obviously local to this page; nothing
   outside WallpaperDetailPage uses them. The dev preview at
   /dev/wp-detail has its own copy of these styles via the demo file
   so the two pages can evolve independently. */
function SpotlightStyles() {
  return (<style>{`
.wd-stage { position: relative; border-radius: 22px; overflow: hidden; padding: clamp(28px, 4vw, 56px) clamp(20px, 3vw, 40px) 180px; min-height: 70vh; }
.wd-stage-tl { position: absolute; top: 22px; left: 28px; z-index: 3; max-width: 70%; }
.wd-stage-tl .kicker { color: rgba(255,255,255,0.9); }
.wd-stage-tr { position: absolute; top: 18px; right: 28px; z-index: 3; display: flex; align-items: flex-start; gap: 12px; background: rgba(20,18,15,0.45); backdrop-filter: blur(14px); border: 1px solid rgba(255,255,255,0.14); border-radius: 14px; padding: 12px 16px; color: white; }
.wd-hero { position: relative; max-width: 1080px; margin: 0 auto; border-radius: 16px; overflow: hidden; box-shadow: 0 30px 80px -20px rgba(0,0,0,0.45); border: 1px solid rgba(255,255,255,0.18); cursor: zoom-in; max-height: 70vh; }
.wd-hero > img, .wd-hero > div > img { width: 100%; height: 100%; object-fit: contain; display: block; }
.wd-hero-hint { position: absolute; top: 14px; right: 14px; display: inline-flex; gap: 5px; align-items: center; padding: 5px 10px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(8px); color: white; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.08em; border: 1px solid rgba(255,255,255,0.15); opacity: 0; transition: opacity .25s ease; pointer-events: none; }
.wd-hero:hover .wd-hero-hint { opacity: 1; }

.wd-dock { position: absolute; bottom: 92px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 10px; padding: 10px 14px; background: rgba(250,247,240,0.86); backdrop-filter: blur(18px) saturate(1.2); border: 1px solid rgba(0,0,0,0.06); border-radius: 999px; box-shadow: 0 24px 56px -18px rgba(0,0,0,0.42); max-width: calc(100% - 40px); flex-wrap: nowrap; overflow-x: auto; scrollbar-width: none; }
.wd-dock::-webkit-scrollbar { display: none; }
.wd-dock-uploader { display: flex; align-items: center; gap: 10px; min-width: 0; flex-shrink: 0; }
.wd-dock-avatar { width: 34px; height: 34px; border-radius: 50%; overflow: hidden; background: var(--color-paper-2); border: 1px solid var(--color-hair); display: flex; align-items: center; justify-content: center; font-family: var(--font-display); font-size: 14px; flex-shrink: 0; }
.wd-dock-divider { width: 1px; height: 26px; background: var(--color-hair); flex-shrink: 0; }
.wd-dock-palette { display: flex; gap: 4px; flex-shrink: 0; }
.wd-dock-icon { padding: 8px; border-radius: 999px; color: var(--color-ink-2); display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; transition: background-color .15s ease, color .15s ease; }
.wd-dock-icon:hover { background: var(--color-paper-2); color: var(--color-accent); }
.wd-dock-icon.is-liked { color: oklch(58% 0.20 25); }
.wd-dock-icon.is-favorited { color: oklch(72% 0.18 65); }
.wd-dock-pill { display: inline-flex; align-items: center; gap: 6px; padding: 8px 14px; border-radius: 999px; border: 1px solid var(--color-hair); background: var(--color-paper); font-size: 12px; font-weight: 500; color: var(--color-ink); flex-shrink: 0; white-space: nowrap; }
.wd-dock-pill:hover { background: var(--color-paper-2); }
.wd-dock-cta { display: inline-flex; align-items: center; gap: 8px; padding: 10px 18px; border-radius: 999px; background: var(--color-ink); color: var(--color-paper); font-size: 13px; font-weight: 600; flex-shrink: 0; white-space: nowrap; }
.wd-dock-cta:hover { background: var(--color-ink-2); }
.wd-dock-cta:disabled { opacity: 0.7; cursor: not-allowed; }

.wd-dock-pop { position: relative; flex-shrink: 0; }
.wd-popover-scrim { position: fixed; inset: 0; z-index: 40; background: transparent; }
.wd-popover { position: absolute; bottom: calc(100% + 10px); left: 50%; transform: translateX(-50%); width: 260px; background: var(--color-paper); border: 1px solid var(--color-hair); border-radius: 14px; box-shadow: 0 20px 50px -16px rgba(0,0,0,0.32); padding: 6px; z-index: 50; }
.wd-popover button { width: 100%; display: flex; align-items: flex-start; gap: 10px; padding: 10px 12px; border-radius: 10px; text-align: left; color: var(--color-ink); }
.wd-popover button:hover { background: var(--color-paper-2); }
.wd-popover button strong { display: block; font-size: 13px; font-weight: 600; margin-bottom: 2px; }
.wd-popover button span span { display: block; font-family: var(--font-mono); font-size: 10px; color: var(--color-muted); letter-spacing: 0.04em; line-height: 1.3; }

.wd-quickmatch { position: absolute; bottom: 22px; left: 50%; transform: translateX(-50%); display: flex; align-items: center; gap: 12px; color: white; max-width: calc(100% - 40px); }
.wd-quickmatch-card { display: inline-flex; align-items: center; gap: 10px; padding: 8px 12px 8px 14px; border-radius: 999px; background: rgba(20,18,15,0.55); backdrop-filter: blur(12px); border: 1px solid var(--color-accent); color: white; min-width: 0; }
.wd-quickmatch-dl { display: inline-flex; align-items: center; gap: 4px; padding: 5px 12px; border-radius: 999px; background: var(--color-accent); color: white; font-size: 11px; font-weight: 600; flex-shrink: 0; }
.wd-quickmatch-dl:disabled { opacity: 0.6; }

/* Devices drawer — right-side slide-in */
.wd-drawer-scrim { position: fixed; inset: 0; background: rgba(20,18,15,0.42); backdrop-filter: blur(2px); z-index: 60; display: flex; justify-content: flex-end; animation: wdFadeIn .2s ease; }
.wd-drawer { width: 440px; max-width: 92vw; height: 100vh; background: var(--color-paper); display: flex; flex-direction: column; box-shadow: -20px 0 60px -20px rgba(0,0,0,0.28); border-left: 1px solid var(--color-hair); animation: wdSlideInRight .28s cubic-bezier(0.2,0.8,0.2,1); }
.wd-drawer-head { padding: 22px 22px 16px; border-bottom: 1px solid var(--color-hair); display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; flex-shrink: 0; }
.wd-drawer-body { flex: 1; overflow-y: auto; padding: 6px 18px 18px; }
.wd-drawer-foot { padding: 12px 22px; border-top: 1px solid var(--color-hair); background: var(--color-paper-2); flex-shrink: 0; }
.wd-drawer-group { margin-top: 14px; }
.wd-drawer-grouphead { display: flex; justify-content: space-between; align-items: baseline; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--color-muted); padding: 0 6px 6px; border-bottom: 1px solid var(--color-hair); margin-bottom: 6px; }
.wd-drawer-row { display: grid; grid-template-columns: 22px 1fr auto; gap: 12px; align-items: center; padding: 10px 6px; border-radius: 8px; transition: background-color .15s ease; }
.wd-drawer-row:hover { background: var(--color-paper-2); }
.wd-drawer-row.is-matched { background: color-mix(in oklch, var(--color-accent) 5%, var(--color-paper)); }

@keyframes wdSlideInRight { from { transform: translateX(20px); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
@keyframes wdFadeIn { from { opacity: 0; } to { opacity: 1; } }

@media (max-width: 640px) {
  .wd-stage-tl, .wd-stage-tr { left: 16px; right: 16px; }
  .wd-stage-tr { padding: 10px 12px; }
  .wd-dock { padding: 8px 10px; gap: 8px; }
  .wd-dock-uploader > div { display: none; }
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
