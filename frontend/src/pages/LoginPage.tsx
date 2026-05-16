import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { AiOutlineMail, AiOutlineLock } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { login } from '../api';
import { resolveBaseURL } from '../api/client';
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
  const existingToken = useAuthStore((s) => s.token);
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const isDesktop = searchParams.get('desktop') === '1';

  // Desktop client opens /login?desktop=1 in ASWebAuthenticationSession. If
  // the user is already signed in to the web (token in localStorage), don't
  // make them re-enter credentials — hand the existing token to the Mac app
  // via the wallxch:// callback. Validate first so we don't pass an expired
  // token (would log the Mac client right back out).
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
    setLoading(true);
    try {
      const res = await login({ email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      track('login_success', { desktop: isDesktop });
      if (isDesktop) {
        window.location.href = `wallxch://auth?token=${encodeURIComponent(token)}`;
        return;
      }
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
    <div className="bg-paper-2 min-h-full flex items-center justify-center px-4 py-12">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-[460px] p-10 bg-paper"
        style={{ border: '1px solid var(--color-hair)', boxShadow: '0 8px 32px rgba(0,0,0,0.04)' }}
      >
        <div className="kicker text-muted">Sign in</div>
        <h1 className="display text-[44px] sm:text-[48px] leading-[0.98] tracking-[-0.02em] mt-2 text-ink">
          Welcome back, <span className="italic-d">archivist.</span>
        </h1>
        <p className="text-[13px] text-ink-2 leading-[1.55] mt-3">
          Sign in to spend coins, save favorites, and upload your own specimens.
        </p>

        <hr className="my-6 border-t border-hair" />

        <div className="flex flex-col gap-[18px]">
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

        <button
          type="submit"
          disabled={loading}
          className="mt-6 w-full py-3.5 bg-ink text-paper text-[14px] font-semibold rounded disabled:opacity-50 hover:bg-ink-2 transition-colors"
        >
          {loading ? 'Signing in…' : 'Sign in →'}
        </button>

        <p className="mt-5 text-center text-[12px] text-muted">
          New to the archive?{' '}
          <Link
            to={isDesktop ? '/register?desktop=1' : '/register'}
            className="text-ink hover:underline font-medium"
          >Register →</Link>
        </p>
      </form>
    </div>
  );
}
