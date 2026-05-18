import { Link } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import { useAuthStore } from '../store/auth';

// Editorial /contribute landing — aimed at would-be wallpaper artists.
// Three value props (auto-variants / coins / curation), three-step
// "how to start", a short quality bar, and a single primary CTA that
// sends them straight into /upload (or /register first if signed out).
export default function ContributePage() {
  const { isAuthenticated } = useAuthStore();
  const startPath = isAuthenticated ? '/upload' : '/register';

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title="Contribute"
        description="Upload your wallpapers to Wallpaper Exchange. We auto-generate variants for forty-plus device profiles, you earn a coin per accepted upload, and the best work gets featured."
      />

      <div className="px-6 sm:px-10 pt-7 pb-12 max-w-[820px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-10">
          <div className="kicker text-muted">Contribute · For wallpaper artists</div>
          <h1 className="display text-[40px] sm:text-[56px] leading-[0.96] mt-2 tracking-[-0.02em] text-ink">
            Your wallpaper, <span className="italic-d">forty devices,</span> one upload.
          </h1>
          <p className="text-[16px] leading-[1.55] text-ink-2 mt-5 max-w-[640px]">
            Drop a single high-resolution file. We crop and resize it
            for every device profile in our library, store the
            originals, and serve whichever one fits the visitor's
            current screen. You don't have to think about iPad
            portrait vs. iPhone Pro Max vs. ultrawide.
          </p>
        </header>

        {/* ─── Why upload here ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">What you get</div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            <Pillar
              n="01"
              t="Forty-plus variants"
              p="iPhone 16 Pro to iMac 27″ Retina to Galaxy S25 Ultra to iPad Air. Generated automatically when you upload. You see them on your profile, the rest of the site picks the right one for each visitor."
            />
            <Pillar
              n="02"
              t="A coin per upload"
              p="Every accepted upload pays out one coin. Coins aren't money yet — they're a bookkeeping signal — but the ledger is real and persistent. Future revenue share will run on the same rails."
            />
            <Pillar
              n="03"
              t="Editorial surface"
              p="The Mac menu-bar app, featured collections, and the homepage Latest rail all pull from the same pool. Strong work surfaces; algorithm spam doesn't."
            />
          </div>
        </section>

        {/* ─── How to start ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">How to start</div>
          <ol className="space-y-5 text-[14.5px] leading-[1.6] text-ink-2 list-none p-0 m-0">
            <Step
              n="01"
              t="Sign up"
              p="Free, no credit card. You start with a small coin balance so you can browse before you upload."
            />
            <Step
              n="02"
              t="Drag and drop"
              p="JPEG, PNG, or HEIC. 4K (3840 × 2160) and up is preferred — smaller files still work but fit fewer device profiles. macOS dynamic wallpapers (.heic with embedded solar / h24 / appearance metadata) are supported and surfaced separately."
            />
            <Step
              n="03"
              t="Variants process in the background"
              p="The image worker decodes your file, generates each device variant, extracts a dominant color, and publishes the wallpaper. Usually under a minute. Your profile updates the moment it's live."
            />
          </ol>
        </section>

        {/* ─── Quality bar ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">A short, honest quality bar</div>
          <ul className="space-y-2 text-[14px] leading-[1.6] text-ink-2 list-none p-0 m-0">
            <li className="flex gap-3">
              <span className="mono text-[11px] tracking-[0.06em] text-muted shrink-0 mt-[2px]">→</span>
              <span><strong className="text-ink">Original work only.</strong> Don't upload anything you don't hold rights to. We honor DMCA take-downs.</span>
            </li>
            <li className="flex gap-3">
              <span className="mono text-[11px] tracking-[0.06em] text-muted shrink-0 mt-[2px]">→</span>
              <span><strong className="text-ink">High resolution.</strong> 4K (3840 × 2160) or above is the sweet spot — under 1920 wide and the file fits fewer of our device profiles.</span>
            </li>
            <li className="flex gap-3">
              <span className="mono text-[11px] tracking-[0.06em] text-muted shrink-0 mt-[2px]">→</span>
              <span><strong className="text-ink">No watermarks across the image.</strong> Signature in the corner is fine; a logo across the whole canvas is not.</span>
            </li>
            <li className="flex gap-3">
              <span className="mono text-[11px] tracking-[0.06em] text-muted shrink-0 mt-[2px]">→</span>
              <span><strong className="text-ink">Honest metadata.</strong> Title, description, and category should describe the image — keyword-stuffing gets the upload pulled.</span>
            </li>
          </ul>
        </section>

        {/* ─── CTA ─── */}
        <section className="pt-2 border-t border-hair pt-7 flex flex-wrap gap-3 items-center">
          <Link
            to={startPath}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-accent text-white text-[13px] font-semibold no-underline hover:brightness-95 transition-all"
          >
            {isAuthenticated ? 'Upload your first wallpaper' : 'Sign up and start uploading'}
          </Link>
          <Link
            to="/terms"
            className="text-[12px] text-muted no-underline hover:text-ink-2"
          >
            Read the terms first →
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
