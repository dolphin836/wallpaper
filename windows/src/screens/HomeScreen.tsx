import { useCallback, useEffect, useMemo, useState } from 'react';
import { api } from '../lib/api';
import { cmd } from '../lib/commands';
import { clearToken } from '../lib/auth';
import type { User, Wallpaper } from '../lib/types';

// Two-column layout matching the macOS popover: Latest on the left,
// Downloaded on the right. Browse is open; Set / Download only
// require sign-in at click time. Active chip surfaces on whichever
// Downloaded wallpaper is currently applied.

const APPLIED_KEY = 'wpe.applied.id';

export default function HomeScreen({
  token,
  onRequestSignIn,
  onSignOut,
}: {
  token: string | null;
  onRequestSignIn: () => void;
  onSignOut: () => void;
}) {
  const [latest, setLatest] = useState<Wallpaper[]>([]);
  const [latestErr, setLatestErr] = useState<string | null>(null);
  const [latestLoading, setLatestLoading] = useState(true);
  const [downloaded, setDownloaded] = useState<Wallpaper[]>([]);
  const [downloadedPaths, setDownloadedPaths] = useState<Map<number, string>>(new Map());
  const [downloadedLoading, setDownloadedLoading] = useState(true);
  const [me, setMe] = useState<User | null>(null);
  const [diskBytes, setDiskBytes] = useState<number>(0);
  const [appliedID, setAppliedID] = useState<number | null>(() => {
    const v = localStorage.getItem(APPLIED_KEY);
    return v ? Number(v) : null;
  });

  // Latest column — server-anonymous, hides macOS-dynamic since the
  // Windows desktop wallpaper API can't render them.
  useEffect(() => {
    setLatestLoading(true);
    api
      .listWallpapers({ limit: 24, sort: 'newest', exclude_dynamic: true })
      .then((r) => setLatest(r.items))
      .catch((e) => setLatestErr(e instanceof Error ? e.message : 'Failed to load'))
      .finally(() => setLatestLoading(false));
  }, [token]);

  // Profile chip — anonymous users see Sign in instead.
  useEffect(() => {
    if (!token) {
      setMe(null);
      return;
    }
    api.me().then(setMe).catch(() => setMe(null));
  }, [token]);

  // Downloaded column. We list local files (the Rust side scans the
  // downloads dir), then ask the API to hydrate the wallpaper rows so
  // we can show thumbnails / titles consistently with Latest.
  const refreshDownloaded = useCallback(async () => {
    setDownloadedLoading(true);
    try {
      const local = await cmd.listDownloaded();
      const ids = local.map((i) => i.id);
      const paths = new Map(local.map((i) => [i.id, i.path] as const));
      setDownloadedPaths(paths);
      if (ids.length === 0) {
        setDownloaded([]);
      } else {
        // The /wallpapers endpoint doesn't have a "by ids" mode, so
        // we hand-fetch each. Fine for the modest sizes (< 100 local
        // downloads); revisit if users hoard thousands.
        const hydrated = await Promise.all(
          ids.map((id) =>
            api
              .getWallpaper(id)
              .catch(() => null),
          ),
        );
        const valid = hydrated.filter((w): w is Wallpaper => w !== null);
        // Newest-on-top using local stat would need another command;
        // for now sort by id desc.
        valid.sort((a, b) => b.id - a.id);
        setDownloaded(valid);
      }
      const bytes = await cmd.downloadsTotalBytes();
      setDiskBytes(bytes);
    } catch (e) {
      console.error('refresh downloaded', e);
    } finally {
      setDownloadedLoading(false);
    }
  }, []);

  useEffect(() => {
    refreshDownloaded();
  }, [refreshDownloaded]);

  async function onDownload(w: Wallpaper) {
    if (!token) return onRequestSignIn();
    try {
      await cmd.downloadWallpaper(w.id, w.original_url);
      await refreshDownloaded();
    } catch (e) {
      alert(`Download failed: ${e}`);
    }
  }

  async function onSet(w: Wallpaper) {
    if (!token) return onRequestSignIn();
    try {
      await cmd.setWallpaperById(w.id, w.original_url);
      setAppliedID(w.id);
      localStorage.setItem(APPLIED_KEY, String(w.id));
      await refreshDownloaded();
    } catch (e) {
      alert(`Set wallpaper failed: ${e}`);
    }
  }

  async function onSetLocal(w: Wallpaper) {
    // Downloaded → Set: skip the re-download, point straight at the
    // local path so we don't pay bytes twice.
    const path = downloadedPaths.get(w.id);
    if (!path) return onSet(w);
    try {
      await cmd.setStaticWallpaper(path);
      setAppliedID(w.id);
      localStorage.setItem(APPLIED_KEY, String(w.id));
    } catch (e) {
      alert(`Set wallpaper failed: ${e}`);
    }
  }

  async function onRemove(w: Wallpaper) {
    try {
      await cmd.removeDownloaded(w.id);
      await refreshDownloaded();
    } catch (e) {
      alert(`Remove failed: ${e}`);
    }
  }

  async function signOut() {
    await clearToken();
    onSignOut();
  }

  const formattedSize = useMemo(() => humanBytes(diskBytes), [diskBytes]);

  return (
    <div className="home">
      <header>
        <h1>Wallpaper Exchange</h1>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {token && me ? (
            <>
              <span className="kicker">@{me.username} · {me.coins} coins</span>
              <button className="signout" onClick={signOut}>Sign out</button>
            </>
          ) : (
            <button className="signout" onClick={onRequestSignIn}>Sign in</button>
          )}
        </div>
      </header>

      <div className="cols">
        <Column
          title="Latest"
          items={latest}
          loading={latestLoading}
          err={latestErr}
          renderActions={(w) => (
            <>
              <button onClick={() => onSet(w)}>Set</button>
              <button onClick={() => onDownload(w)}>Download</button>
            </>
          )}
          appliedID={appliedID}
        />
        <Column
          title="Downloaded"
          items={downloaded}
          loading={downloadedLoading}
          err={null}
          renderActions={(w) => (
            <>
              <button onClick={() => onSetLocal(w)}>Set</button>
              <button onClick={() => onRemove(w)}>Remove</button>
            </>
          )}
          appliedID={appliedID}
        />
      </div>

      <footer>
        <span className="kicker">{formattedSize} on disk</span>
      </footer>
    </div>
  );
}

function Column({
  title,
  items,
  loading,
  err,
  renderActions,
  appliedID,
}: {
  title: string;
  items: Wallpaper[];
  loading: boolean;
  err: string | null;
  renderActions: (w: Wallpaper) => React.ReactNode;
  appliedID: number | null;
}) {
  return (
    <div className="col">
      <div className="col-head">
        <span className="kicker">{title}</span>
      </div>
      <div className="col-body">
        {loading ? (
          <div className="empty">Loading…</div>
        ) : err ? (
          <div className="empty" style={{ color: '#b1311f' }}>{err}</div>
        ) : items.length === 0 ? (
          <div className="empty">Empty.</div>
        ) : (
          items.map((w) => (
            <Tile
              key={w.id}
              wallpaper={w}
              active={w.id === appliedID}
              actions={renderActions(w)}
            />
          ))
        )}
      </div>
    </div>
  );
}

function Tile({
  wallpaper,
  active,
  actions,
}: {
  wallpaper: Wallpaper;
  active: boolean;
  actions: React.ReactNode;
}) {
  const isVideo = wallpaper.file_type.startsWith('video/');
  return (
    <div className={`tile ${active ? 'active' : ''}`}>
      {wallpaper.thumb_url && <img src={wallpaper.thumb_url} alt="" />}
      {isVideo && <span className="chip">VIDEO</span>}
      {active && <span className="chip chip-active">ACTIVE</span>}
      <div className="actions">{actions}</div>
    </div>
  );
}

function humanBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}
