import { Link } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';

export default function TermsPage() {
  usePageTitle('Terms of Service');

  return (
    <div className="max-w-3xl mx-auto px-6 py-10">
      <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2">Terms of Service</h1>
      <p className="text-sm text-ws-muted dark:text-ws-dark-muted mb-10">Last updated: May 8, 2026</p>

      <div className="prose prose-slate dark:prose-invert prose-sm max-w-none space-y-8 text-slate-700 dark:text-slate-300 leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">1. Acceptance of Terms</h2>
          <p>
            By accessing or using Wallpaper Exchange ("the Service"), operated at wallpaperexchange.com, you agree to be
            bound by these Terms of Service. If you do not agree to these terms, please do not use the Service.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">2. Description of Service</h2>
          <p>
            Wallpaper Exchange is a community-driven platform that allows registered users to upload, share, discover, and
            download wallpapers. The Service operates on a coin-based exchange system where users earn coins by uploading
            wallpapers and spend coins to download wallpapers uploaded by others.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">3. User Accounts</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>You must provide accurate information when creating an account.</li>
            <li>You are responsible for maintaining the security of your account credentials.</li>
            <li>You must be at least 13 years of age to use the Service.</li>
            <li>One person may not maintain more than one account.</li>
            <li>We reserve the right to suspend or terminate accounts that violate these terms.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">4. User-Uploaded Content</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>You retain ownership of content you upload. By uploading, you grant Wallpaper Exchange a non-exclusive,
              worldwide, royalty-free license to host, display, distribute, and make derivative works (such as thumbnails
              and device-specific variants) of the content for the purpose of operating the Service.</li>
            <li>You represent and warrant that you own or have the necessary rights to upload the content and that it does
              not infringe any third party's intellectual property, privacy, or other rights.</li>
            <li>You must not upload content that is illegal, obscene, defamatory, threatening, or otherwise objectionable.</li>
            <li>We reserve the right to remove any content at our sole discretion without prior notice.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">5. Copyright &amp; DMCA</h2>
          <p>
            We respect intellectual property rights. If you believe content on Wallpaper Exchange infringes your copyright,
            please contact us with the following information:
          </p>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Identification of the copyrighted work claimed to have been infringed.</li>
            <li>Identification of the infringing material and its location on the Service.</li>
            <li>Your contact information (name, email address).</li>
            <li>A statement that you have a good-faith belief the use is not authorized.</li>
            <li>A statement, under penalty of perjury, that the information is accurate and you are authorized to act on behalf of the copyright owner.</li>
          </ul>
          <p>Send DMCA notices to: <strong>dmca@wallpaperexchange.com</strong></p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">6. Coin System</h2>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Coins are a virtual currency used solely within the Service and have no monetary value.</li>
            <li>Coins cannot be purchased, sold, transferred, or exchanged for real currency.</li>
            <li>We reserve the right to modify coin values, earning rates, or spending rates at any time.</li>
            <li>Abuse of the coin system (e.g., creating multiple accounts, uploading duplicate or low-quality content to
              farm coins) may result in account suspension.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">7. Prohibited Conduct</h2>
          <p>You agree not to:</p>
          <ul className="list-disc pl-5 space-y-1.5">
            <li>Upload content you do not have the rights to share.</li>
            <li>Use automated tools to scrape, download, or interact with the Service.</li>
            <li>Attempt to circumvent the coin system or download protection mechanisms.</li>
            <li>Redistribute downloaded wallpapers on competing platforms for commercial purposes.</li>
            <li>Harass, abuse, or harm other users.</li>
            <li>Interfere with the proper functioning of the Service.</li>
          </ul>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">8. Disclaimer of Warranties</h2>
          <p>
            THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, WHETHER EXPRESS OR IMPLIED,
            INCLUDING BUT NOT LIMITED TO IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND
            NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE SERVICE WILL BE UNINTERRUPTED, ERROR-FREE, OR SECURE.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">9. Limitation of Liability</h2>
          <p>
            TO THE MAXIMUM EXTENT PERMITTED BY LAW, WALLPAPER EXCHANGE AND ITS OPERATORS SHALL NOT BE LIABLE FOR ANY
            INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING WITHOUT LIMITATION LOSS OF DATA,
            LOSS OF PROFITS, OR BUSINESS INTERRUPTION, ARISING OUT OF OR IN CONNECTION WITH YOUR USE OF THE SERVICE. OUR
            TOTAL LIABILITY SHALL NOT EXCEED THE AMOUNT YOU HAVE PAID TO US IN THE TWELVE MONTHS PRECEDING THE CLAIM,
            OR $100 USD, WHICHEVER IS LESS.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">10. Indemnification</h2>
          <p>
            You agree to indemnify and hold harmless Wallpaper Exchange, its operators, affiliates, and contributors from
            any claims, damages, losses, or expenses (including reasonable attorney fees) arising from your use of the
            Service, your uploaded content, or your violation of these terms.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">11. Content Responsibility</h2>
          <p>
            Wallpaper Exchange is a platform for user-generated content. We do not pre-screen uploads and are not
            responsible for content posted by users. The views and content expressed by users do not represent those of
            Wallpaper Exchange.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">12. Modifications to Terms</h2>
          <p>
            We may revise these terms at any time. Changes become effective upon posting. Continued use of the Service
            after changes constitutes acceptance of the updated terms. We encourage you to review this page periodically.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">13. Termination</h2>
          <p>
            We may terminate or suspend your access to the Service at any time, without prior notice, for conduct that we
            believe violates these terms or is harmful to other users or the Service. Upon termination, your right to use
            the Service ceases immediately. Coins and data associated with terminated accounts may be permanently deleted.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">14. Governing Law</h2>
          <p>
            These terms shall be governed by and construed in accordance with applicable laws, without regard to conflict
            of law principles. Any disputes arising under these terms shall be resolved in a court of competent
            jurisdiction.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-slate-900 dark:text-white">15. Contact</h2>
          <p>
            If you have questions about these terms, please contact us at <strong>support@wallpaperexchange.com</strong>.
          </p>
        </section>
      </div>

      <div className="mt-10 pt-6 border-t border-ws-border dark:border-white/5 text-sm text-ws-muted dark:text-ws-dark-muted">
        See also: <Link to="/privacy" className="text-ws-purple hover:underline">Privacy Policy</Link>
      </div>
    </div>
  );
}
