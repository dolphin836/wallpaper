import { useTranslation } from 'react-i18next';
import usePageTitle from '../hooks/usePageTitle';
import PageMeta from '../components/PageMeta';
import LegalDocument, { type LegalDoc } from '../components/LegalDocument';

const CONTACT_EMAIL = 'copyright@wallpaperexchange.com';

// NOTE: the legal body text below intentionally stays in English — legal
// text is only authoritative in its original language. Only the page
// chrome (page title / meta + heading) is localized.

const DMCA_DOC: LegalDoc = {
  title: 'Copyright',
  italicTail: '/ DMCA',
  updated: '2026-05-14',
  version: 'v1.0',
  toc: [
    '01 · Overview',
    '02 · Where to send notices',
    '03 · What to include',
    '04 · Counter-notice',
    '05 · Repeat infringers',
    '06 · In-app reports',
  ],
  body: [
    {
      id: '01', h: 'Overview',
      ps: [
        'Wallpaper Exchange is a user-driven catalog: anyone with an account can upload wallpapers. We respect the intellectual-property rights of others and respond to credible copyright claims under the principles of the U.S. Digital Millennium Copyright Act (DMCA) and equivalent local frameworks.',
        'If you believe that material on this site infringes your copyright, please send a notice to the address below containing the information listed in the next section. We typically remove or restrict access to clearly-infringing material within 3 business days of receiving a complete notice.',
      ],
    },
    {
      id: '02', h: 'Where to send notices',
      ps: [
        <>Designated copyright agent: <strong className="text-ink mono">{CONTACT_EMAIL}</strong></>,
      ],
    },
    {
      id: '03', h: 'What to include',
      ps: [
        'An identification of the copyrighted work you claim has been infringed.',
        "The URL of the specific wallpaper(s) on Wallpaper Exchange you're asking us to remove.",
        'Your contact information (email + physical address).',
        "A statement that you have a good-faith belief that the use is not authorized by the copyright owner, its agent, or the law.",
        "A statement, under penalty of perjury, that the information in the notice is accurate and that you are the copyright owner or are authorized to act on the owner's behalf.",
        'Your physical or electronic signature.',
      ],
    },
    {
      id: '04', h: 'Counter-notice',
      ps: [
        'If you uploaded a wallpaper that was removed and you believe it was a mistake (e.g., the work is yours, or your use is fair use), send a counter-notice to the same address with: your identification of the removed material, your contact info, a statement under penalty of perjury that the removal was a mistake or misidentification, and your consent to local-court jurisdiction.',
      ],
    },
    {
      id: '05', h: 'Repeat infringers',
      ps: [
        'Accounts that receive multiple substantiated copyright claims will be terminated.',
      ],
    },
    {
      id: '06', h: 'In-app reports',
      ps: [
        "For other content concerns that aren't copyright issues (NSFW, spam, low quality), use the Report button on the wallpaper detail page. Those reports go to the same moderation queue as DMCA notices but are handled under our community guidelines rather than copyright law.",
      ],
    },
  ],
};

export default function LegalDmcaPage() {
  const { t } = useTranslation('about');
  usePageTitle(t('dmca.pageTitle'));
  const doc = { ...DMCA_DOC, title: t('dmca.title'), italicTail: t('dmca.italicTail') };
  return (
    <>
      <PageMeta
        title={t('dmca.pageTitle')}
        description={t('dmca.metaDescription')}
      />
      <LegalDocument doc={doc} currentPath="/legal/dmca" />
    </>
  );
}
