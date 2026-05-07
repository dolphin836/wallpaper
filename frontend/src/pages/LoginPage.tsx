import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { login } from '../api';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';

const INPUT_CLS = 'w-full bg-ws-bg dark:bg-ws-dark-card border-none rounded-xl py-2.5 px-4 text-sm focus:ring-1 focus:ring-ws-purple outline-none transition-all placeholder:text-slate-400 dark:placeholder:text-ws-dark-muted dark:text-white';

export default function LoginPage() {
  usePageTitle('Login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const setAuth = useAuthStore((s) => s.setAuth);
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      const res = await login({ email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      toast.success('Welcome back!');
      navigate('/');
    } catch (err: any) {
      toast.error(err.response?.data?.message || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-[calc(100vh-10rem)] flex items-center justify-center px-4">
      <div className="w-full max-w-md bg-white dark:bg-ws-dark-sidebar rounded-2xl shadow-sm border border-ws-border dark:border-white/5 p-8">
        <h1 className="text-2xl font-bold text-slate-800 dark:text-white text-center mb-8">Sign In</h1>
        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-sm font-medium text-ws-muted dark:text-ws-dark-muted mb-1.5">Email</label>
            <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className={INPUT_CLS} placeholder="you@example.com" />
          </div>
          <div>
            <label className="block text-sm font-medium text-ws-muted dark:text-ws-dark-muted mb-1.5">Password</label>
            <input type="password" required value={password} onChange={(e) => setPassword(e.target.value)} className={INPUT_CLS} placeholder="••••••••" />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 text-sm font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-xl transition-colors duration-200 disabled:opacity-50 shadow-sm"
          >
            {loading ? 'Signing in...' : 'Sign In'}
          </button>
        </form>
        <p className="mt-6 text-center text-sm text-ws-muted dark:text-ws-dark-muted">
          Don&apos;t have an account?{' '}
          <Link to="/register" className="text-ws-purple hover:underline font-medium">Register</Link>
        </p>
      </div>
    </div>
  );
}
