import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import toast from 'react-hot-toast';
import { useAuthStore } from '../store/auth';
import {
  likeWallpaper,
  unlikeWallpaper,
  favoriteWallpaper,
  unfavoriteWallpaper,
  downloadWallpaper,
  getMyCoins,
} from '../api';
import type { Wallpaper } from '../types';

/**
 * Shared state + handlers for the tile action rail (favorite, like,
 * download). Centralises:
 *   - the optimistic toggle states (liked / favorited / downloaded)
 *   - per-action loading flags so a tile can render a spinner
 *   - auth gating (redirect to /login on click while signed out)
 *   - the download blob handler + coin balance update + low-coin nudge
 *   - the dynamic-wallpaper download gate (Mac-only)
 *
 * Used by WallpaperCard (salon variant) and HomePage's WallpaperTile so
 * the action rail behaves identically on both surfaces. Wrap callers
 * with handleAction(e, fn) to .preventDefault() / .stopPropagation()
 * before invoking — that part stays at the caller because the wrapping
 * Link / modal-nav context varies per surface.
 */
export function useWallpaperActions(wallpaper: Wallpaper) {
  const { t } = useTranslation('detail');
  const [liked, setLiked] = useState(wallpaper.is_liked ?? false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favorited, setFavorited] = useState(wallpaper.is_favorited ?? false);
  const [favLoading, setFavLoading] = useState(false);
  const [downloaded, setDownloaded] = useState(wallpaper.is_downloaded ?? false);
  const [downloading, setDownloading] = useState(false);
  const [downloadProgress, setDownloadProgress] = useState<number | null>(null);
  const { isAuthenticated, user, updateCoins } = useAuthStore();
  const navigate = useNavigate();

  const requireAuth = (action: () => void) => {
    if (!isAuthenticated) {
      navigate('/login');
      return;
    }
    action();
  };

  const isOwnWallpaper = !!(user && wallpaper.user_id === user.id);
  const canDownload = !wallpaper.is_dynamic || /Macintosh|Mac OS X/i.test(navigator.userAgent);
  const downloadCost = isOwnWallpaper || downloaded ? 0 : 1;
  const downloadTitle = downloaded ? t('cta.gotIt') : downloadCost > 0 ? t('cta.tradeFor', { n: downloadCost }) : t('cta.download');

  const doLike = async () => {
    if (likeLoading) return;
    setLikeLoading(true);
    try {
      if (liked) await unlikeWallpaper(wallpaper.id);
      else await likeWallpaper(wallpaper.id);
      setLiked(!liked);
    } catch {
      toast.error(t('toast.actionFailed'));
    } finally {
      setLikeLoading(false);
    }
  };

  const doFavorite = async () => {
    if (favLoading) return;
    setFavLoading(true);
    try {
      if (favorited) await unfavoriteWallpaper(wallpaper.id);
      else await favoriteWallpaper(wallpaper.id);
      setFavorited(!favorited);
    } catch {
      toast.error(t('toast.actionFailed'));
    } finally {
      setFavLoading(false);
    }
  };

  const doDownload = async () => {
    setDownloading(true);
    setDownloadProgress(null);
    try {
      const resp = await fetch(downloadWallpaper(wallpaper.id), {
        headers: { Authorization: `Bearer ${useAuthStore.getState().token}` },
      });
      if (resp.status === 402) {
        toast.error(t('toast.insufficientCoins'));
        return;
      }
      if (!resp.ok) {
        toast.error(t('toast.downloadFailed'));
        return;
      }
      const totalBytes = Number(resp.headers.get('content-length') || 0);
      let blob: Blob;
      if (!resp.body) {
        blob = await resp.blob();
        setDownloadProgress(1);
      } else {
        const reader = resp.body.getReader();
        const chunks: BlobPart[] = [];
        let receivedBytes = 0;
        setDownloadProgress(totalBytes > 0 ? 0 : null);
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          if (value) {
            const chunk = new ArrayBuffer(value.byteLength);
            new Uint8Array(chunk).set(value);
            chunks.push(chunk);
            receivedBytes += value.byteLength;
            if (totalBytes > 0) {
              setDownloadProgress(Math.min(receivedBytes / totalBytes, 1));
            }
          }
        }
        blob = new Blob(chunks, {
          type: resp.headers.get('content-type') || 'application/octet-stream',
        });
        setDownloadProgress(1);
      }
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      const finalPath = new URL(resp.url, window.location.href).pathname;
      const ext = finalPath.match(/\.([a-z0-9]{2,8})$/i)?.[1] || 'jpg';
      a.download = `wallpaper_${wallpaper.id}.${ext}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setDownloaded(true);
      if (!isOwnWallpaper && user && !downloaded) {
        try {
          const coinsResp = await getMyCoins();
          const remaining = coinsResp.data.data.coins;
          updateCoins(remaining);
          if (remaining <= 3 && remaining > 0) {
            toast(t('toast.coinsLeft', { count: remaining }), { icon: '💡' });
          }
        } catch {
          updateCoins(Math.max(user.coins - downloadCost, 0));
        }
      }
    } catch {
      toast.error(t('toast.downloadFailed'));
    } finally {
      setDownloading(false);
      setDownloadProgress(null);
    }
  };

  return {
    liked, favorited, downloaded,
    likeLoading, favLoading, downloading,
    downloadProgress, downloadTitle, downloadCost,
    canDownload,
    handleLike: () => requireAuth(doLike),
    handleFavorite: () => requireAuth(doFavorite),
    handleDownload: () => requireAuth(doDownload),
  };
}
