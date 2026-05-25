import { useState, type FormEvent } from 'react';
import { api } from '../lib/api';
import { setToken } from '../lib/auth';

// Login appears as a centered modal-style overlay on top of the
// Home screen. Click outside the form (the dim backdrop) or press
// Esc to dismiss without signing in. Sign-up is web-only — link
// users out to the marketing site rather than reimplementing the
// flow in the desktop client.
export default function LoginScreen({
  onSignedIn,
  onCancel,
}: {
  onSignedIn: (token: string) => void;
  onCancel: () => void;
}) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const r = await api.login(email, password);
      await setToken(r.token);
      onSignedIn(r.token);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Sign in failed');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="modal-backdrop" onClick={(e) => { if (e.target === e.currentTarget) onCancel(); }}>
      <form className="login-form" onSubmit={submit} onKeyDown={(e) => { if (e.key === 'Escape') onCancel(); }}>
        <div className="brand">
          <div className="name">Wallpaper Exchange</div>
          <div className="kicker" style={{ marginTop: 4 }}>Sign in to download</div>
        </div>

        <input
          type="email"
          autoComplete="username"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoFocus
          required
          disabled={busy}
        />
        <input
          type="password"
          autoComplete="current-password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          disabled={busy}
        />
        {err && <div className="err">{err}</div>}
        <button type="submit" className="primary" disabled={busy || !email || !password}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
        <div className="kicker" style={{ textAlign: 'center', marginTop: 8 }}>
          No account? Sign up at wallpaperexchange.com
        </div>
        <button type="button" onClick={onCancel} style={{ background: 'transparent', border: 'none', color: 'var(--muted)', marginTop: 4, fontSize: 12 }}>
          Cancel
        </button>
      </form>
    </div>
  );
}
