import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuthStore } from '../store/auth';
import {
  likeWallpaper,
  unlikeWallpaper,
  favoriteWallpaper,
  unfavoriteWallpaper,
  downloadWallpaper,
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
  const [liked, setLiked] = useState(wallpaper.is_liked ?? false);
  const [likeLoading, setLikeLoading] = useState(false);
  const [favorited, setFavorited] = useState(wallpaper.is_favorited ?? false);
  const [favLoading, setFavLoading] = useState(false);
  const [downloaded, setDownloaded] = useState(wallpaper.is_downloaded ?? false);
  const [downloading, setDownloading] = useState(false);
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

  const doLike = async () => {
    if (likeLoading) return;
    setLikeLoading(true);
    try {
      if (liked) await unlikeWallpaper(wallpaper.id);
      else await likeWallpaper(wallpaper.id);
      setLiked(!liked);
    } catch {
      toast.error('Action failed');
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
      toast.error('Action failed');
    } finally {
      setFavLoading(false);
    }
  };

  const doDownload = async () => {
    if (!isOwnWallpaper && user && user.coins <= 0) {
      toast.error('Insufficient coins. Upload wallpapers to earn more!');
      return;
    }
    setDownloading(true);
    try {
      const resp = await fetch(downloadWallpaper(wallpaper.id), {
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
      const blob = await resp.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      const ext = wallpaper.original_url.split('.').pop()?.split('?')[0] || 'jpg';
      a.download = `wallpaper_${wallpaper.id}.${ext}`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      setDownloaded(true);
      if (!isOwnWallpaper && user) {
        const remaining = user.coins - 1;
        updateCoins(remaining);
        if (remaining <= 3 && remaining > 0) {
          toast(`${remaining} coin${remaining === 1 ? '' : 's'} left. Upload wallpapers to earn more!`, { icon: '💡' });
        }
      }
    } catch {
      toast.error('Download failed');
    } finally {
      setDownloading(false);
    }
  };

  return {
    liked, favorited, downloaded,
    likeLoading, favLoading, downloading,
    canDownload,
    handleLike: () => requireAuth(doLike),
    handleFavorite: () => requireAuth(doFavorite),
    handleDownload: () => requireAuth(doDownload),
  };
}
