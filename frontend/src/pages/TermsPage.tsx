import { useTranslation } from 'react-i18next';
import usePageTitle from '../hooks/usePageTitle';
import LegalDocument, { type LegalDoc } from '../components/LegalDocument';

// NOTE: the legal body text below intentionally stays in English — legal
// text is only authoritative in its original language. Only the page
// chrome (page title + heading) is localized.
const TERMS_DOC: LegalDoc = {
  title: 'Terms',
  italicTail: 'of service',
  updated: 'May 8, 2026',
  version: 'v1.0',
  toc: [
    '01 · Acceptance',
    '02 · The service',
    '03 · Accounts',
    '04 · Your content',
    '05 · Copyright & DMCA',
    '06 · Coin system',
    '07 · Prohibited conduct',
    '08 · Disclaimers',
    '09 · Liability',
    '10 · Indemnity',
    '11 · Content responsibility',
    '12 · Changes',
    '13 · Termination',
    '14 · Governing law',
    '15 · Contact',
  ],
  body: [
    {
      id: '01', h: 'Acceptance',
      ps: [
        'By accessing or using Wallpaper Exchange ("the Service"), operated at wallpaperexchange.com, you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the Service.',
      ],
    },
    {
      id: '02', h: 'The service',
      ps: [
        'Wallpaper Exchange is a community-driven platform that allows registered users to upload, share, discover, and download wallpapers. The Service operates on a coin-based exchange system where users earn coins by uploading wallpapers and spend coins to download wallpapers uploaded by others.',
      ],
    },
    {
      id: '03', h: 'Accounts',
      ps: [
        'You must provide accurate information when creating an account.',
        'You are responsible for maintaining the security of your account credentials.',
        'You must be at least 13 years of age to use the Service.',
        'One person may not maintain more than one account.',
        'We reserve the right to suspend or terminate accounts that violate these terms.',
      ],
    },
    {
      id: '04', h: 'Your content',
      ps: [
        "You retain ownership of content you upload. By uploading, you grant Wallpaper Exchange a non-exclusive, worldwide, royalty-free license to host, display, distribute, and make derivative works (such as thumbnails and device-specific variants) of the content for the purpose of operating the Service.",
        "You represent and warrant that you own or have the necessary rights to upload the content and that it does not infringe any third party's intellectual property, privacy, or other rights.",
        'You must not upload content that is illegal, obscene, defamatory, threatening, or otherwise objectionable. We reserve the right to remove any content at our sole discretion without prior notice.',
      ],
    },
    {
      id: '05', h: 'Copyright & DMCA',
      ps: [
        'We respect intellectual property rights. If you believe content on Wallpaper Exchange infringes your copyright, please contact us with: identification of the work, identification of the infringing material and its location, your contact information, a good-faith statement, and a statement under penalty of perjury that the information is accurate.',
        'Send DMCA notices to dmca@wallpaperexchange.com.',
      ],
    },
    {
      id: '06', h: 'Coin system',
      ps: [
        'Coins are a virtual credit used solely within the Service and have no monetary value. Coins cannot be purchased, sold, transferred, or exchanged for real currency.',
        'We reserve the right to modify coin values, earning rates, or spending rates at any time. Abuse of the coin system (e.g., creating multiple accounts, uploading duplicate or low-quality content to farm coins) may result in account suspension.',
      ],
    },
    {
      id: '07', h: 'Prohibited conduct',
      ps: [
        'You agree not to: upload content you do not have the rights to share; use automated tools to scrape, download, or interact with the Service; attempt to circumvent the coin system or download protection mechanisms; redistribute downloaded wallpapers on competing platforms for commercial purposes; harass, abuse, or harm other users; or interfere with the proper functioning of the Service.',
      ],
    },
    {
      id: '08', h: 'Disclaimers',
      ps: [
        'THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.',
      ],
    },
    {
      id: '09', h: 'Liability',
      ps: [
        'TO THE MAXIMUM EXTENT PERMITTED BY LAW, WALLPAPER EXCHANGE AND ITS OPERATORS SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING WITHOUT LIMITATION LOSS OF DATA, LOSS OF PROFITS, OR BUSINESS INTERRUPTION, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE SERVICE. OUR TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU HAVE PAID TO US IN THE TWELVE MONTHS PRECEDING THE CLAIM, OR $100 USD, WHICHEVER IS LESS.',
      ],
    },
    {
      id: '10', h: 'Indemnity',
      ps: [
        'You agree to indemnify and hold harmless Wallpaper Exchange, its operators, affiliates, and contributors from any claims, damages, losses, or expenses (including reasonable attorney fees) arising from your use of the Service, your uploaded content, or your violation of these terms.',
      ],
    },
    {
      id: '11', h: 'Content responsibility',
      ps: [
        'Wallpaper Exchange is a platform for user-generated content. We do not pre-screen uploads and are not responsible for content posted by users. The views and content expressed by users do not represent those of Wallpaper Exchange.',
      ],
    },
    {
      id: '12', h: 'Changes',
      ps: [
        'We may revise these terms at any time. Changes become effective upon posting. Continued use of the Service after changes constitutes acceptance of the updated terms. We encourage you to review this page periodically.',
      ],
    },
    {
      id: '13', h: 'Termination',
      ps: [
        'We may terminate or suspend your access to the Service at any time, without prior notice, for conduct that we believe violates these terms or is harmful to other users or the Service. Upon termination, your right to use the Service ceases immediately. Coins and data associated with terminated accounts may be permanently deleted.',
      ],
    },
    {
      id: '14', h: 'Governing law',
      ps: [
        'These terms shall be governed by and construed in accordance with applicable laws, without regard to conflict of law principles. Any disputes arising under these terms shall be resolved in a court of competent jurisdiction.',
      ],
    },
    {
      id: '15', h: 'Contact',
      ps: [
        'If you have questions about these terms, please contact us at support@wallpaperexchange.com.',
      ],
    },
  ],
};

export default function TermsPage() {
  const { t } = useTranslation('about');
  usePageTitle(t('terms.pageTitle'));
  const doc = { ...TERMS_DOC, title: t('terms.title'), italicTail: t('terms.italicTail') };
  return <LegalDocument doc={doc} currentPath="/terms" />;
}
