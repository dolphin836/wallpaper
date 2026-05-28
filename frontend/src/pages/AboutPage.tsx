import { Link } from 'react-router-dom';
import PageMeta from '../components/PageMeta';

// Editorial /about page. Intentionally short — the goal isn't to recite
// marketing copy, it's to give a new visitor (or a Google reviewer) one
// scrollable page that answers "what is this and who runs it." Anything
// dynamic (counts, leaderboards) lives elsewhere.
export default function AboutPage() {
  return (
    <div className="legal-page min-h-full">
      <div className="legal-mesh" aria-hidden />
      <PageMeta
        title="About"
        description="Wallpaper Exchange — a wallpaper community where every image comes pre-sized for forty-plus devices, and every contributor earns a coin for every upload."
      />

      <div className="relative z-10 px-6 sm:px-10 lg:px-14 py-12 max-w-[1280px] mx-auto">

        {/* ─── Hero ─── */}
        <header className="mb-10">
          <div className="kicker text-muted">About · Independent since 2026</div>
          <h1 className="display text-[40px] sm:text-[56px] leading-[1.02] mt-2 tracking-[-0.015em] text-ink">
            The archive built for <em className="legal-title-tail">the screens you actually use.</em>
          </h1>
          <p className="text-[16px] leading-[1.55] text-ink-2 mt-5 max-w-[640px]">
            Wallpaper Exchange is a small editorial wallpaper community.
            Every upload is automatically resized for forty-plus device
            profiles — from a 27-inch iMac to a folding Android — and
            every contributor earns a coin for every wallpaper they put
            in.
          </p>
        </header>

        {/* ─── Why this exists ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">Why this exists</div>
          <div className="space-y-4 text-[14.5px] leading-[1.65] text-ink-2">
            <p>
              Most "free wallpaper" sites serve a 1920×1080 JPEG to a
              Retina display and call it a day. The image either looks
              soft, gets cropped wrong, or has dead pixels around the
              menu bar. We wanted something where the file you download
              fits your specific device, not the average device.
            </p>
            <p>
              And most "community" wallpaper sites are SEO-bait
              disguised as a community — there's no real reason for a
              creator to upload, and no real reason for a downloader to
              come back. The coin economy is a small experiment in
              fixing that: contributors earn, downloaders spend, and
              the two sides keep each other honest.
            </p>
          </div>
        </section>

        {/* ─── How it actually works ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">How it works</div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-5">
            <Pillar
              n="01"
              t="Forty-plus variants"
              p="Upload once. We generate a variant for every device profile in our library — iPhone 16 Pro to iMac 27″ Retina to Galaxy S25 Ultra. The download endpoint serves whichever one fits your current screen."
            />
            <Pillar
              n="02"
              t="A coin per upload"
              p="Every accepted upload earns its author one coin. Downloading a wallpaper spends one. Coins are not money — yet — but they're a real bookkeeping signal of who's contributing and who's consuming."
            />
            <Pillar
              n="03"
              t="Editorial curation"
              p="Featured collections instead of an algorithmic feed. The Mac menu-bar app surfaces a hand-picked rotation; the web archive groups work by curator, not by recency."
            />
          </div>
        </section>

        {/* ─── Made by ─── */}
        <section className="mb-10">
          <div className="label-rule mb-3">Made by</div>
          <p className="text-[14.5px] leading-[1.65] text-ink-2">
            One person. Built quietly in the open. Bug reports and
            contributors welcome — drop a line at{' '}
            <a className="text-ink underline" href="mailto:hello@wallpaperexchange.com">
              hello@wallpaperexchange.com
            </a>
            .
          </p>
        </section>

        {/* ─── CTA ─── */}
        <section className="pt-2 flex flex-wrap gap-3">
          <Link
            to="/"
            className="inline-flex items-center px-5 py-2.5 rounded-full bg-ink text-paper text-[13px] font-medium no-underline hover:bg-ink-2 transition-colors"
          >
            Browse the archive
          </Link>
          <Link
            to="/contribute"
            className="inline-flex items-center px-5 py-2.5 rounded-full bg-paper text-ink border border-hair text-[13px] font-medium no-underline hover:bg-paper-2 hover:border-ink-2 transition-colors"
          >
            Become a contributor
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
