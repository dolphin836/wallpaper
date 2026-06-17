import { useState, type FormEvent } from 'react';
import { api } from '../lib/api';
import { setToken } from '../lib/auth';

export default function LoginScreen({
  onSignedIn,
  onCancel,
}: {
  onSignedIn: (token: string) => void;
  onCancel: () => void;
}) {
  const [mode, setMode] = useState<'login' | 'register'>('login');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [passwordVisible, setPasswordVisible] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setErr(null);
    try {
      const response = mode === 'login'
        ? await api.login(email, password)
        : await api.register(username.trim(), email, password);
      await setToken(response.token);
      onSignedIn(response.token);
    } catch (error) {
      setErr(error instanceof Error ? error.message : '登录失败');
    } finally {
      setBusy(false);
    }
  }

  const disabled = busy || !email || !password || (mode === 'register' && !username.trim());

  return (
    <div className="modal-backdrop" onClick={(event) => { if (event.target === event.currentTarget) onCancel(); }}>
      <form className="login-form" onSubmit={submit} onKeyDown={(event) => { if (event.key === 'Escape') onCancel(); }}>
        <div className="brand">
          <div className="name">Wallpaper Exchange</div>
          <div className="kicker">{mode === 'login' ? '登录后同步收藏和下载' : '创建账号后即可下载'}</div>
        </div>

        {mode === 'register' && (
          <input
            type="text"
            autoComplete="username"
            placeholder="用户名"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
            disabled={busy}
            autoFocus
          />
        )}

        <input
          type="email"
          autoComplete="email"
          placeholder="邮箱"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          autoFocus={mode === 'login'}
          required
          disabled={busy}
        />

        <div className="password-field">
          <input
            type={passwordVisible ? 'text' : 'password'}
            autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            placeholder="密码"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            required
            disabled={busy}
          />
          <button type="button" onClick={() => setPasswordVisible((value) => !value)} disabled={busy}>
            {passwordVisible ? '隐藏' : '显示'}
          </button>
        </div>

        {err && <div className="err">{err}</div>}

        <button type="submit" className="primary-pill" disabled={disabled}>
          {busy ? '处理中...' : mode === 'login' ? '登录' : '注册'}
        </button>

        <button
          type="button"
          className="ghost"
          onClick={() => {
            setErr(null);
            setMode(mode === 'login' ? 'register' : 'login');
          }}
        >
          {mode === 'login' ? '没有账号？注册' : '已有账号？登录'}
        </button>
        <button type="button" className="ghost" onClick={onCancel}>取消</button>
      </form>
    </div>
  );
}
