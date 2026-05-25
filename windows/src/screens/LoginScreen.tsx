import { useState, type FormEvent } from 'react';
import { api } from '../lib/api';
import { setToken } from '../lib/auth';

// First-run / signed-out surface. Email + password. The web app's
// register flow doesn't ship with the Windows MVP — users sign up on
// the website, then sign in here.
export default function LoginScreen({ onSignedIn }: { onSignedIn: (token: string) => void }) {
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
    <div className="screen-center">
      <form className="login-form" onSubmit={submit}>
        <div className="brand">
          <div className="name">Wallpaper Exchange</div>
          <div className="kicker" style={{ marginTop: 4 }}>Sign in</div>
        </div>

        <input
          type="email"
          autoComplete="username"
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
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
          Don&apos;t have an account? Sign up at wallpaperexchange.com
        </div>
      </form>
    </div>
  );
}
