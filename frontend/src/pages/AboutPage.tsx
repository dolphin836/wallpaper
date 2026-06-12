import { Link } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import PageMeta from '../components/PageMeta';

// Editorial /about page. Intentionally short — the goal isn't to recite
// marketing copy, it's to give a new visitor (or a Google reviewer) one
// scrollable page that answers "what is this and who runs it." Anything
// dynamic (counts, leaderboards) lives elsewhere.
export default function AboutPage() {
  const { t } = useTranslation('about');
  return (
    <div className="legal-page min-h-full">
      <div className="legal-mesh" aria-hidden />
      <PageMeta
        title={t('about.metaTitle')}
        description={t('about.metaDescription')}
      />

      <div className="relative z-10 px-6 sm:px-10 lg:px-14 py-12 max-w-[1600px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-10">
          <div className="kicker text-muted">{t('about.kicker')}</div>
          <h1 className="display text-[40px] sm:text-[56px] leading-[1.02] mt-2 tracking-[-0.015em] text-ink">
            <Trans i18nKey="about.title" ns="about" components={[<em key="0" className="legal-title-tail" />]} />
          </h1>
          <p className="text-[16px] leading-[1.55] text-ink-2 mt-5 max-w-[640px]">
            {t('about.intro')}
          </p>
        </header>

        {/* ─── Why this exists ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('about.whyLabel')}</div>
          <div className="space-y-4 text-[14.5px] leading-[1.65] text-ink-2">
            <p>{t('about.whyP1')}</p>
            <p>{t('about.whyP2')}</p>
          </div>
        </section>

        {/* ─── How it actually works ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('about.howLabel')}</div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            <Pillar n="01" t={t('about.pillar1Title')} p={t('about.pillar1Text')} />
            <Pillar n="02" t={t('about.pillar2Title')} p={t('about.pillar2Text')} />
            <Pillar n="03" t={t('about.pillar3Title')} p={t('about.pillar3Text')} />
          </div>
        </section>

        {/* ─── Made by ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">{t('about.madeByLabel')}</div>
          <p className="text-[14.5px] leading-[1.65] text-ink-2">
            <Trans
              i18nKey="about.madeByText"
              ns="about"
              components={[<a key="0" className="text-ink underline" href="mailto:hello@wallpaperexchange.com" />]}
            />
          </p>
        </section>

        {/* ─── CTA ─── */}
        <section className="pt-2 flex flex-wrap gap-3">
          <Link
            to="/"
            className="inline-flex items-center px-5 py-2.5 rounded-full bg-ink text-paper text-[13px] font-medium no-underline hover:bg-ink-2 transition-colors"
          >
            {t('about.ctaBrowse')}
          </Link>
          <Link
            to="/contribute"
            className="inline-flex items-center px-5 py-2.5 rounded-full bg-paper text-ink border border-hair text-[13px] font-medium no-underline hover:bg-paper-2 hover:border-ink-2 transition-colors"
          >
            {t('about.ctaContribute')}
          </Link>
        </section>

      </div>
    </div>
  );
}

// One of the three "how it works" pillars. Mono number on top, serif
// title under it, sans body underneath.
function Pillar({ n, t, p }: { n: string; t: string; p: string }) {
  return (
    <div>
      <div className="mono text-[10px] tracking-[0.14em] uppercase text-muted mb-2">{n}</div>
      <div className="display text-[20px] leading-[1.15] text-ink">{t}</div>
      <p className="text-[13px] leading-[1.6] text-ink-2 mt-2">{p}</p>
    </div>
  );
}
