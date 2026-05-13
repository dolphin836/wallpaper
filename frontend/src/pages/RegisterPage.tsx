import { useState, useEffect } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import toast from 'react-hot-toast';
import { register } from '../api';
import { resolveBaseURL } from '../api/client';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';

const INPUT_CLS = 'w-full bg-ws-bg dark:bg-ws-dark-card border-none rounded-xl py-2.5 px-4 text-sm focus:ring-1 focus:ring-ws-purple outline-none transition-all placeholder:text-slate-400 dark:placeholder:text-ws-dark-muted dark:text-white';

export default function RegisterPage() {
  usePageTitle('Register');
  const [username, setUsername] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [agreed, setAgreed] = useState(false);
  const setAuth = useAuthStore((s) => s.setAuth);
  const existingToken = useAuthStore((s) => s.token);
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const isDesktop = searchParams.get('desktop') === '1';

  // Same shortcut as LoginPage: if the desktop client opened this URL but the user
  // is already authenticated in the web session, hand the existing token to the Mac
  // app via wallxch://. Validate first so we don't pass an expired token (would log
  // the Mac client right back out — see LoginPage useEffect for the full reasoning).
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
    if (!agreed) {
      toast.error('Please agree to the Terms of Service and Privacy Policy');
      return;
    }
    setLoading(true);
    try {
      const res = await register({ username, email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      if (isDesktop) {
        window.location.href = `wallxch://auth?token=${encodeURIComponent(token)}`;
        return;
      }
      toast.success('Account created!');
      navigate('/');
    } catch (err: any) {
      toast.error(err.response?.data?.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-[calc(100vh-10rem)] flex items-center justify-center px-4">
      <div className="w-full max-w-md bg-white dark:bg-ws-dark-sidebar rounded-2xl shadow-sm border border-ws-border dark:border-white/5 p-8">
        <h1 className="text-2xl font-bold text-slate-800 dark:text-white text-center mb-8">Create Account</h1>
        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-sm font-medium text-ws-muted dark:text-ws-dark-muted mb-1.5">Username</label>
            <input type="text" required value={username} onChange={(e) => setUsername(e.target.value)} className={INPUT_CLS} placeholder="johndoe" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ws-muted dark:text-ws-dark-muted mb-1.5">Email</label>
            <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className={INPUT_CLS} placeholder="you@example.com" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ws-muted dark:text-ws-dark-muted mb-1.5">Password</label>
            <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} className={INPUT_CLS} placeholder="••••••••" />
          </div>
          <label className="flex items-start gap-2.5 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={agreed}
              onChange={(e) => setAgreed(e.target.checked)}
              className="mt-0.5 w-4 h-4 rounded border-ws-border dark:border-white/20 text-ws-purple focus:ring-ws-purple bg-ws-bg dark:bg-ws-dark-card"
            />
            <span className="text-xs text-ws-muted dark:text-ws-dark-muted leading-relaxed">
              I agree to the{' '}
              <Link to="/terms" className="text-ws-purple hover:underline" target="_blank">Terms of Service</Link>
              {' '}and{' '}
              <Link to="/privacy" className="text-ws-purple hover:underline" target="_blank">Privacy Policy</Link>
            </span>
          </label>
          <button
            type="submit"
            disabled={loading || !agreed}
            className="w-full py-2.5 text-sm font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-xl transition-colors duration-200 disabled:opacity-50 shadow-sm"
          >
            {loading ? 'Creating account...' : 'Create Account'}
          </button>
        </form>
        <p className="mt-6 text-center text-sm text-ws-muted dark:text-ws-dark-muted">
          Already have an account?{' '}
          <Link to={isDesktop ? '/login?desktop=1' : '/login'} className="text-ws-purple hover:underline font-medium">Sign In</Link>
        </p>
      </div>
    </div>
  );
}
