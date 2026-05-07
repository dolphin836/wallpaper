import { Link } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';

export default function PrivacyPage() {
  usePageTitle('Privacy Policy');

  return (
    <div className="max-w-3xl mx-auto px-6 py-10">
      <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2">Privacy Policy</h1>
      <p className="text-sm text-ws-muted dark:text-ws-dark-muted mb-10">Last updated: May 8, 2026</p>

      <div className="prose prose-slate dark:prose-invert prose-sm max-w-none space-y-8 text-slate-700 dark:text-slate-300 leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">1. Information We Collect</h2>
          <h3 className="text-base font-medium text-slate-800 dark:text-slate-200 mt-4">Account Information</h3>
          <p>
            When you register, we collect your username, email address, and a hashed version of your password. We do not
            store plain-text passwords.
          </p>
          <h3 className="text-base font-medium text-slate-800 dark:text-slate-200 mt-4">Usage Data</h3>
          <p>
            We collect information about how you interact with the Service, including uploads, downloads, likes, favorites,
            and coin transactions. This data is used to operate the coin system and provide personalized features.
          </p>
          <h3 className="text-base font-medium text-slate-800 dark:text-slate-200 mt-4">Device Information</h3>
          <p>
            When you use the device-matching feature, your screen resolution is sent to the server to find wallpapers
            that fit your device. This information is not stored permanently.
          </p>
          <h3 className="text-base font-medium text-slate-800 dark:text-slate-200 mt-4">Uploaded Content</h3>
          <p>
            Wallpapers you upload are stored on our servers. Metadata such as resolution, file size, dominant colors, and
            file type are extracted and stored alongside the image.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">2. How We Use Your Information</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>To operate, maintain, and improve the Service.</li>
            <li>To process coin transactions and track upload/download activity.</li>
            <li>To generate device-specific wallpaper variants for optimal display.</li>
            <li>To display your public profile (username, avatar, uploaded wallpapers) to other users.</li>
            <li>To communicate important updates about the Service or your account.</li>
            <li>To enforce our Terms of Service and prevent abuse.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">3. Information Sharing</h2>
          <p>We do not sell, trade, or rent your personal information to third parties. We may share information only in the following circumstances:</p>
          <ul className="list-disc pl-5 space-y-1.5">
            <li><strong>Public content:</strong> Wallpapers you upload and your public profile are visible to all users.</li>
            <li><strong>Legal requirements:</strong> We may disclose information if required by law, court order, or governmental request.</li>
            <li><strong>Service providers:</strong> We may share data with trusted service providers who help operate the Service (e.g., hosting, storage), subject to confidentiality obligations.</li>
            <li><strong>Safety:</strong> We may share information when we believe it is necessary to protect the rights, safety, or property of the Service, our users, or the public.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">4. Data Storage &amp; Security</h2>
          <p>
            Your data is stored on secured servers. We implement reasonable technical and organizational measures to protect
            your information, including encrypted password storage, secure HTTPS connections, and access controls.
            However, no system is completely secure, and we cannot guarantee absolute security.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">5. Cookies &amp; Local Storage</h2>
          <p>
            We use browser local storage and session storage to maintain your login session, remember your preferences
            (such as theme and view mode), and cache scroll position for a better browsing experience. We do not use
            third-party tracking cookies.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">6. Your Rights</h2>
          <p>You have the right to:</p>
          <ul className="list-disc pl-5 space-y-1.5">
            <li><strong>Access</strong> the personal data we hold about you.</li>
            <li><strong>Correct</strong> inaccurate information in your profile.</li>
            <li><strong>Delete</strong> your uploaded wallpapers at any time.</li>
            <li><strong>Request account deletion</strong> by contacting us. Upon deletion, your personal data and uploaded
              content will be permanently removed. Note that wallpapers already downloaded by other users cannot be recalled.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">7. Children's Privacy</h2>
          <p>
            The Service is not intended for children under the age of 13. We do not knowingly collect personal information
            from children under 13. If we become aware that a child under 13 has provided us with personal information,
            we will take steps to delete it.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">8. Data Retention</h2>
          <p>
            We retain your account information and uploaded content for as long as your account is active. If you delete
            your account, we will delete your personal data within 30 days, except where we are required to retain it for
            legal or legitimate business purposes.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">9. Changes to This Policy</h2>
          <p>
            We may update this Privacy Policy from time to time. We will notify you of material changes by posting the
            new policy on this page with an updated "Last updated" date. Your continued use of the Service after changes
            constitutes acceptance of the updated policy.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">10. Contact</h2>
          <p>
            If you have questions about this Privacy Policy or wish to exercise your data rights, please contact us
            at <strong>privacy@wallpaperexchange.com</strong>.
          </p>
        </section>
      </div>

      <div className="mt-10 pt-6 border-t border-ws-border dark:border-white/5 text-sm text-ws-muted dark:text-ws-dark-muted">
        See also: <Link to="/terms" className="text-ws-purple hover:underline">Terms of Service</Link>
      </div>
    </div>
  );
}
