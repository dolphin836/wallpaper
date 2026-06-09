import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AiOutlineMail, AiOutlineLock, AiOutlineUser } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { register } from '../api';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';
import { track } from '../lib/track';
import Field from '../components/Field';

export default function RegisterPage() {
  usePageTitle('Register');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [agreed, setAgreed] = useState(true);
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<{ username?: string; email?: string; password?: string }>({});
  const setAuth = useAuthStore((s) => s.setAuth);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});
    if (!agreed) {
      toast.error('Please accept the Terms of Service and Privacy Policy.');
      return;
    }
    setLoading(true);
    try {
      const res = await register({ username, email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      track('register_success');
      toast.success('Account created!');
      navigate('/');
    } catch (err: unknown) {
      const e = err as { response?: { status?: number; data?: { message?: string; code?: number } } };
      const msg = e?.response?.data?.message || 'Registration failed';
      // 40901 = username/email already taken. Backend doesn't tell us which,
      // so we hint at both fields with a generic conflict line.
      if (e?.response?.status === 409 || e?.response?.data?.code === 40901) {
        const lower = msg.toLowerCase();
        setErrors({
          username: lower.includes('username') ? 'Username taken' : (!lower.includes('email') ? 'Username or email is already taken' : undefined),
          email: lower.includes('email') ? 'Email already registered' : undefined,
        });
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

        <div className="auth-kicker">Register</div>
        <h1 className="auth-title">
          Join <em>the archive</em>.
        </h1>
        <p className="auth-desc">
          Free. Get <strong className="text-accent">10 coins</strong> on signup; earn{' '}
          <strong className="text-accent">+1</strong> for every wallpaper you contribute.
        </p>

        <div className="auth-fields">
          <Field
            label="Username"
            type="text"
            required
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder="archivist"
            autoComplete="username"
            icon={<AiOutlineUser size={15} />}
            help="3–32 chars · letters, numbers, dot, underscore"
            error={errors.username}
          />
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
            autoComplete="new-password"
            icon={<AiOutlineLock size={15} />}
            help="At least 8 characters"
            error={errors.password}
          />
        </div>

        <label className="auth-agree">
          <input
            type="checkbox"
            checked={agreed}
            onChange={(e) => setAgreed(e.target.checked)}
            className="accent-ink"
          />
          <span>
            I accept the{' '}
            <Link to="/terms" target="_blank" className="auth-link">Terms of Service</Link>
            {', '}
            <Link to="/privacy" target="_blank" className="auth-link">Privacy Policy</Link>
            {', and '}
            <Link to="/legal/dmca" target="_blank" className="auth-link">DMCA policy</Link>.
          </span>
        </label>

        <button type="submit" disabled={loading} className="auth-submit">
          {loading ? 'Creating…' : <>Create account · <span className="text-accent">get 10 coins</span></>}
        </button>

        <p className="auth-footnote">
          Already have an account?{' '}
          <Link to="/login" className="auth-footnote-link">Sign in →</Link>
        </p>
      </form>
    </div>
  );
}
