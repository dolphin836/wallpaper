import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { clearToken } from '../lib/auth';
import type { User, Wallpaper } from '../lib/types';

// Home renders even when the user isn't signed in (matches the
// macOS client). The wallpaper list endpoint is anonymous-friendly
// on the backend — only download-flavored actions require auth.
export default function HomeScreen({
  token,
  onRequestSignIn,
  onSignOut,
}: {
  token: string | null;
  onRequestSignIn: () => void;
  onSignOut: () => void;
}) {
  const [items, setItems] = useState<Wallpaper[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);
  const [me, setMe] = useState<User | null>(null);

  // Fetch the public list once on mount; refetch silently when the
  // sign-in state changes so server-personalized fields like
  // is_liked / is_downloaded show up correctly.
  useEffect(() => {
    setLoading(true);
    api
      .listWallpapers({ limit: 24, sort: 'newest' })
      .then((r) => setItems(r.items))
      .catch((e) => setErr(e instanceof Error ? e.message : 'Failed to load'))
      .finally(() => setLoading(false));
  }, [token]);

  // Pull the signed-in user's username + coin balance, if signed in.
  // Silent failure: anonymous users see no profile chip.
  useEffect(() => {
    if (!token) {
      setMe(null);
      return;
    }
    api.me().then(setMe).catch(() => setMe(null));
  }, [token]);

  async function signOut() {
    await clearToken();
    onSignOut();
  }

  return (
    <div className="home">
      <header>
        <h1>Wallpapers</h1>
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
      <div className="body">
        {loading ? (
          <div className="empty">Loading…</div>
        ) : err ? (
          <div className="empty" style={{ color: '#b1311f' }}>{err}</div>
        ) : items.length === 0 ? (
          <div className="empty">Nothing yet.</div>
        ) : (
          <div className="grid">
            {items.map((w) => (
              <Tile key={w.id} wallpaper={w} signedIn={!!token} onNeedsSignIn={onRequestSignIn} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Tile({
  wallpaper,
  signedIn,
  onNeedsSignIn,
}: {
  wallpaper: Wallpaper;
  signedIn: boolean;
  onNeedsSignIn: () => void;
}) {
  const isVideo = wallpaper.file_type.startsWith('video/');
  const guard = (label: string) => () => {
    if (!signedIn) {
      onNeedsSignIn();
      return;
    }
    // TODO: wire to Tauri commands in the next pass.
    console.log(label, wallpaper.id);
  };
  return (
    <div className="tile">
      {wallpaper.thumb_url && <img src={wallpaper.thumb_url} alt="" />}
      {isVideo && <span className="chip">VIDEO</span>}
      <div className="actions">
        <button title="Set as desktop wallpaper" onClick={guard('set')}>Set</button>
        <button title="Download to local downloads" onClick={guard('download')}>Download</button>
      </div>
    </div>
  );
}
