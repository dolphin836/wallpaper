import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import { AiOutlineMail, AiOutlineLock } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { login } from '../api';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';
import { track } from '../lib/track';
import Field from '../components/Field';

export default function LoginPage() {
  const { t } = useTranslation('auth');
  usePageTitle(t('login.pageTitle'));
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
      toast.success(t('login.toastWelcome'));
      navigate('/');
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string; code?: number } } };
      const msg = e?.response?.data?.message || t('login.errFailed');
      // 40103 = wrong password (mostly hits the password field). 40400 =
      // user not found. Both signal "email/password mismatch" to the user.
      const code = e?.response?.data?.code;
      if (code === 40103 || code === 40400) {
        setErrors({ password: t('login.errCredentials') });
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

        <div className="auth-kicker">{t('login.kicker')}</div>
        <h1 className="auth-title">
          <Trans i18nKey="login.title" ns="auth" components={[<em key="0" />]} />
        </h1>
        <p className="auth-desc">
          {t('login.desc')}
        </p>

        <div className="auth-fields">
          <Field
            label={t('form.email')}
            type="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder={t('form.emailPlaceholder')}
            autoComplete="email"
            icon={<AiOutlineMail size={15} />}
            error={errors.email}
          />
          <Field
            label={t('form.password')}
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
          {loading ? t('login.submitting') : <>{t('login.submit')} <span aria-hidden>→</span></>}
        </button>

        <p className="auth-footnote">
          {t('login.footnote')}{' '}
          <Link to="/register" className="auth-footnote-link">{t('login.footnoteLink')}</Link>
        </p>
      </form>
    </div>
  );
}
