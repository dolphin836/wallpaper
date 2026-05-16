import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { AiOutlineMail, AiOutlineLock, AiOutlineUser } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { register } from '../api';
import { resolveBaseURL } from '../api/client';
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
  const existingToken = useAuthStore((s) => s.token);
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const isDesktop = searchParams.get('desktop') === '1';

  // Same shortcut as LoginPage — see comment there for the full reasoning.
  useEffect(() => {
    if (!isDesktop || !existingToken) return;
    let cancelled = false;
    (async () => {
      try {
        const resp = await fetch(`${resolveBaseURL()}/users/me`, {
          headers: { Authorization: `Bearer ${existingToken}` },
        });
        if (cancelled) return;
        if (resp.ok) {
          window.location.href = `wallxch://auth?token=${encodeURIComponent(existingToken)}`;
        } else {
          useAuthStore.getState().logout();
        }
      } catch {
        if (!cancelled) useAuthStore.getState().logout();
      }
    })();
    return () => { cancelled = true; };
  }, [isDesktop, existingToken]);

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
      track('register_success', { desktop: isDesktop });
      if (isDesktop) {
        window.location.href = `wallxch://auth?token=${encodeURIComponent(token)}`;
        return;
      }
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
    <div className="bg-paper-2 min-h-full flex items-center justify-center px-4 py-12">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-[480px] p-10 bg-paper"
        style={{ border: '1px solid var(--color-hair)', boxShadow: '0 8px 32px rgba(0,0,0,0.04)' }}
      >
        <div className="kicker text-muted">Register</div>
        <h1 className="display text-[40px] sm:text-[44px] leading-[0.98] tracking-[-0.02em] mt-2 text-ink">
          Join <span className="italic-d">the archive.</span>
        </h1>
        <p className="text-[13px] text-ink-2 leading-[1.55] mt-3">
          Free. Get <strong className="text-accent">10 coins</strong> on signup; earn{' '}
          <strong className="text-accent">+5</strong> for every wallpaper you contribute.
        </p>

        <hr className="my-6 border-t border-hair" />

        <div className="flex flex-col gap-[18px]">
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

        <label className="flex items-start gap-2.5 mt-5 text-[12px] text-ink-2 leading-snug cursor-pointer select-none">
          <input
            type="checkbox"
            checked={agreed}
            onChange={(e) => setAgreed(e.target.checked)}
            className="mt-0.5 accent-ink"
          />
          <span>
            I accept the{' '}
            <Link to="/terms" target="_blank" className="text-ink hover:underline">Terms of Service</Link>
            {', '}
            <Link to="/privacy" target="_blank" className="text-ink hover:underline">Privacy Policy</Link>
            {', and '}
            <Link to="/legal/dmca" target="_blank" className="text-ink hover:underline">DMCA policy</Link>.
          </span>
        </label>

        <button
          type="submit"
          disabled={loading}
          className="mt-6 w-full py-3.5 bg-ink text-paper text-[14px] font-semibold rounded disabled:opacity-50 hover:bg-ink-2 transition-colors"
        >
          {loading ? 'Creating…' : <>Create account · <span className="text-accent">get 10 coins</span></>}
        </button>

        <p className="mt-5 text-center text-[12px] text-muted">
          Already have an account?{' '}
          <Link
            to={isDesktop ? '/login?desktop=1' : '/login'}
            className="text-ink hover:underline font-medium"
          >Sign in →</Link>
        </p>
      </form>
    </div>
  );
}
