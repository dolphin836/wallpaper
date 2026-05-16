import usePageTitle from '../hooks/usePageTitle';
import LegalDocument, { type LegalDoc } from '../components/LegalDocument';

const PRIVACY_DOC: LegalDoc = {
  title: 'Privacy',
  italicTail: 'policy',
  updated: 'May 8, 2026',
  version: 'v1.0',
  toc: [
    '01 · What we collect',
    '02 · How we use it',
    '03 · Sharing',
    '04 · Storage & security',
    '05 · Cookies & local storage',
    '06 · Your rights',
    '07 · Children',
    '08 · Retention',
    '09 · Changes',
    '10 · Contact',
  ],
  body: [
    {
      id: '01', h: 'What we collect',
      ps: [
        'Account information: when you register, we collect your username, email address, and a hashed version of your password. We do not store plain-text passwords.',
        'Usage data: we collect information about how you interact with the Service, including uploads, downloads, likes, favorites, and coin transactions. This data is used to operate the coin system and provide personalized features.',
        'Device information: when you use the device-matching feature, your screen resolution is sent to the server to find wallpapers that fit your device. This information is not stored permanently.',
        'Uploaded content: wallpapers you upload are stored on our servers. Metadata such as resolution, file size, dominant colors, and file type are extracted and stored alongside the image.',
      ],
    },
    {
      id: '02', h: 'How we use it',
      ps: [
        'To operate, maintain, and improve the Service. To process coin transactions and track upload/download activity. To generate device-specific wallpaper variants for optimal display. To display your public profile (username, avatar, uploaded wallpapers) to other users. To communicate important updates about the Service or your account. To enforce our Terms of Service and prevent abuse.',
      ],
    },
    {
      id: '03', h: 'Sharing',
      ps: [
        'We do not sell, trade, or rent your personal information to third parties.',
        'Public content: wallpapers you upload and your public profile are visible to all users.',
        'Legal requirements: we may disclose information if required by law, court order, or governmental request.',
        'Service providers: we may share data with trusted service providers who help operate the Service (e.g., hosting, storage), subject to confidentiality obligations.',
        'Safety: we may share information when we believe it is necessary to protect the rights, safety, or property of the Service, our users, or the public.',
      ],
    },
    {
      id: '04', h: 'Storage & security',
      ps: [
        'Your data is stored on secured servers. We implement reasonable technical and organizational measures to protect your information, including encrypted password storage, secure HTTPS connections, and access controls. However, no system is completely secure, and we cannot guarantee absolute security.',
      ],
    },
    {
      id: '05', h: 'Cookies & local storage',
      ps: [
        'We use browser local storage and session storage to maintain your login session, remember your preferences (such as theme and view mode), and cache scroll position for a better browsing experience. We do not use third-party tracking cookies.',
      ],
    },
    {
      id: '06', h: 'Your rights',
      ps: [
        'Access the personal data we hold about you.',
        'Correct inaccurate information in your profile.',
        'Delete your uploaded wallpapers at any time.',
        'Request account deletion by contacting us. Upon deletion, your personal data and uploaded content will be permanently removed. Note that wallpapers already downloaded by other users cannot be recalled.',
      ],
    },
    {
      id: '07', h: 'Children',
      ps: [
        'The Service is not intended for children under the age of 13. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided us with personal information, we will take steps to delete it.',
      ],
    },
    {
      id: '08', h: 'Retention',
      ps: [
        'We retain your account information and uploaded content for as long as your account is active. If you delete your account, we will delete your personal data within 30 days, except where we are required to retain it for legal or legitimate business purposes.',
      ],
    },
    {
      id: '09', h: 'Changes',
      ps: [
        'We may update this Privacy Policy from time to time. We will notify you of material changes by posting the new policy on this page with an updated "Last updated" date. Your continued use of the Service after changes constitutes acceptance of the updated policy.',
      ],
    },
    {
      id: '10', h: 'Contact',
      ps: [
        'If you have questions about this Privacy Policy or wish to exercise your data rights, please contact us at privacy@wallpaperexchange.com.',
      ],
    },
  ],
};

export default function PrivacyPage() {
  usePageTitle('Privacy Policy');
  return <LegalDocument doc={PRIVACY_DOC} currentPath="/privacy" />;
}
