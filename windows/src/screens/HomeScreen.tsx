import { useEffect, useState } from 'react';
import { api } from '../lib/api';
import { clearToken } from '../lib/auth';
import type { Wallpaper } from '../lib/types';

// Home: a single column of recent wallpapers. Hover reveals "Set"
// + "Download" actions (TODO: wire to Tauri commands). Matches the
// macOS popover's Latest column.
export default function HomeScreen({ onSignOut }: { onSignOut: () => void }) {
  const [items, setItems] = useState<Wallpaper[]>([]);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    api
      .listWallpapers({ limit: 24, sort: 'newest' })
      .then((r) => setItems(r.items))
      .catch((e) => setErr(e instanceof Error ? e.message : 'Failed to load'))
      .finally(() => setLoading(false));
  }, []);

  async function signOut() {
    await clearToken();
    onSignOut();
  }

  return (
    <div className="home">
      <header>
        <h1>Wallpapers</h1>
        <button className="signout" onClick={signOut}>Sign out</button>
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
              <Tile key={w.id} wallpaper={w} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function Tile({ wallpaper }: { wallpaper: Wallpaper }) {
  const isVideo = wallpaper.file_type.startsWith('video/');
  return (
    <div className="tile">
      {wallpaper.thumb_url && <img src={wallpaper.thumb_url} alt="" />}
      {isVideo && <span className="chip">VIDEO</span>}
      <div className="actions">
        <button title="Set as desktop wallpaper">Set</button>
        <button title="Download to local downloads">Download</button>
      </div>
    </div>
  );
}
