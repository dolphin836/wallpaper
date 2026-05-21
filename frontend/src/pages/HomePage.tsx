import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getWeeklyCurrent, getWallpapers, type WeeklyCurrent } from '../api';
import type { Wallpaper } from '../types';
import PageMeta from '../components/PageMeta';
import WallpaperCard from '../components/WallpaperCard';
import CollectionCard from '../components/CollectionCard';

// Home is the rotation surface: hero picks slate at the top, themed
// collections below, and a discreet pair of links out to the full
// gallery + past weeks at the bottom. It's the page a returning
// visitor opens hoping for *something new this week*, so it stays
// deliberately small — the deep gallery lives on /discover.
export default function HomePage() {
  const [data, setData] = useState<WeeklyCurrent | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState(false);

  // AI-generated row. Independent fetch — failure here shouldn't break
  // the weekly drop above it. Empty array (e.g. nothing flagged yet) hides
  // the section entirely so we don't surface a sad placeholder row.
  const [aiItems, setAiItems] = useState<Wallpaper[]>([]);
  const [aiLoading, setAiLoading] = useState(true);

  useEffect(() => {
    getWeeklyCurrent()
      .then((r) => setData(r.data.data))
      .catch(() => setErr(true))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    getWallpapers({ ai_only: true, limit: 10, sort: 'newest' })
      .then((r) => setAiItems(r.data.data.items))
      .catch(() => setAiItems([]))
      .finally(() => setAiLoading(false));
  }, []);

  const hasPicks = !!data && data.picks && data.picks.length > 0;
  const hasThemes = !!data && data.themes && data.themes.length > 0;
  const hasAI = aiItems.length > 0;

  return (
    <div className="bg-paper-2 min-h-full">
      <PageMeta
        title="Home"
        description="The weekly drop on Wallpaper Exchange — 10 hand-picked wallpapers plus a themed editor collection, refreshed every Friday."
      />

      <main className="px-6 sm:px-10 lg:px-16 py-10 max-w-[1600px] mx-auto">
        {/* ── Hero strip ──────────────────────────────────────────── */}
        <section className="mb-12">
          <div className="flex items-baseline justify-between mb-5">
            <div>
              <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">
                {data && data.year > 0 ? `Week ${data.week} · ${data.year}` : 'This Week'}
              </div>
              <h1 className="display text-[34px] sm:text-[40px] leading-tight mt-1">
                The Weekly Drop
              </h1>
            </div>
            <Link to="/weekly-picks" className="mono text-[11px] tracking-[0.14em] uppercase text-ink-2 hover:text-ink no-underline">
              See past weeks →
            </Link>
          </div>

          {loading ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
              {Array.from({ length: 10 }).map((_, i) => (
                <div key={i} className="aspect-[4/3] border border-hair rounded bg-paper-3 skeleton-card" />
              ))}
            </div>
          ) : err ? (
            <div className="text-rose-500 text-sm">Couldn't load this week's picks. Try refreshing.</div>
          ) : !hasPicks ? (
            <div className="rounded-lg border border-hair bg-paper p-8 text-center text-ink-2">
              <div className="display text-[20px] mb-2">No picks yet.</div>
              <div className="text-sm">Check back after this Friday's drop, or browse the full gallery.</div>
              <Link to="/discover" className="inline-block mt-4 mono text-[11px] tracking-[0.14em] uppercase text-accent hover:underline no-underline">
                Browse the gallery →
              </Link>
            </div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
              {data!.picks.map((w, i) => (
                <div key={w.id} className="aspect-[4/3] relative">
                  <WallpaperCard wallpaper={w} fixedAspect hideActions animDelay={i * 30} />
                </div>
              ))}
            </div>
          )}
        </section>

        {/* ── AI-generated row ───────────────────────────────────── */}
        {(aiLoading || hasAI) && (
          <section className="mb-12">
            <div className="flex items-baseline justify-between mb-5">
              <div>
                <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">AI Lab</div>
                <h2 className="display text-[28px] sm:text-[32px] leading-tight mt-1">
                  Generated this week
                </h2>
              </div>
              <Link to="/discover?filter=ai" className="mono text-[11px] tracking-[0.14em] uppercase text-ink-2 hover:text-ink no-underline">
                All AI wallpapers →
              </Link>
            </div>
            {aiLoading ? (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                {Array.from({ length: 5 }).map((_, i) => (
                  <div key={i} className="aspect-[4/3] border border-hair rounded bg-paper-3 skeleton-card" />
                ))}
              </div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
                {aiItems.map((w, i) => (
                  <div key={w.id} className="aspect-[4/3] relative">
                    <WallpaperCard wallpaper={w} fixedAspect hideActions animDelay={i * 30} />
                  </div>
                ))}
              </div>
            )}
          </section>
        )}

        {/* ── Themed collections ─────────────────────────────────── */}
        {(loading || hasThemes) && (
          <section className="mb-12">
            <div className="flex items-baseline justify-between mb-5">
              <div>
                <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">Editor Themes</div>
                <h2 className="display text-[28px] sm:text-[32px] leading-tight mt-1">
                  Curated collections, one per week
                </h2>
              </div>
              <Link to="/collections?kind=1" className="mono text-[11px] tracking-[0.14em] uppercase text-ink-2 hover:text-ink no-underline">
                All themes →
              </Link>
            </div>
            {loading ? (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                {Array.from({ length: 3 }).map((_, i) => (
                  <div key={i} className="flex flex-col gap-3">
                    <div className="aspect-[4/3] border border-hair rounded-lg bg-paper-3 skeleton-card" />
                    <div className="h-4 w-[70%] rounded-sm bg-paper-3 skeleton-card" />
                    <div className="h-3 w-[40%] rounded-sm bg-paper-3 skeleton-card" />
                  </div>
                ))}
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
                {data!.themes.map((c) => <CollectionCard key={c.id} collection={c} />)}
              </div>
            )}
          </section>
        )}

        {/* ── Browse-everything escape hatch ─────────────────────── */}
        <section className="border-t border-hair pt-8 mt-12">
          <div className="flex flex-wrap items-baseline gap-x-8 gap-y-3 text-sm">
            <Link to="/discover" className="display text-[20px] text-ink hover:underline no-underline">
              Browse all wallpapers →
            </Link>
            <Link to="/wallpapers-for" className="text-ink-2 hover:text-ink no-underline">By device</Link>
            <Link to="/collections" className="text-ink-2 hover:text-ink no-underline">All collections</Link>
            <Link to="/uploaders" className="text-ink-2 hover:text-ink no-underline">Uploaders</Link>
          </div>
        </section>
      </main>
    </div>
  );
}
