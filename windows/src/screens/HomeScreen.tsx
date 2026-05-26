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
  const [localIDs, setLocalIDs] = useState<Set<number>>(new Set());
  const [downloadedLoading, setDownloadedLoading] = useState(false);
  const [downloadedErr, setDownloadedErr] = useState<string | null>(null);
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

  // Downloaded column. Server-side download history drives the list
  // (mirrors macOS behavior — a wallpaper pulled on another device
  // still surfaces here), while the local file scan only determines
  // which tiles render Set vs Re-download.
  const refreshLocalIDs = useCallback(async () => {
    try {
      const local = await cmd.listDownloaded();
      setLocalIDs(new Set(local.map((i) => i.id)));
      setDownloadedPaths(new Map(local.map((i) => [i.id, i.path] as const)));
      const bytes = await cmd.downloadsTotalBytes();
      setDiskBytes(bytes);
    } catch (e) {
      console.error('refresh local ids', e);
    }
  }, []);

  const refreshDownloaded = useCallback(async () => {
    if (!token) {
      setDownloaded([]);
      setDownloadedErr(null);
      return;
    }
    setDownloadedLoading(true);
    setDownloadedErr(null);
    try {
      const r = await api.listMyDownloads({ limit: 24 });
      setDownloaded(r.items);
    } catch (e) {
      setDownloadedErr(e instanceof Error ? e.message : 'Failed to load');
    } finally {
      setDownloadedLoading(false);
    }
  }, [token]);

  useEffect(() => { refreshLocalIDs(); }, [refreshLocalIDs]);
  useEffect(() => { refreshDownloaded(); }, [refreshDownloaded]);

  async function onDownload(w: Wallpaper) {
    if (!token) return onRequestSignIn();
    try {
      // First-time download from Latest — resolve the signed URL via
      // the API since original_url may be empty for non-owners.
      const url = w.original_url || (await api.getDownloadURL(w.id));
      await cmd.downloadWallpaper(w.id, url);
      await refreshLocalIDs();
      await refreshDownloaded();
    } catch (e) {
      alert(`Download failed: ${e}`);
    }
  }

  async function onSet(w: Wallpaper) {
    if (!token) return onRequestSignIn();
    try {
      const url = w.original_url || (await api.getDownloadURL(w.id));
      await cmd.setWallpaperById(w.id, url);
      setAppliedID(w.id);
      localStorage.setItem(APPLIED_KEY, String(w.id));
      await refreshLocalIDs();
      await refreshDownloaded();
    } catch (e) {
      alert(`Set wallpaper failed: ${e}`);
    }
  }

  async function onSetLocal(w: Wallpaper) {
    // Downloaded → Set when the file is already on this machine —
    // skip the network round-trip entirely.
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

  async function onRedownload(w: Wallpaper) {
    // Downloaded column, local file missing — pull from server-side
    // history. HasDownloaded means the server won't re-charge coins.
    if (!token) return onRequestSignIn();
    try {
      const url = await api.getDownloadURL(w.id);
      await cmd.downloadWallpaper(w.id, url);
      await refreshLocalIDs();
    } catch (e) {
      alert(`Re-download failed: ${e}`);
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
          err={downloadedErr ?? (!token ? 'Sign in to see your downloads' : null)}
          renderActions={(w) => (
            localIDs.has(w.id) ? (
              <button onClick={() => onSetLocal(w)}>Set</button>
            ) : (
              <button onClick={() => onRedownload(w)}>Re-download</button>
            )
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
