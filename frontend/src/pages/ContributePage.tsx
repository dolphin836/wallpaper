import { Link } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import PageMeta from '../components/PageMeta';
import { useAuthStore } from '../store/auth';

// Editorial /contribute landing — aimed at would-be wallpaper artists.
// Three value props (auto-variants / coins / curation), three-step
// "how to start", a short quality bar, and a single primary CTA that
// sends them straight into /upload (or /register first if signed out).
export default function ContributePage() {
  const { t } = useTranslation('about');
  const { isAuthenticated } = useAuthStore();
  const startPath = isAuthenticated ? '/upload' : '/register';

  return (
    <div className="legal-page min-h-full">
      <div className="legal-mesh" aria-hidden />
      <PageMeta
        title={t('contribute.metaTitle')}
        description={t('contribute.metaDescription')}
      />

      <div className="relative z-10 px-6 sm:px-10 lg:px-14 py-12 max-w-[1600px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-10">
          <div className="kicker text-muted">{t('contribute.kicker')}</div>
          <h1 className="display text-[40px] sm:text-[56px] leading-[1.02] mt-2 tracking-[-0.015em] text-ink">
            <Trans i18nKey="contribute.title" ns="about" components={[<em key="0" className="legal-title-tail" />]} />
          </h1>
          <p className="text-[16px] leading-[1.55] text-ink-2 mt-5 max-w-[640px]">
            {t('contribute.intro')}
          </p>
        </header>

        {/* ─── Why upload here ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('contribute.whatLabel')}</div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            <Pillar n="01" t={t('contribute.pillar1Title')} p={t('contribute.pillar1Text')} />
            <Pillar n="02" t={t('contribute.pillar2Title')} p={t('contribute.pillar2Text')} />
            <Pillar n="03" t={t('contribute.pillar3Title')} p={t('contribute.pillar3Text')} />
          </div>
        </section>

        {/* ─── How to start ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('contribute.startLabel')}</div>
          <ol className="space-y-5 text-[14.5px] leading-[1.6] text-ink-2 list-none p-0 m-0">
            <Step n="01" t={t('contribute.step1Title')} p={t('contribute.step1Text')} />
            <Step n="02" t={t('contribute.step2Title')} p={t('contribute.step2Text')} />
            <Step n="03" t={t('contribute.step3Title')} p={t('contribute.step3Text')} />
          </ol>
        </section>

        {/* ─── Quality bar ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('contribute.qualityLabel')}</div>
          <ul className="space-y-2 text-[14px] leading-[1.6] text-ink-2 list-none p-0 m-0">
            {(['quality1', 'quality2', 'quality3', 'quality4'] as const).map((key) => (
              <li key={key} className="flex gap-3">
                <span className="mono text-[11px] tracking-[0.06em] text-muted shrink-0 mt-[2px]">→</span>
                <span><Trans i18nKey={`contribute.${key}`} ns="about" components={[<strong key="0" className="text-ink" />]} /></span>
              </li>
            ))}
          </ul>
        </section>

        {/* ─── CTA ─── */}
        <section className="pt-2 border-t border-hair pt-7 flex flex-wrap gap-3 items-center">
          <Link
            to={startPath}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-accent text-white text-[13px] font-semibold no-underline hover:brightness-95 transition-all"
          >
            {isAuthenticated ? t('contribute.ctaUpload') : t('contribute.ctaSignUp')}
          </Link>
          <Link
            to="/terms"
            className="text-[12px] text-muted no-underline hover:text-ink-2"
          >
            {t('contribute.readTerms')}
          </Link>
        </section>

      </div>
    </div>
  );
}

function Pillar({ n, t, p }: { n: string; t: string; p: string }) {
  return (
    <div>
      <div className="mono text-[10px] tracking-[0.14em] uppercase text-muted mb-2">{n}</div>
      <div className="display text-[20px] leading-[1.15] text-ink">{t}</div>
      <p className="text-[13px] leading-[1.6] text-ink-2 mt-2">{p}</p>
    </div>
  );
}

function Step({ n, t, p }: { n: string; t: string; p: string }) {
  return (
    <li className="grid grid-cols-[36px_1fr] gap-4 items-start">
      <span className="mono text-[11px] tracking-[0.14em] text-muted pt-1">{n}</span>
      <div>
        <div className="display text-[19px] leading-[1.15] text-ink">{t}</div>
        <p className="text-[13.5px] leading-[1.6] text-ink-2 mt-1.5">{p}</p>
      </div>
    </li>
  );
}
