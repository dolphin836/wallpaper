import { useEffect, useState } from 'react';
import { AiOutlineApple, AiOutlineDownload, AiOutlineCheckCircle } from 'react-icons/ai';
import { getMacRelease } from '../api';
import type { MacRelease } from '../types';
import usePageTitle from '../hooks/usePageTitle';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

function formatDate(iso: string): string {
  try {
    return new Date(iso).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' });
  } catch {
    return iso;
  }
}

export default function DownloadMacPage() {
  usePageTitle('Download for macOS');
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

  return (
    <div className="max-w-3xl mx-auto px-6 py-10">
      {/* Hero */}
      <div className="text-center mb-10">
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-2xl bg-gradient-to-br from-slate-900 to-slate-700 dark:from-white/10 dark:to-white/5 mb-5 shadow-lg">
          <AiOutlineApple className="text-white" size={48} />
        </div>
        <h1 className="text-3xl font-bold text-slate-900 dark:text-white mb-2">
          Wallpaper Exchange for macOS
        </h1>
        <p className="text-sm text-ws-muted dark:text-ws-dark-muted">
          Menubar app — browse the latest, download, set as wallpaper, all without leaving the menu bar.
        </p>
      </div>

      {/* Download card */}
      <div className="bg-white dark:bg-ws-dark-card rounded-2xl border border-ws-border dark:border-white/10 shadow-sm p-6 mb-8">
        <div className="flex items-center justify-between flex-wrap gap-4">
          <div>
            <div className="flex items-baseline gap-3">
              <span className="text-2xl font-bold text-slate-900 dark:text-white">
                v{release.current_version}
              </span>
              <span className="text-xs text-ws-muted dark:text-ws-dark-muted">
                Requires macOS {release.min_macos_version}+
              </span>
            </div>
            {release.releases[0] && (
              <p className="text-sm text-ws-muted dark:text-ws-dark-muted mt-1">
                Released {formatDate(release.releases[0].released_at)}
              </p>
            )}
          </div>
          <a
            href={release.current_dmg_url}
            className="flex items-center gap-2 px-6 py-3 text-sm font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-xl transition-colors shadow-sm"
          >
            <AiOutlineDownload size={18} />
            Download .dmg
          </a>
        </div>
      </div>

      {/* Install hint */}
      <div className="bg-amber-50 dark:bg-amber-900/10 border border-amber-200/60 dark:border-amber-700/30 rounded-xl px-5 py-4 mb-10 text-sm text-amber-800 dark:text-amber-300">
        <div className="font-semibold mb-1">First-time install</div>
        <p className="leading-relaxed">
          The download is not yet notarized through Apple. On first launch, macOS will say
          the developer can't be verified — right-click <span className="font-semibold">Wallpaper Exchange.app</span>{' '}
          and choose <span className="font-semibold">Open</span> instead of double-clicking. Future launches are normal.
        </p>
      </div>

      {/* Changelog */}
      <h2 className="text-lg font-semibold text-slate-800 dark:text-white mb-4">Release notes</h2>
      <div className="space-y-6">
        {release.releases.map((r) => (
          <div
            key={r.version}
            className="bg-white dark:bg-ws-dark-card rounded-xl border border-ws-border dark:border-white/10 p-5"
          >
            <div className="flex items-baseline gap-3 mb-3">
              <span className="text-base font-bold text-slate-900 dark:text-white">
                v{r.version}
              </span>
              <span className="text-xs text-ws-muted dark:text-ws-dark-muted">
                {formatDate(r.released_at)}
              </span>
              {r.version === release.current_version && (
                <span className="text-[10px] font-semibold uppercase tracking-wider px-2 py-0.5 rounded-full bg-ws-purple/10 text-ws-purple">
                  Latest
                </span>
              )}
            </div>
            <ul className="space-y-1.5">
              {r.notes.map((n, i) => (
                <li key={i} className="flex items-start gap-2 text-sm text-slate-700 dark:text-slate-300">
                  <AiOutlineCheckCircle className="text-ws-purple mt-0.5 flex-shrink-0" size={14} />
                  <span>{n}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </div>
  );
}
