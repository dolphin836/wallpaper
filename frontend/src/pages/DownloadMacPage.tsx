import { useEffect, useState } from 'react';
import {
  AiOutlineApple,
  AiOutlineMenu,
  AiOutlineThunderbolt,
} from 'react-icons/ai';
import { BiCollection } from 'react-icons/bi';
import { Link } from 'react-router-dom';
import { getMacRelease } from '../api';
import type { MacRelease, MacReleaseEntry } from '../types';
import PageMeta from '../components/PageMeta';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
  } catch {
    return iso;
  }
}

export default function DownloadMacPage() {
  const [release, setRelease] = useState<MacRelease | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  useEffect(() => {
    getMacRelease()
      .then((res) => setRelease(res.data.data))
      .catch(() => setError(true))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <Spinner />;
  if (error || !release) return <EmptyState message="Release info unavailable. Try again later." />;

  const latest: MacReleaseEntry | undefined = release.releases[0];

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title="Wallpaper Exchange for macOS"
        description="Free menu-bar companion app for macOS — browse, preview, and apply wallpapers in one click. Apple dynamic wallpaper support."
      />

      {/* Hero — 2 columns */}
      <section className="grid grid-cols-1 lg:grid-cols-2 gap-10 lg:gap-14 px-6 sm:px-10 lg:px-14 pt-10 lg:pt-12 pb-10 border-b border-hair">
        <div>
          <div className="kicker text-muted inline-flex items-center gap-2">
            <AiOutlineApple size={11} />
            FOR MACOS {release.min_macos_version}+ · UNIVERSAL · v{release.current_version}
          </div>
          <h1 className="display text-[44px] sm:text-[64px] lg:text-[80px] leading-[0.92] tracking-[-0.03em] mt-4 text-ink">
            The archive,<br />
            <span className="italic-d">in your menu bar.</span>
          </h1>
          <p className="text-[14px] sm:text-[15px] text-ink-2 leading-[1.55] mt-5 max-w-[520px]">
            A small companion app that lives in the macOS menu bar. Browse, preview, and apply
            wallpapers in one click — including <strong className="text-ink">Apple dynamic</strong> wallpapers
            that shift with the sun.
          </p>

          <div className="flex items-center gap-4 flex-wrap mt-7">
            <a
              href={release.current_dmg_url}
              className="inline-flex items-center gap-3 px-6 py-4 rounded-full bg-ink text-paper text-[15px] font-semibold no-underline hover:bg-ink-2 transition-colors"
            >
              <AiOutlineApple size={16} /> Download for macOS
              <span
                className="pl-3 ml-1 mono text-[11px] font-medium tracking-[0.1em]"
                style={{ borderLeft: '1px solid rgba(255,255,255,0.2)', color: 'rgba(255,255,255,0.6)' }}
              >
                DMG
              </span>
            </a>
            <div className="mono text-[11px] tracking-[0.06em] text-muted">
              Free · auto-updates · signed and notarized
            </div>
          </div>

          {/* System requirements table */}
          <div
            className="mt-9 grid grid-cols-1 sm:grid-cols-3"
            style={{ border: '1px solid var(--color-hair)', borderRight: 'none' }}
          >
            {[
              ['MACOS', `${release.min_macos_version} or later`],
              ['ARCHITECTURE', 'Apple Silicon · Intel'],
              ['SIGN-IN', 'Same archive account'],
            ].map(([k, v]) => (
              <div key={k} className="px-4 py-3.5" style={{ borderRight: '1px solid var(--color-hair)' }}>
                <div className="kicker text-muted">{k}</div>
                <div className="text-[12px] text-ink mt-1">{v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* Stylized device mockup (static) */}
        <DeviceMockup />
      </section>

      {/* Features — 4 columns */}
      <section className="px-6 sm:px-10 lg:px-14 py-9 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6 lg:gap-0 border-b border-hair">
        {([
          { title: 'One-click apply',     body: 'Right-click any wallpaper in the menu-bar grid to set it as your desktop.' },
          { title: 'Apple Dynamic',       body: 'Full support for solar / 24-hour / appearance-linked wallpapers.' },
          { title: 'Live sync',           body: 'Your favorites and likes sync with the web archive. No setup required.' },
          { title: 'Collections offline', body: 'Subscribe a collection — every wallpaper is cached locally.' },
        ] as const).map((f, i) => (
          <div key={f.title} className={`lg:px-6 ${i > 0 ? 'lg:border-l border-hair' : ''}`}>
            <div className="kicker text-muted">{String(i + 1).padStart(2, '0')}</div>
            <div className="display text-[22px] leading-tight mt-1.5">{f.title}</div>
            <p className="text-[13px] text-ink-2 leading-[1.5] mt-2">{f.body}</p>
          </div>
        ))}
      </section>

      {/* Changelog stub */}
      <section className="px-6 sm:px-10 lg:px-14 py-6 bg-paper-2 flex justify-between items-center gap-6 flex-wrap">
        <div>
          <div className="kicker text-muted">
            v{release.current_version}{latest ? ` · ${formatDate(latest.released_at)}` : ''}
          </div>
          {latest && latest.notes.length > 0 && (
            <div className="text-[13px] text-ink-2 mt-1">{latest.notes[0]}</div>
          )}
        </div>
        <a
          href="#changelog"
          className="mono text-[11px] tracking-[0.12em] uppercase text-ink no-underline hover:opacity-80"
          style={{ textDecoration: 'underline', textDecorationColor: 'var(--color-hair)', textUnderlineOffset: 4 }}
        >
          FULL CHANGELOG →
        </a>
      </section>

      {/* Full changelog */}
      {release.releases.length > 0 && (
        <section id="changelog" className="px-6 sm:px-10 lg:px-14 py-10">
          <div className="label-rule mb-5">Changelog · {release.releases.length}</div>
          <ul className="list-none p-0 m-0 space-y-6">
            {release.releases.map((r) => (
              <li key={r.version} className="border-b border-hair pb-5 last:border-b-0">
                <div className="flex items-baseline justify-between gap-4 flex-wrap">
                  <div className="display text-[22px] leading-tight">v{r.version}</div>
                  <div className="mono text-[10px] tracking-[0.12em] uppercase text-muted">
                    {formatDate(r.released_at)}
                  </div>
                </div>
                {r.notes.length > 0 && (
                  <ul className="mt-3 ml-5 list-disc text-[13px] text-ink-2 leading-[1.5] space-y-1">
                    {r.notes.map((n, i) => <li key={i}>{n}</li>)}
                  </ul>
                )}
              </li>
            ))}
          </ul>
          {/* Tiny "back to top" affordance using a real Link wouldn't make
              sense — drop a passive note instead. */}
          <Link to="/" className="hidden" aria-hidden />
        </section>
      )}
    </div>
  );
}

/**
 * Static visual mock of the macOS menu-bar popover. Pure CSS so we don't
 * need to ship a screenshot. Tinted gradient background + a blurred
 * paper-colored popover sitting in the top-right corner.
 */
function DeviceMockup() {
  return (
    <div className="relative aspect-[5/4] rounded-md overflow-hidden bg-paper-3" style={{ border: '1px solid var(--color-hair)' }}>
      <div
        className="absolute inset-0"
        style={{
          background:
            'linear-gradient(135deg, oklch(58% 0.1 270) 0%, oklch(72% 0.08 80) 50%, oklch(48% 0.12 145) 100%)',
        }}
      />
      <div className="absolute inset-0" style={{ background: 'linear-gradient(180deg, rgba(0,0,0,0.05), rgba(0,0,0,0.35))' }} />

      <div
        className="absolute right-6 top-6 sm:right-8 sm:top-8 w-[280px]"
        style={{
          background: 'rgba(245,243,238,0.94)',
          border: '1px solid rgba(0,0,0,0.08)',
          backdropFilter: 'blur(20px) saturate(1.2)',
          WebkitBackdropFilter: 'blur(20px) saturate(1.2)',
          boxShadow: '0 20px 60px rgba(0,0,0,0.25)',
        }}
      >
        <div
          className="flex justify-between items-center px-3.5 py-2.5 mono text-[9px] uppercase text-muted"
          style={{ borderBottom: '1px solid rgba(0,0,0,0.06)', letterSpacing: '0.14em' }}
        >
          <span>WALLPAPER EXCHANGE</span>
          <AiOutlineApple size={11} />
        </div>
        <div className="grid grid-cols-2 gap-1.5 p-2.5">
          {[
            'oklch(64% 0.21 42)',
            'oklch(56% 0.18 270)',
            'oklch(72% 0.12 145)',
            'oklch(48% 0.20 30)',
          ].map((c, i) => (
            <div
              key={i}
              className="aspect-[16/10] rounded-sm"
              style={{
                background: c,
                border: i === 0 ? '2px solid var(--color-accent)' : '1px solid rgba(0,0,0,0.06)',
              }}
            />
          ))}
        </div>
        <div className="px-3.5 py-2.5 text-[11px] flex justify-between" style={{ borderTop: '1px solid rgba(0,0,0,0.06)' }}>
          <span className="text-ink">Latest from the wall</span>
          <span className="text-accent font-semibold">Applied</span>
        </div>
        <button className="w-full py-2.5 bg-ink text-paper text-[12px] font-medium border-0 cursor-pointer">
          Open in archive →
        </button>
      </div>

      {/* Feature trio icons floating below the popover for visual rhythm */}
      <div
        className="absolute left-6 sm:left-8 bottom-6 sm:bottom-8 flex items-center gap-2.5 px-3 py-2 rounded-full"
        style={{ background: 'rgba(255,255,255,0.18)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)' }}
      >
        <AiOutlineMenu size={14} className="text-white/85" />
        <AiOutlineThunderbolt size={14} className="text-white/85" />
        <BiCollection size={14} className="text-white/85" />
      </div>
    </div>
  );
}
