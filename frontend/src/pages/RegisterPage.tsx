import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import { AiOutlineMail, AiOutlineLock, AiOutlineUser } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { register } from '../api';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';
import { track } from '../lib/track';
import Field from '../components/Field';

export default function RegisterPage() {
  const { t } = useTranslation('auth');
  usePageTitle(t('register.pageTitle'));
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
      toast.error(t('register.errAcceptTerms'));
      return;
    }
    setLoading(true);
    try {
      const res = await register({ username, email, password });
      const { token, user } = res.data.data;
      setAuth(token, user);
      track('register_success');
      toast.success(t('register.toastCreated'));
      navigate('/');
    } catch (err: unknown) {
      const e = err as { response?: { status?: number; data?: { message?: string; code?: number } } };
      const msg = e?.response?.data?.message || t('register.errFailed');
      // 40901 = username/email already taken. Backend doesn't tell us which,
      // so we hint at both fields with a generic conflict line.
      if (e?.response?.status === 409 || e?.response?.data?.code === 40901) {
        const lower = msg.toLowerCase();
        setErrors({
          username: lower.includes('username') ? t('register.errUsernameTaken') : (!lower.includes('email') ? t('register.errConflict') : undefined),
          email: lower.includes('email') ? t('register.errEmailRegistered') : undefined,
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

        <div className="auth-kicker">{t('register.kicker')}</div>
        <h1 className="auth-title">
          <Trans i18nKey="register.title" ns="auth" components={[<em key="0" />]} />
        </h1>
        <p className="auth-desc">
          <Trans
            i18nKey="register.desc"
            ns="auth"
            components={[
              <strong key="0" className="text-accent" />,
              <strong key="1" className="text-accent" />,
            ]}
          />
        </p>

        <div className="auth-fields">
          <Field
            label={t('form.username')}
            type="text"
            required
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            placeholder={t('form.usernamePlaceholder')}
            autoComplete="username"
            icon={<AiOutlineUser size={15} />}
            help={t('form.usernameHelp')}
            error={errors.username}
          />
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
            autoComplete="new-password"
            icon={<AiOutlineLock size={15} />}
            help={t('form.passwordHelp')}
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
            <Trans
              i18nKey="register.agree"
              ns="auth"
              components={[
                <Link key="0" to="/terms" target="_blank" className="auth-link" />,
                <Link key="1" to="/privacy" target="_blank" className="auth-link" />,
                <Link key="2" to="/legal/dmca" target="_blank" className="auth-link" />,
              ]}
            />
          </span>
        </label>

        <button type="submit" disabled={loading} className="auth-submit">
          {loading
            ? t('register.submitting')
            : <Trans i18nKey="register.submit" ns="auth" components={[<span key="0" className="text-accent" />]} />}
        </button>

        <p className="auth-footnote">
          {t('register.footnote')}{' '}
          <Link to="/login" className="auth-footnote-link">{t('register.footnoteLink')}</Link>
        </p>
      </form>
    </div>
  );
}
