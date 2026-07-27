import { useState, useEffect, useLayoutEffect, useMemo, useCallback, useRef } from 'react';
import { createPortal } from 'react-dom';
import { useParams, Link, useNavigate, useLocation } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import {
  AiOutlineLeft,
  AiOutlineRight,
  AiOutlineInfoCircle,
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineFullscreen,
  AiOutlineClose,
  AiOutlineLoading3Quarters,
  AiOutlineZoomIn,
  AiOutlineZoomOut,
  AiOutlineRedo,
  AiOutlineReload,
  AiOutlineDown,
} from 'react-icons/ai';
import { MdPlaylistAdd, MdDesktopMac, MdLaptopMac, MdTabletMac, MdPhoneIphone, MdOutlineRemoveRedEye, MdDevices, MdPlayArrow, MdPause } from 'react-icons/md';
import toast from 'react-hot-toast';
import { useTranslation, Trans } from 'react-i18next';
import type { Wallpaper, WallpaperDetail, WallpaperVariant, Engagements, User } from '../types';
import DeviceMockup, { canShowMockup } from '../components/DeviceMockup';
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
  downloadWallpaper,
  getMyCoins,
  getWallpaperVariants,
  getWallpaperEngagements,
} from '../api';
import { useAuthStore } from '../store/auth';
import EmptyState from '../components/EmptyState';
import ErrorState from '../components/ErrorState';
import AvatarStack from '../components/AvatarStack';
import AddToCollectionModal from '../components/AddToCollectionModal';
import useProtectedImageBlob from '../hooks/useProtectedImageBlob';
import { isMacDynamicWallpaper } from '../lib/wallpaperType';
import {
  wallpaperDetailPath,
  type WallpaperDetailLocationState,
} from '../lib/wallpaperDetailNavigation';

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

function toDetailSnapshot(wallpaper: Wallpaper): WallpaperDetail {
  return {
    ...wallpaper,
    tags: [],
    uploader: undefined as unknown as User,
  };
}

function matchesDetailRoute(wallpaper: Wallpaper, routeId: string): boolean {
  return wallpaper.slug === routeId || String(wallpaper.id) === routeId;
}

const DRAWER_PLATFORMS = ['desktop', 'laptop', 'tablet', 'phone', 'other'] as const;
type DrawerPlatform = (typeof DRAWER_PLATFORMS)[number];
const EMPTY_NAVIGATION_ITEMS: Wallpaper[] = [];

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
  const detailState = location.state as WallpaperDetailLocationState | null;
  const initialWallpaper = detailState?.initialWallpaper;
  const detailScrollRef = useRef<HTMLDivElement>(null);

  // Hide only the scrollbar chrome while this route is mounted. The document
  // remains scrollable for direct detail URLs, and modal details keep using
  // their own scroll container below, so the recommendation screen is still
  // reached normally with wheel, trackpad, touch, or keyboard input.
  useEffect(() => {
    const root = document.documentElement;
    root.classList.add('wd-detail-scrollbar-hidden');
    return () => root.classList.remove('wd-detail-scrollbar-hidden');
  }, []);

  // Hydrate from list snapshot so the preview renders immediately; uploader/tags are filled in by the detail fetch.
  const [wallpaper, setWallpaper] = useState<WallpaperDetail | null>(() =>
    initialWallpaper
      ? toDetailSnapshot(initialWallpaper)
      : null
  );
  const metaTitle = wallpaper ? t('meta.title', { res: `${wallpaper.width}×${wallpaper.height}` }) : t('meta.titleFallback');
  const metaDescription = wallpaper
    ? t(wallpaper.is_dynamic ? 'meta.descriptionDynamic' : 'meta.description', { res: `${wallpaper.width}×${wallpaper.height}` })
    : undefined;
  const metaImage = wallpaper?.preview_url || wallpaper?.thumb_url;
  const jsonLd = wallpaper
    ? {
        '@context': 'https://schema.org',
        '@type': 'ImageObject',
        name: metaTitle,
        contentUrl: wallpaper.preview_url || wallpaper.thumb_url,
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
  const [variantsLoading, setVariantsLoading] = useState(true);
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
  // The actual original image stays mounted above the list preview while
  // it loads. Once decoded, opacity cross-fades it in without ever removing
  // the preview underneath, avoiding the one-frame blank flash caused by
  // swapping a single <img>'s src. The same load also warms the HTTP cache
  // for downloads. Videos and dynamic wallpapers stay ungated.
  const [readyOriginalURL, setReadyOriginalURL] = useState('');
  const [failedOriginalURL, setFailedOriginalURL] = useState('');
  const heroMediaRef = useRef<HTMLDivElement>(null);
  const [heroCanCover, setHeroCanCover] = useState(false);
  const [heroContainedSize, setHeroContainedSize] = useState({ width: 0, height: 0 });
  const heroSourceId = wallpaper?.id;
  const isVideoWallpaper = (wallpaper?.file_type || '').startsWith('video/');
  const isMacDynamic = isMacDynamicWallpaper(wallpaper);
  const protectedOriginalSource = wallpaper?.original_url && !isVideoWallpaper && !wallpaper.is_dynamic
    ? wallpaper.original_url
    : '';
  const {
    blobURL: originalBlobURL,
    loading: originalBlobLoading,
    failed: originalBlobFailed,
  } = useProtectedImageBlob(protectedOriginalSource);
  const fullscreenVisible = fullscreen && !isVideoWallpaper && !isMacDynamic;
  const originalSourceWidth = wallpaper?.width ?? 0;
  const originalSourceHeight = wallpaper?.height ?? 0;
  // The browser displays derived HEIC frames at up to 1600px wide. Video
  // posters now preserve the served video's full dimensions, so their fit
  // calculation uses the original width/height directly.
  const derivedScale = wallpaper?.is_dynamic && originalSourceWidth > 0
    ? Math.min(1, 1600 / originalSourceWidth)
    : 1;
  const heroSourceWidth = Math.round(originalSourceWidth * derivedScale);
  const heroSourceHeight = Math.round(originalSourceHeight * derivedScale);
  const originalReady = !!originalBlobURL && readyOriginalURL === originalBlobURL;
  const originalFailed = !!protectedOriginalSource
    && (originalBlobFailed || failedOriginalURL === protectedOriginalSource);
  const needsOriginalLoad = !!protectedOriginalSource;
  const downloadReady = !!wallpaper && (!needsOriginalLoad || originalReady || originalFailed);
  const markOriginalDecoded = (image: HTMLImageElement, url: string) => {
    void image.decode()
      .catch(() => undefined)
      .finally(() => setReadyOriginalURL(url));
  };

  // Keep the immersive cover treatment only when the original has enough
  // pixels to fill the live hero box without being enlarged. Smaller images
  // use object-fit: scale-down, which preserves their intrinsic size (or only
  // shrinks them when necessary) and centres them in the available space.
  useLayoutEffect(() => {
    const media = heroMediaRef.current;
    if (loading || !media || !heroSourceId) {
      setHeroCanCover(false);
      setHeroContainedSize({ width: 0, height: 0 });
      return;
    }

    const updateFit = () => {
      const { width: containerWidth, height: containerHeight } = media.getBoundingClientRect();
      setHeroCanCover(
        heroSourceWidth >= Math.ceil(containerWidth) && heroSourceHeight >= Math.ceil(containerHeight),
      );
      const containedScale = Math.min(
        1,
        containerWidth / Math.max(1, heroSourceWidth),
        containerHeight / Math.max(1, heroSourceHeight),
      );
      setHeroContainedSize({
        width: Math.round(heroSourceWidth * containedScale),
        height: Math.round(heroSourceHeight * containedScale),
      });
    };

    updateFit();
    const observer = new ResizeObserver(updateFit);
    observer.observe(media);
    return () => observer.disconnect();
  }, [loading, heroSourceId, heroSourceWidth, heroSourceHeight]);

  // Toolbar overlays. Drawer holds the grouped device list (opened
  // from the toolbar's Devices · N button).
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [expandedDrawerPlatform, setExpandedDrawerPlatform] = useState<DrawerPlatform | null>(null);
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
  const matchedDrawerPlatform = useMemo<DrawerPlatform | null>(() => {
    if (!matchedVariant) return null;
    return DRAWER_PLATFORMS.includes(matchedVariant.platform as DrawerPlatform)
      ? matchedVariant.platform as DrawerPlatform
      : 'other';
  }, [matchedVariant]);

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

    let cancelled = false;
    const snapshot = initialWallpaper && matchesDetailRoute(initialWallpaper, id)
      ? initialWallpaper
      : null;

    // Route changes intentionally reset the full detail state machine before
    // the fresh request starts; keeping any drawer or transform state would
    // leak controls from the previous wallpaper into the next one.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setError(false);
    setVariants([]);
    setVariantsLoading(true);
    setEngagements(null);
    setFrameIdx(0);
    setFramePlaying(true);
    setFullscreen(false);
    setMockupVariant(null);
    setDrawerOpen(false);
    setInfoOpen(false);
    setShowAddToCollection(false);
    setReadyOriginalURL('');
    setFailedOriginalURL('');
    detailScrollRef.current?.scrollTo({ top: 0, behavior: 'auto' });

    if (snapshot) {
      setWallpaper(toDetailSnapshot(snapshot));
      setDlDone(snapshot.is_downloaded ?? false);
      setLoading(false);
    } else {
      setWallpaper(null);
      setLoading(true);
    }

    getWallpaper(id)
      .then((wpRes) => {
        if (cancelled) return;
        const wp = wpRes.data.data;
        setWallpaper(wp);
        setDlDone(wp.is_downloaded ?? false);

        getWallpaperVariants(wp.id)
          .then((varRes) => {
            if (!cancelled) setVariants(varRes.data.data || []);
          })
          .catch(() => { /* variants optional */ })
          .finally(() => {
            if (!cancelled) setVariantsLoading(false);
          });
        getWallpaperEngagements(wp.id)
          .then((res) => {
            if (!cancelled) setEngagements(res.data.data);
          })
          .catch(() => { /* non-critical */ });
      })
      .catch((e) => {
        if (!cancelled) {
          setVariantsLoading(false);
          if (!snapshot && e?.response?.status !== 404) setError(true);
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [id, initialWallpaper]);

  useEffect(() => {
    if (!fullscreenVisible && !mockupVariant && !drawerOpen) return;
    const handleEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (drawerOpen) { setDrawerOpen(false); return; }
        setFullscreen(false);
        setMockupVariant(null);
      }
    };
    document.addEventListener('keydown', handleEsc);
    if (fullscreenVisible || mockupVariant) document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', handleEsc);
      document.body.style.overflow = '';
    };
  }, [fullscreenVisible, mockupVariant, drawerOpen]);

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

  const navigationItems = detailState?.detailNavigation?.items ?? EMPTY_NAVIGATION_ITEMS;
  const navigationIndex = useMemo(() => {
    if (!id) return -1;
    return navigationItems.findIndex((item) => matchesDetailRoute(item, id));
  }, [id, navigationItems]);
  const previousWallpaper = navigationIndex > 0
    ? navigationItems[navigationIndex - 1]
    : null;
  const nextWallpaper = navigationIndex >= 0 && navigationIndex < navigationItems.length - 1
    ? navigationItems[navigationIndex + 1]
    : null;

  const navigateWithinDetails = useCallback((target: Wallpaper | null) => {
    if (!target) return;
    setWallpaper(toDetailSnapshot(target));
    setDlDone(target.is_downloaded ?? false);
    setLoading(false);
    setError(false);
    navigate(wallpaperDetailPath(target), {
      replace: Boolean(detailState?.background),
      state: {
        ...detailState,
        initialWallpaper: target,
      },
    });
  }, [detailState, navigate]);

  const handleLike = async () => {
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper || likeLoading) return;
    const targetId = wallpaper.id;
    setLikeLoading(true);
    try {
      if (wallpaper.is_liked) {
        await unlikeWallpaper(targetId);
        setWallpaper((current) => current?.id === targetId
          ? { ...current, is_liked: false, like_count: Math.max(0, current.like_count - 1) }
          : current);
      } else {
        await likeWallpaper(targetId);
        setWallpaper((current) => current?.id === targetId
          ? { ...current, is_liked: true, like_count: current.like_count + 1 }
          : current);
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
    const targetId = wallpaper.id;
    setFavLoading(true);
    try {
      if (wallpaper.is_favorited) {
        await unfavoriteWallpaper(targetId);
        setWallpaper((current) => current?.id === targetId
          ? { ...current, is_favorited: false, favorite_count: Math.max(0, current.favorite_count - 1) }
          : current);
      } else {
        await favoriteWallpaper(targetId);
        setWallpaper((current) => current?.id === targetId
          ? { ...current, is_favorited: true, favorite_count: current.favorite_count + 1 }
          : current);
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
    if (dlLoading || !downloadReady) return;
    if (!isAuthenticated) { navigate('/login'); return; }
    if (!wallpaper) return;
    const targetId = wallpaper.id;
    const isOwnerDl = user?.id === wallpaper.user_id;
    setDlLoading(true);
    try {
      const url = downloadWallpaper(targetId);
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
      // No streamed progress: after the hero displayed the original the
      // bytes come straight from the HTTP cache.
      const blob = await resp.blob();
      const blobUrl = URL.createObjectURL(blob);
      const ext = finalUrl.split('.').pop()?.split('?')[0] || 'jpg';
      const filename = `wallpaper_${wallpaper.id}_${wallpaper.width}x${wallpaper.height}.${ext}`;
      const a = document.createElement('a');
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(blobUrl);
      setWallpaper((current) => current?.id === targetId
        ? { ...current, download_count: current.download_count + 1 }
        : current);
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
    }
  };

  if (loading) {
    return (
      <WallpaperDetailLoading
        title={metaTitle}
        onBack={() => { if (window.history.length > 1) navigate(-1); else navigate('/'); }}
      />
    );
  }
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
  const heroImg = wallpaper.preview_url || wallpaper.thumb_url || originalBlobURL;
  const originalHeroImg = !(wallpaper.file_type || '').startsWith('video/')
    && !wallpaper.is_dynamic
    && originalBlobURL
    && originalBlobURL !== heroImg
      ? originalBlobURL
      : '';
  const fileSize = wallpaper.file_size > 0 ? formatFileSize(wallpaper.file_size) : '—';
  const downloadCost = isOwner ? 0 : 1;
  const userBalance = user?.coins ?? 0;
  const isMacUA = /Macintosh|Mac OS X/i.test(navigator.userAgent);
  const devicePreviewUnavailable = isVideoWallpaper || isMacDynamic;
  const devicePreviewDisabled = devicePreviewUnavailable
    || variantsLoading
    || variants.length === 0
    || !downloadReady;

  const ctaState = ctaMode;

  const handleDownloadClick = () => {
    if (!downloadReady) return;
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

      {tradeFlashTick > 0 && createPortal(
        <div key={tradeFlashTick} className="trade-flash" aria-hidden />,
        document.body,
      )}

      {/* Download progress is rendered below the preview, matching the
          macOS detail page. */}

      {mockupVariant && wallpaper && (
        <DeviceMockup
          imageUrl={mockupVariant.url || originalBlobURL || wallpaper.preview_url || wallpaper.thumb_url}
          platform={mockupVariant.platform}
          deviceName={`${mockupVariant.brand} ${mockupVariant.device_name}`}
          deviceWidth={mockupVariant.width}
          deviceHeight={mockupVariant.height}
          dominantColor={wallpaper.dominant_color}
          onClose={() => setMockupVariant(null)}
        />
      )}

      {fullscreenVisible && createPortal(
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
            src={matchedVariant?.url || originalBlobURL || wallpaper.preview_url || wallpaper.thumb_url}
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
              {DRAWER_PLATFORMS.map((platform) => {
                const list = groupedVariants[platform];
                if (!list || list.length === 0) return null;
                const label = t(`drawer.platform.${platform}`);
                const isExpanded = expandedDrawerPlatform === platform;
                const triggerId = `wd-drawer-trigger-${platform}`;
                const panelId = `wd-drawer-panel-${platform}`;
                return (
                  <div key={platform} className="wd-drawer-group">
                    <button
                      id={triggerId}
                      type="button"
                      className="wd-drawer-grouphead"
                      aria-expanded={isExpanded}
                      aria-controls={panelId}
                      onClick={() => setExpandedDrawerPlatform((current) => current === platform ? null : platform)}
                    >
                      <span>{label}</span>
                      <span className="wd-drawer-groupmeta">
                        <span className="mono text-[10px] tracking-[0.14em] text-muted normal-case">{list.length}</span>
                        <AiOutlineDown className="wd-drawer-groupchevron" size={13} aria-hidden />
                      </span>
                    </button>
                    <div
                      id={panelId}
                      role="region"
                      aria-labelledby={triggerId}
                      aria-hidden={!isExpanded}
                      className={`wd-drawer-groupcontent ${isExpanded ? 'is-open' : ''}`}
                    >
                      <div className="wd-drawer-groupitems">
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
                                  disabled={dlLoading || !downloadReady}
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
                    </div>
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

        <div ref={detailScrollRef} className="wd-detail-scroll flex-1 min-h-0 overflow-y-auto relative z-10">

          {/* ═══ SCREEN 1 — immersive hero (mirrors the Mac detail page):
              full-bleed wallpaper, back circle top-left, info circle +
              panel top-right, glass toolbar bottom-centre. ═══ */}
          <section className="wd-s1">
            <div ref={heroMediaRef} className="wd-s1-media" style={{ backgroundColor: wallpaper.dominant_color || undefined }}>
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
                      className={`absolute inset-0 w-full h-full ${heroCanCover ? 'object-cover' : 'object-scale-down'} select-none transition-opacity duration-500 ${frameIdx === i ? 'opacity-100' : 'opacity-0'}`}
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                  ))}
                </>
              ) : isVideoWallpaper && wallpaper.original_url ? (
                <div className="absolute inset-0 flex items-center justify-center">
                  <div
                    className={heroCanCover ? 'w-full h-full' : 'shrink-0'}
                    style={heroCanCover ? undefined : heroContainedSize}
                  >
                    <VideoPlayer
                      src={wallpaper.original_url}
                      thumb={wallpaper.thumb_url}
                      preview={wallpaper.preview_url}
                      poster={wallpaper.poster_url}
                    />
                  </div>
                </div>
              ) : heroImg ? (
                <div className="absolute inset-0 flex items-center justify-center">
                  <div
                    className={`wd-s1-image-canvas ${heroCanCover ? 'w-full h-full' : 'shrink-0'}`}
                    style={heroCanCover ? undefined : heroContainedSize}
                  >
                    <img
                      src={heroImg}
                      alt=""
                      loading="eager"
                      decoding="async"
                      fetchPriority="high"
                      onLoad={(event) => {
                        if (heroImg === originalBlobURL) markOriginalDecoded(event.currentTarget, heroImg);
                      }}
                      onError={() => {
                        if (heroImg === originalBlobURL) setFailedOriginalURL(protectedOriginalSource);
                      }}
                      onContextMenu={(e) => e.preventDefault()}
                      draggable={false}
                      className={`wd-s1-img wd-s1-img-preview ${originalReady ? 'is-upgraded' : ''}`}
                      style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                    />
                    {originalHeroImg && (
                      <img
                        src={originalHeroImg}
                        alt=""
                        aria-hidden
                        loading="eager"
                        decoding="async"
                        fetchPriority="high"
                        onLoad={(event) => markOriginalDecoded(event.currentTarget, originalHeroImg)}
                        onError={() => setFailedOriginalURL(protectedOriginalSource)}
                        onContextMenu={(e) => e.preventDefault()}
                        draggable={false}
                        className={`wd-s1-img wd-s1-img-original ${originalReady ? 'is-ready' : ''}`}
                        style={{ WebkitUserDrag: 'none' } as React.CSSProperties}
                      />
                    )}
                    {needsOriginalLoad && (originalBlobLoading || !originalReady) && !originalFailed && (
                      <span className="wd-s1-loading-glow" aria-hidden />
                    )}
                  </div>
                </div>
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
                className="wd-circle-btn glass-bounce"
                onClick={() => setInfoOpen((v) => !v)}
                aria-label="info"
              >
                <AiOutlineInfoCircle size={18} />
              </button>
              {infoOpen && (
                <div className="wd-info-panel">
                  {wallpaper.uploader && (
                    <Link to={`/user/${wallpaper.uploader.username}`} className="wd-ip-row avatar-shell no-underline">
                      <span className="avatar-btn wd-ip-avatar-btn">
                        {wallpaper.uploader.avatar_url
                          ? <img src={wallpaper.uploader.avatar_url} alt="" decoding="async" className="avatar-img" />
                          : <span className="avatar-img avatar-img--fallback">{uploaderInitial}</span>}
                      </span>
                      <div className="wd-ip-user-copy">
                        <div className="wd-ip-user-line">
                          <span className="wd-ip-username">@{wallpaper.uploader.username}</span>
                          <span className="wd-ip-coins">{formatNumber(wallpaper.uploader.coins ?? 0)}</span>
                        </div>
                        <div className="wd-ip-bio" title={wallpaper.uploader.bio || undefined}>
                          {wallpaper.uploader.bio || '\u00A0'}
                        </div>
                      </div>
                    </Link>
                  )}

                  <div className="wd-ip-block">
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

                </div>
              )}
            </div>

            {/* Bottom-centre column: progress / notices / glass toolbar. */}
            <div className="wd-s1-bottom">
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

              {/* Bottom-centre glass toolbar: meta | social | navigation | preview | get */}
              <div className="wd-bar">
                <div className="wd-bar-meta">
                  <span className="text-[13px] font-semibold text-white leading-none whitespace-nowrap">
                    {wallpaper.width.toLocaleString()} × {wallpaper.height.toLocaleString()}
                  </span>
                  <span className="wd-bar-meta-secondary mono text-[10px] tracking-[0.04em] text-white/65 whitespace-nowrap">
                    <span className="wd-bar-meta-secondary-main">
                      {resLabel || '—'} · {(wallpaper.file_type || 'IMAGE').toUpperCase()} · {fileSize}
                    </span>
                    {(wallpaper.is_dynamic || isVideoWallpaper) && (
                      <span className="wd-bar-meta-secondary-flag"> · {t('pill.live')}</span>
                    )}
                    {wallpaper.is_ai_generated && (
                      <span className="wd-bar-meta-secondary-flag"> · AI</span>
                    )}
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

                <div className="wd-bar-nav" role="group" aria-label={t('navigation.group')}>
                  <button
                    type="button"
                    onClick={() => navigateWithinDetails(previousWallpaper)}
                    disabled={!previousWallpaper}
                    className="wd-btn wd-bar-nav-btn"
                    title={t('navigation.previous')}
                    aria-label={t('navigation.previous')}
                  >
                    <AiOutlineLeft size={15} />
                    <span className="wd-bar-hidesm">{t('navigation.previousShort')}</span>
                  </button>
                  <button
                    type="button"
                    onClick={() => navigateWithinDetails(nextWallpaper)}
                    disabled={!nextWallpaper}
                    className="wd-btn wd-bar-nav-btn"
                    title={t('navigation.next')}
                    aria-label={t('navigation.next')}
                  >
                    <AiOutlineRight size={15} />
                    <span className="wd-bar-hidesm">{t('navigation.nextShort')}</span>
                  </button>
                </div>

                <span className="wd-bar-divider" />

                <button
                  type="button"
                  disabled={!downloadReady || isVideoWallpaper || isMacDynamic}
                  onClick={() => {
                    if (!downloadReady || isVideoWallpaper || isMacDynamic) return;
                    if (frames.length > 1) {
                      toast(t('toast.useHeroControls'), { icon: 'ℹ️' });
                      return;
                    }
                    setFullscreen(true);
                  }}
                  className="wd-btn wd-btn-icon"
                  title={t('preview.fullscreenTitle')}
                  aria-label={t('preview.fullscreenTitle')}
                >
                  <AiOutlineFullscreen size={15} />
                </button>

                <button
                  type="button"
                  onClick={() => {
                    if (devicePreviewDisabled) return;
                    setExpandedDrawerPlatform(matchedDrawerPlatform);
                    setDrawerOpen(true);
                  }}
                  disabled={devicePreviewDisabled}
                  className="wd-btn wd-bar-device"
                  title={devicePreviewUnavailable || (!variantsLoading && variants.length === 0)
                    ? t('actions.devicesUnavailable')
                    : t('actions.devicesTitle')}
                >
                  <MdDevices size={16} />
                  <span className="wd-bar-hidesm">{t('actions.devices')}</span>
                  <span className={`wd-btn-count ${variantsLoading ? 'is-loading' : ''}`} aria-live="polite">
                    {variantsLoading ? '\u00A0' : variants.length}
                  </span>
                </button>
                {isMacDynamic && frames.length > 1 && (
                  <>
                    <span className="wd-bar-divider" />
                    <button
                      type="button"
                      onClick={() => setFramePlaying((playing) => !playing)}
                      className="wd-btn"
                      title={framePlaying ? t('hero.pause') : t('hero.play')}
                      aria-label={framePlaying ? t('hero.pause') : t('hero.play')}
                      aria-pressed={framePlaying}
                    >
                      {framePlaying ? <MdPause size={16} /> : <MdPlayArrow size={17} />}
                      <span>{framePlaying ? t('hero.pause') : t('hero.play')}</span>
                      <span className="wd-btn-count">{frameIdx + 1}/{frames.length}</span>
                    </button>
                    <span className="wd-bar-divider" />
                  </>
                )}
                <button
                  onClick={handleDownloadClick}
                  disabled={dlLoading || !downloadReady}
                  className="wd-btn-cta"
                  style={{ opacity: downloadReady ? undefined : 0.55 }}
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

function WallpaperDetailLoading({ title, onBack }: { title: string; onBack: () => void }) {
  const { t } = useTranslation('detail');
  return (
    <>
      <PageMeta title={title} />
      <div className="bg-paper text-ink h-full flex flex-col min-h-0 relative wd-root" aria-busy="true">
        <div className="wd-detail-scroll flex-1 min-h-0 overflow-y-auto relative z-10">
          <section className="wd-s1">
            <div className="wd-s1-media wd-detail-loading-media">
              <span className="wd-s1-loading-glow" aria-hidden />
            </div>
            <div className="wd-s1-vignette" aria-hidden />

            <button
              type="button"
              className="wd-circle-btn glass-bounce wd-s1-back"
              onClick={onBack}
              aria-label={t('cta.cancel')}
            >
              <AiOutlineLeft size={17} />
            </button>
            <div className="wd-s1-info">
              <button type="button" className="wd-circle-btn" disabled aria-label={t('video.loading')}>
                <AiOutlineInfoCircle size={18} />
              </button>
            </div>

            <div className="wd-s1-bottom">
              <div className="wd-bar" aria-label={t('video.loading')}>
                <div className="wd-bar-meta is-loading" aria-hidden>
                  <span className="wd-toolbar-skeleton is-meta-primary" />
                  <span className="wd-toolbar-skeleton is-meta-secondary" />
                </div>

                <span className="wd-bar-divider" />

                <button type="button" disabled className="wd-btn">
                  <AiOutlineHeart size={14} />
                  <span className="wd-bar-hidesm">{t('actions.like')}</span>
                  <span className="wd-btn-count is-loading">&nbsp;</span>
                </button>
                <button type="button" disabled className="wd-btn">
                  <AiOutlineStar size={14} />
                  <span className="wd-bar-hidesm">{t('actions.favorite')}</span>
                </button>
                <button type="button" disabled className="wd-btn">
                  <MdPlaylistAdd size={16} />
                  <span className="wd-bar-hidesm">{t('actions.addToList')}</span>
                </button>

                <span className="wd-bar-divider" />

                <div className="wd-bar-nav" role="group" aria-label={t('navigation.group')}>
                  <button type="button" disabled className="wd-btn wd-bar-nav-btn" aria-label={t('navigation.previous')}>
                    <AiOutlineLeft size={15} />
                    <span className="wd-bar-hidesm">{t('navigation.previousShort')}</span>
                  </button>
                  <button type="button" disabled className="wd-btn wd-bar-nav-btn" aria-label={t('navigation.next')}>
                    <AiOutlineRight size={15} />
                    <span className="wd-bar-hidesm">{t('navigation.nextShort')}</span>
                  </button>
                </div>

                <span className="wd-bar-divider" />

                <button type="button" disabled className="wd-btn wd-btn-icon" aria-label={t('preview.fullscreenTitle')}>
                  <AiOutlineFullscreen size={15} />
                </button>
                <button type="button" disabled className="wd-btn wd-bar-device" aria-label={t('actions.devicesTitle')}>
                  <MdDevices size={16} />
                  <span className="wd-bar-hidesm">{t('actions.devices')}</span>
                  <span className="wd-btn-count is-loading">&nbsp;</span>
                </button>
                <button type="button" disabled className="wd-btn-cta" aria-label={t('video.loading')}>
                  <span className="wd-toolbar-skeleton is-cta" aria-hidden />
                </button>
              </div>
            </div>
          </section>
        </div>
      </div>
      <SpotlightStyles />
    </>
  );
}


function SpotlightStyles() {
  return (<style>{`
/* ── Immersive two-screen layout (mirrors the Mac detail page) ── */
.wd-root, .wd-drawer {
  --wd-detail-glass-bg: rgba(10,10,12,0.44);
  --wd-detail-glass-filter: blur(24px) saturate(1.4);
  --wd-detail-glass-shadow: inset 0 1px 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(0,0,0,0.30),
                            0 2px 3px rgba(0,0,0,0.22), 0 12px 26px rgba(0,0,0,0.34);
}
html.wd-detail-scrollbar-hidden,
html.wd-detail-scrollbar-hidden body,
.wd-detail-scroll {
  scrollbar-width: none;
  -ms-overflow-style: none;
}
html.wd-detail-scrollbar-hidden::-webkit-scrollbar,
html.wd-detail-scrollbar-hidden body::-webkit-scrollbar,
.wd-detail-scroll::-webkit-scrollbar {
  width: 0;
  height: 0;
  display: none;
}
.wd-s1 { position: relative; height: calc(100dvh - 60px); min-height: 560px; overflow: hidden; }
/* Inside the route modal the panel has its own definite height. */
.wd-in-modal .wd-s1 { height: 100%; min-height: 0; }
.wd-s1-media { position: absolute; inset: 0; overflow: hidden; isolation: isolate; }
.wd-s1-image-canvas { position: relative; overflow: hidden; }
.wd-s1-img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover;
  transition: opacity 520ms var(--ease-out-quart), filter 720ms var(--ease-out-quart);
  will-change: opacity, filter; }
.wd-s1-img-preview { z-index: 0; filter: saturate(.96) blur(1.5px); }
.wd-s1-img-preview.is-upgraded { filter: none; }
.wd-s1-img-original { z-index: 1; opacity: 0; pointer-events: none; }
.wd-s1-img-original.is-ready { opacity: 1; }
.wd-s1-loading-glow { position: absolute; inset: 0; z-index: 2; overflow: hidden; pointer-events: none;
  background: radial-gradient(circle at 50% 44%, rgba(255,255,255,.08), transparent 58%);
  animation: wdHeroGlowPulse 1.8s ease-in-out infinite alternate; }
.wd-s1-loading-glow::after { content: ''; position: absolute; top: -24%; bottom: -24%; left: -54%; width: 38%;
  background: linear-gradient(100deg, transparent 0%, rgba(255,255,255,.08) 24%, rgba(255,255,255,.48) 50%, rgba(255,255,255,.08) 76%, transparent 100%);
  filter: blur(22px); transform: translateX(-120%) rotate(10deg); mix-blend-mode: screen;
  animation: wdHeroGlowSweep 1.65s ease-in-out infinite; }
@keyframes wdHeroGlowPulse { from { opacity: .48; } to { opacity: .9; } }
@keyframes wdHeroGlowSweep { from { transform: translateX(-120%) rotate(10deg); } to { transform: translateX(520%) rotate(10deg); } }
@media (prefers-reduced-motion: reduce) {
  .wd-s1-img { transition-duration: 0ms; }
  .wd-s1-loading-glow, .wd-s1-loading-glow::after { animation: none; }
  .wd-s1-loading-glow { opacity: .55; }
}
.wd-detail-loading-media { background: linear-gradient(145deg, rgba(34,34,40,0.98), rgba(16,16,20,0.98)); }
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
.wd-s1-back { position: absolute; top: 22px; left: 24px; z-index: 5; }
.wd-s1-info { position: absolute; top: 22px; right: 24px; z-index: 5; display: flex; flex-direction: column; align-items: flex-end; gap: 10px; }

/* Info panel — glass-dark metadata card (Mac detailInfoPanel). */
.wd-info-panel { width: 320px; max-width: 86vw; max-height: calc(100dvh - 120px); overflow-y: auto;
  padding: 16px; border-radius: 18px;
  background: var(--wd-detail-glass-bg);
  backdrop-filter: var(--wd-detail-glass-filter); -webkit-backdrop-filter: var(--wd-detail-glass-filter);
  box-shadow: var(--wd-detail-glass-shadow);
  display: flex; flex-direction: column; gap: 14px;
  animation: wdFadeIn .16s ease; }
.wd-ip-row { display: flex; align-items: center; gap: 10px; }
.wd-ip-avatar-btn { flex-shrink: 0; }
.wd-ip-user-copy { min-width: 0; flex: 1; }
.wd-ip-user-line { display: flex; align-items: baseline; gap: 10px; min-width: 0; }
.wd-ip-username { min-width: 0; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  color: #fff; font-size: 13px; font-weight: 500; }
.wd-ip-coins { flex-shrink: 0; color: oklch(84% 0.14 82); font-size: 13px; font-weight: 600;
  font-variant-numeric: tabular-nums; text-shadow: 0 1px 8px oklch(76% 0.16 75 / 0.24); }
.wd-ip-bio { min-height: 1.35em; margin-top: 3px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  color: rgba(255,255,255,0.55); font-size: 11px; line-height: 1.35; }
.wd-ip-block { border-top: 1px solid rgba(255,255,255,0.14); padding-top: 12px; }
.wd-ip-kicker { font-family: var(--font-mono); font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: rgba(255,255,255,0.50); margin-bottom: 4px; }
.wd-ip-tag { display: inline-flex; padding: 2px 9px; border-radius: 9999px; font-size: 10.5px; font-weight: 500;
  color: rgba(255,255,255,0.85); background: rgba(255,255,255,0.10); border: 1px solid rgba(255,255,255,0.16); }
.wd-ip-swatch { width: 30px; height: 30px; border-radius: 8px; border: 1px solid rgba(255,255,255,0.25); cursor: pointer; transition: transform 160ms var(--ease-out-quart); }
.wd-ip-swatch:hover { transform: scale(1.08); }
.wd-ip-stats { display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px 12px; border-top: 1px solid rgba(255,255,255,0.14); padding-top: 12px; }

/* Bottom-centre column: progress + notices + toolbar. */
.wd-s1-bottom { position: absolute; left: 50%; bottom: 22px; transform: translateX(-50%); z-index: 6;
  display: flex; flex-direction: column; align-items: center; gap: 12px;
  width: max-content; max-width: calc(100vw - 32px); }
.wd-s1-bottom .wd-notice { width: min(560px, calc(100vw - 40px)); }
.wd-s1-bottom .wd-download-progress { width: min(420px, calc(100vw - 40px)); margin-top: 0; }

/* The toolbar itself — dark glass capsule (Mac immersiveToolbar). */
.wd-bar { position: relative; display: flex; align-items: center; gap: 8px; flex-wrap: wrap; justify-content: center;
  padding: 8px 10px; border-radius: 9999px;
  background: var(--wd-detail-glass-bg);
  backdrop-filter: var(--wd-detail-glass-filter); -webkit-backdrop-filter: var(--wd-detail-glass-filter);
  box-shadow: var(--wd-detail-glass-shadow); }
.wd-bar-meta { width: 252px; min-height: 29px; display: flex; flex-direction: column; gap: 3px; padding: 0 6px 0 10px; flex-shrink: 0; }
.wd-bar-meta > span { overflow: hidden; text-overflow: ellipsis; }
.wd-bar-meta-secondary { display: flex; align-items: center; min-width: 0; }
.wd-bar-meta-secondary-main { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
.wd-bar-meta-secondary-flag { flex-shrink: 0; color: rgba(255,255,255,0.78); }
.wd-toolbar-skeleton { display: block; border-radius: 9999px; background: rgba(255,255,255,0.18); }
.wd-toolbar-skeleton.is-meta-primary { width: 112px; height: 13px; }
.wd-toolbar-skeleton.is-meta-secondary { width: 188px; height: 10px; background: rgba(255,255,255,0.11); }
.wd-toolbar-skeleton.is-cta { width: 68px; height: 12px; background: rgba(255,255,255,0.42); }
.wd-bar-divider { width: 1px; height: 24px; background: rgba(255,255,255,0.22); flex-shrink: 0; }
.wd-bar-nav { display: inline-flex; align-items: center; gap: 6px; flex-shrink: 0; }
.wd-bar-nav-btn { justify-content: center; }
/* Buttons inside the dark bar: flat white tints (no glass-on-glass). */
.wd-bar .wd-btn { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.14); color: rgba(255,255,255,0.92); box-shadow: none; }
.wd-bar .wd-btn:not(:disabled):hover { background: rgba(255,255,255,0.16); border-color: rgba(255,255,255,0.28); }
.wd-bar .wd-btn-count { background: rgba(255,255,255,0.14); color: rgba(255,255,255,0.75); }
.wd-bar-device { min-width: 96px; justify-content: center; }
.wd-bar-device .wd-btn-count { min-width: 24px; justify-content: center; font-variant-numeric: tabular-nums; }
.wd-bar .wd-btn-count.is-loading { color: transparent; background: rgba(255,255,255,0.10); }
.wd-bar .wd-btn.is-liked { color: #ff9e97; border-color: rgba(224,70,58,0.65); background: rgba(224,70,58,0.20); }
.wd-bar .wd-btn.is-favorited { color: #ffd98f; border-color: rgba(216,162,58,0.65); background: rgba(216,162,58,0.20); }
.wd-bar .wd-actionbar-toggle { background: rgba(255,255,255,0.08); border-color: rgba(255,255,255,0.12); }
.wd-bar .wd-toggle-pill { color: rgba(255,255,255,0.60); }
.wd-bar .wd-toggle-pill:hover { color: rgba(255,255,255,0.9); }
.wd-bar .wd-toggle-pill.is-on { background: rgba(255,255,255,0.92); color: var(--color-ink); }
@media (max-width: 900px) {
  .wd-bar-hidesm { display: none; }
  .wd-bar-meta { display: none; }
  .wd-bar-device { min-width: 60px; }
}

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
.wd-btn:not(:disabled):hover { background: var(--color-paper-2); border-color: var(--color-ink-2); }
.wd-btn:disabled { opacity: 0.6; cursor: not-allowed; }
.wd-btn-icon { padding: 8px 12px; }
.wd-btn.is-liked { color: oklch(58% 0.20 25); border-color: oklch(58% 0.20 25); background: color-mix(in oklch, oklch(58% 0.20 25) 4%, var(--color-paper)); }
.wd-btn.is-favorited { color: oklch(70% 0.18 65); border-color: oklch(70% 0.18 65); background: color-mix(in oklch, oklch(70% 0.18 65) 5%, var(--color-paper)); }
.wd-btn-count { min-width: 21px; display: inline-flex; align-items: center; justify-content: center; padding: 1px 6px; border-radius: 999px; background: var(--color-paper-2); color: var(--color-muted); font-family: var(--font-mono); font-size: 10px; margin-left: 2px; font-variant-numeric: tabular-nums; }

.wd-toggle-pill { padding: 6px 14px; border-radius: 999px; font-size: 12px; font-weight: 500; color: var(--color-muted); transition: background-color .15s ease, color .15s ease, box-shadow .15s ease; }
.wd-toggle-pill:hover { color: var(--color-ink-2); }
.wd-toggle-pill.is-on { background: var(--color-paper); color: var(--color-ink); box-shadow: inset 0 1px 0 rgba(255,255,255,0.7), 0 1.5px 2px rgba(0,0,0,0.12), 0 3px 6px rgba(0,0,0,0.14); }

.wd-btn-cta { min-width: 108px; display: inline-flex; align-items: center; justify-content: center; gap: 8px; padding: 9px 18px; border-radius: 999px; background: var(--color-accent); color: white; font-size: 13px; font-weight: 600; white-space: nowrap;
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.35), 0 4px 8px -2px oklch(64% 0.21 42 / 0.30), 0 8px 16px -6px oklch(64% 0.21 42 / 0.35);
  transition: filter .15s ease, transform 240ms cubic-bezier(0.34,1.56,0.64,1); }
.wd-btn-cta:not(:disabled):hover { transform: scale(1.04); }
.wd-btn-cta:not(:disabled):active { transform: scale(0.94); }
.wd-btn-cta:not(:disabled):hover { filter: brightness(1.05); }
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
  color: rgba(255,255,255,0.92); background: var(--wd-detail-glass-bg);
  backdrop-filter: var(--wd-detail-glass-filter); -webkit-backdrop-filter: var(--wd-detail-glass-filter);
  display: flex; flex-direction: column;
  box-shadow: inset 1px 0 0 rgba(255,255,255,0.22), inset 0 -1px 0 rgba(0,0,0,0.30), -20px 0 60px -20px rgba(0,0,0,0.34);
  border-left: 1px solid rgba(255,255,255,0.14); animation: wdSlideInRight .28s cubic-bezier(0.2,0.8,0.2,1); }
.wd-drawer .text-ink { color: rgba(255,255,255,0.92); }
.wd-drawer .text-ink-2 { color: rgba(255,255,255,0.72); }
.wd-drawer .text-muted { color: rgba(255,255,255,0.50); }
.wd-drawer-head { padding: 22px 22px 16px; border-bottom: 1px solid rgba(255,255,255,0.14); display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; flex-shrink: 0; }
.wd-drawer-head button { color: rgba(255,255,255,0.72); }
.wd-drawer-head button:hover { color: rgba(255,255,255,0.96); background: rgba(255,255,255,0.10); }
.wd-drawer-body { flex: 1; overflow-y: auto; padding: 6px 18px 18px; }
.wd-drawer-foot { padding: 12px 22px; border-top: 1px solid rgba(255,255,255,0.14); background: rgba(255,255,255,0.04); flex-shrink: 0; }
.wd-drawer-group { margin-top: 14px; }
.wd-drawer-grouphead { width: 100%; display: flex; justify-content: space-between; align-items: center; font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.16em; text-align: left; text-transform: uppercase; color: rgba(255,255,255,0.50); padding: 2px 6px 8px; border: 0; border-bottom: 1px solid rgba(255,255,255,0.14); background: transparent; cursor: pointer; transition: color .18s ease, border-color .18s ease; }
.wd-drawer-grouphead:hover, .wd-drawer-grouphead[aria-expanded="true"] { color: rgba(255,255,255,0.88); border-bottom-color: rgba(255,255,255,0.24); }
.wd-drawer-grouphead:focus-visible { outline: 2px solid color-mix(in oklch, var(--color-accent) 72%, white); outline-offset: 3px; border-radius: 6px; }
.wd-drawer-groupmeta { display: inline-flex; align-items: center; gap: 8px; }
.wd-drawer-groupchevron { flex-shrink: 0; color: rgba(255,255,255,0.58); transform: rotate(0deg); transition: transform .22s cubic-bezier(0.2,0.8,0.2,1), color .18s ease; }
.wd-drawer-grouphead[aria-expanded="true"] .wd-drawer-groupchevron { color: rgba(255,255,255,0.88); transform: rotate(180deg); }
.wd-drawer-groupcontent { display: grid; grid-template-rows: 0fr; opacity: 0; visibility: hidden; transition: grid-template-rows .24s cubic-bezier(0.2,0.8,0.2,1), opacity .18s ease, visibility 0s linear .24s; }
.wd-drawer-groupcontent.is-open { grid-template-rows: 1fr; opacity: 1; visibility: visible; transition-delay: 0s; }
.wd-drawer-groupitems { min-height: 0; overflow: hidden; padding-top: 6px; }
.wd-drawer-row { display: flex; flex-direction: column; gap: 10px; padding: 12px; border-radius: 12px; transition: background-color .15s ease; border: 1px solid transparent; margin-bottom: 4px; }
.wd-drawer-row:hover { background: rgba(255,255,255,0.07); border-color: rgba(255,255,255,0.14); }
.wd-drawer-row.is-matched { background: color-mix(in oklch, var(--color-accent) 16%, transparent); border-color: color-mix(in oklch, var(--color-accent) 52%, transparent); }
.wd-drawer-row-head { display: flex; align-items: center; gap: 12px; }
.wd-drawer-row-actions { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 6px; }
.wd-drawer-action { display: inline-flex; align-items: center; justify-content: center; gap: 5px; padding: 7px 8px; border-radius: 999px; border: 1px solid rgba(255,255,255,0.14); background: rgba(255,255,255,0.08); color: rgba(255,255,255,0.82); font-size: 11px; font-weight: 500; transition: background-color .15s ease, color .15s ease, border-color .15s ease; }
.wd-drawer-action:hover:not(:disabled):not(.is-disabled) { background: rgba(255,255,255,0.16); color: rgba(255,255,255,0.96); border-color: rgba(255,255,255,0.28); }
.wd-drawer-action:disabled, .wd-drawer-action.is-disabled { opacity: 0.45; cursor: not-allowed; }
.wd-drawer-action-cta { background: rgba(255,255,255,0.14); color: rgba(255,255,255,0.94); border-color: rgba(255,255,255,0.22); }
.wd-drawer-action-cta:hover:not(:disabled) { background: rgba(255,255,255,0.22); border-color: rgba(255,255,255,0.34); color: white; }
.wd-drawer-action-cta.is-matched { background: var(--color-accent); border-color: var(--color-accent); }
.wd-drawer-action-cta.is-matched:hover:not(:disabled) { filter: brightness(1.05); }

@media (prefers-reduced-transparency: reduce) {
  .wd-info-panel, .wd-bar, .wd-drawer { background: rgba(10,10,12,0.96); backdrop-filter: none; -webkit-backdrop-filter: none; }
}

@media (prefers-reduced-motion: reduce) {
  .wd-drawer-grouphead, .wd-drawer-groupchevron, .wd-drawer-groupcontent { transition: none; }
}

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
function VideoPlayer({
  src,
  thumb,
  preview,
  poster,
}: {
  src: string;
  thumb?: string;
  preview?: string;
  poster?: string;
}) {
  const { t } = useTranslation('detail');
  const vidRef = useRef<HTMLVideoElement | null>(null);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [progress, setProgress] = useState<number | null>(null); // null = not buffering
  const [buffering, setBuffering] = useState(false);
  const [playing, setPlaying] = useState(false);
  const posterTiers = [thumb, preview, poster].filter(
    (url, index, list): url is string => !!url && list.indexOf(url) === index,
  );
  const posterIdentity = posterTiers.join('|');
  const [posterLoadState, setPosterLoadState] = useState({ identity: '', index: -1 });
  const highestLoadedPoster = posterLoadState.identity === posterIdentity ? posterLoadState.index : -1;
  const markPosterLoaded = (index: number) => {
    setPosterLoadState((current) => ({
      identity: posterIdentity,
      index: current.identity === posterIdentity ? Math.max(current.index, index) : index,
    }));
  };

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
      {posterTiers.map((url, index) => (index === 0 || highestLoadedPoster >= index - 1) && (
        <img
          key={url}
          src={url}
          alt=""
          decoding="async"
          draggable={false}
          onLoad={() => markPosterLoaded(index)}
          onError={() => markPosterLoaded(index)}
          className={`absolute inset-0 w-full h-full object-cover pointer-events-none transition-opacity duration-300 ${!playing && highestLoadedPoster === index ? 'opacity-100' : 'opacity-0'}`}
          style={{ transitionTimingFunction: 'var(--ease-out-quart)' }}
        />
      ))}
      <video
        ref={vidRef}
        src={blobUrl ?? undefined}
        loop
        playsInline
        muted
        onPlaying={() => { setPlaying(true); setBuffering(false); }}
        onPause={() => setPlaying(false)}
        className={`relative z-[1] w-full h-full object-cover transition-opacity duration-300 ${playing ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}
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
            className={`flex items-center justify-center w-20 h-20 rounded-full bg-black/55 text-white backdrop-blur-md transition-[transform,background-color,opacity] duration-200 group-hover:scale-105 group-hover:bg-black/70 ${playing ? 'opacity-0 group-hover:opacity-100' : 'opacity-100'}`}
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
