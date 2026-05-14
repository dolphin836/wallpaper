import PageMeta from '../components/PageMeta';

const CONTACT_EMAIL = 'copyright@wallpaperexchange.com';

export default function LegalDmcaPage() {
  return (
    <div className="max-w-3xl mx-auto px-6 py-10 text-slate-700 dark:text-slate-300 leading-relaxed">
      <PageMeta
        title="Copyright / DMCA"
        description="How to report copyright infringement on Wallpaper Exchange and how we handle takedown notices."
      />

      <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2">Copyright / DMCA</h1>
      <p className="text-sm text-ws-muted dark:text-ws-dark-muted mb-8">Last updated: 2026-05-14</p>

      <section className="space-y-4 mb-8">
        <p>
          Wallpaper Exchange is a user-driven catalog: anyone with an account can upload wallpapers.
          We respect the intellectual-property rights of others and respond to credible copyright
          claims under the principles of the U.S. Digital Millennium Copyright Act (DMCA) and
          equivalent local frameworks.
        </p>
        <p>
          If you believe that material on this site infringes your copyright, please send a notice
          to the address below containing the information listed in the next section. We typically
          remove or restrict access to clearly-infringing material within <strong>3 business days</strong> of
          receiving a complete notice.
        </p>
      </section>

      <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-3">Where to send notices</h2>
      <div className="bg-ws-bg dark:bg-ws-dark-bg border border-ws-border dark:border-white/5 rounded-xl p-5 mb-8">
        <p className="mb-2"><strong>Designated copyright agent:</strong></p>
        <p className="font-mono text-sm">{CONTACT_EMAIL}</p>
      </div>

      <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-3">What to include</h2>
      <ol className="list-decimal list-inside space-y-2 mb-8">
        <li>An identification of the copyrighted work you claim has been infringed.</li>
        <li>The URL of the specific wallpaper(s) on Wallpaper Exchange you're asking us to remove.</li>
        <li>Your contact information (email + physical address).</li>
        <li>
          A statement that you have a good-faith belief that the use is not authorized by the
          copyright owner, its agent, or the law.
        </li>
        <li>
          A statement, under penalty of perjury, that the information in the notice is accurate
          and that you are the copyright owner or are authorized to act on the owner's behalf.
        </li>
        <li>Your physical or electronic signature.</li>
      </ol>

      <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-3">Counter-notice</h2>
      <p className="mb-4">
        If you uploaded a wallpaper that was removed and you believe it was a mistake (e.g.,
        the work is yours, or your use is fair use), send a counter-notice to the same address
        with: your identification of the removed material, your contact info, a statement under
        penalty of perjury that the removal was a mistake or misidentification, and your consent
        to local-court jurisdiction.
      </p>

      <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-3">Repeat infringers</h2>
      <p className="mb-8">
        Accounts that receive multiple substantiated copyright claims will be terminated.
      </p>

      <h2 className="text-xl font-semibold text-slate-900 dark:text-white mb-3">In-app reports</h2>
      <p>
        For other content concerns that aren't copyright issues (NSFW, spam, low quality), use
        the <em>Report</em> button on the wallpaper detail page. Those reports go to the same
        moderation queue as DMCA notices but are handled under our community guidelines rather
        than copyright law.
      </p>
    </div>
  );
}
