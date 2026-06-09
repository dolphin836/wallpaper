import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AiOutlineMail, AiOutlineLock } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { login } from '../api';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';
import { track } from '../lib/track';
import Field from '../components/Field';

export default function LoginPage() {
  usePageTitle('Login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});
  const setAuth = useAuthStore((s) => s.setAuth);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});
    setLoading(true);
    try {
      const res = await login({ email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      track('login_success');
      toast.success('Welcome back!');
      navigate('/');
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string; code?: number } } };
      const msg = e?.response?.data?.message || 'Login failed';
      // 40103 = wrong password (mostly hits the password field). 40400 =
      // user not found. Both signal "email/password mismatch" to the user.
      const code = e?.response?.data?.code;
      if (code === 40103 || code === 40400) {
        setErrors({ password: 'Email or password is incorrect' });
      } else {
        toast.error(msg);
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="auth-page">
      <div className="auth-mesh" aria-hidden />
      <form onSubmit={handleSubmit} className="auth-card">
        <Link to="/" className="auth-brand" aria-label="Wallpaper Exchange">
          <img src="/logo-192.png" alt="" />
          <span className="auth-brand-stack">
            <span className="auth-brand-name">Wallpaper</span>
            <span className="auth-brand-sub">Exchange</span>
          </span>
        </Link>

        <div className="auth-kicker">Sign in</div>
        <h1 className="auth-title">
          Welcome back, <em>archivist</em>.
        </h1>
        <p className="auth-desc">
          Sign in to spend coins, save favourites, and upload your own work.
        </p>

        <div className="auth-fields">
          <Field
            label="Email"
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="you@example.com"
            autoComplete="email"
            icon={<AiOutlineMail size={15} />}
            error={errors.email}
          />
          <Field
            label="Password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="••••••••"
            autoComplete="current-password"
            icon={<AiOutlineLock size={15} />}
            error={errors.password}
          />
        </div>

        <button type="submit" disabled={loading} className="auth-submit">
          {loading ? 'Signing in…' : <>Sign in <span aria-hidden>→</span></>}
        </button>

        <p className="auth-footnote">
          New here?{' '}
          <Link to="/register" className="auth-footnote-link">Register →</Link>
        </p>
      </form>
    </div>
  );
}
