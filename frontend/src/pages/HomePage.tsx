import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { getWeeklyCurrent, type WeeklyCurrent } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import WallpaperTile from '../components/WallpaperTile';

/**
 * Home v4 — immersive weekly backdrop, mirroring the Mac client
 * (docs/design-system.md):
 *   • The weekly hero pick IS the page background — fixed full-bleed,
 *     loaded progressively (dominant color → thumb → original) under
 *     the Mac backdrop's scrim stops.
 *   • One content row: "This week's picks" in white display type over
 *     the photo, then a golden-ratio adaptive grid of the whole slate
 *     (hero included — its tile is the way to open it).
 *   • A "browse more" link at the grid's bottom-trailing corner routes
 *     to Discover.
 */
export default function HomePage() {
  const { t } = useTranslation('browse');
  const [data, setData] = useState<WeeklyCurrent | null>(null);
  const [loading, setLoading] = useState(true);
  const [weeklyError, setWeeklyError] = useState(false);

  useEffect(() => {
    getWeeklyCurrent()
      .then((r) => { setData(r.data.data); setWeeklyError(false); })
      .catch(() => setWeeklyError(true))
      .finally(() => setLoading(false));
  }, []);

  const hero = data?.picks?.find((p) => p.is_hero) || data?.picks?.[0] || null;
  const picks = data?.picks || [];

  return (
    <div className="h4-home">
      <PageMeta
        title={t('home.metaTitle')}
        description={t('home.metaDescription')}
      />

      {/* Full-page wallpaper backdrop (progressive) + legibility scrim. */}
      <HomeBackdrop hero={hero} />

      <main className="h4-home-main relative z-[1] px-6 sm:px-10 py-10">
        {weeklyError && !data ? (
          <div className="pt-[20vh]"><ErrorState /></div>
        ) : (
          <>
            {/* Empty band — the first screenful leads with the backdrop
                wallpaper itself. */}
            <div className="h-[38vh] min-h-[220px]" aria-hidden />

            <h1 className="h4-weekly-title display">{t('home.weeklyTitle')}</h1>

            <div className="h4-weekly-grid mt-7">
              {loading && picks.length === 0
                ? Array.from({ length: 6 }).map((_, i) => (
                    <div key={`hsk-${i}`} className="h3-tile h3-home skeleton-card" style={{ aspectRatio: '1.618' }} />
                  ))
                : picks.map((w) => <WallpaperTile key={w.id} w={w} variant="home" />)}
            </div>

            {picks.length > 0 && (
              <div className="flex justify-end mt-4">
                <Link to="/discover" className="h4-browse-more">{t('home.browseMore')}</Link>
              </div>
            )}
          </>
        )}
      </main>
    </div>
  );
}

/* ─── Fixed full-bleed backdrop, Mac loading order:
       dominant color → thumb (blurred) → original. ─── */
function HomeBackdrop({ hero }: { hero: { thumb_url?: string; preview_url?: string; original_url?: string; dominant_color?: string } | null }) {
  const [src, setSrc] = useState('');
  const [sharp, setSharp] = useState(false);

  useEffect(() => {
    if (!hero) return;
    let alive = true;
    const thumb = hero.thumb_url || hero.preview_url || '';
    const original = hero.original_url || hero.preview_url || thumb;

    setSrc(thumb);
    setSharp(false);

    if (original && original !== thumb) {
      const img = new Image();
      img.onload = () => { if (alive) { setSrc(original); setSharp(true); } };
      img.onerror = () => { if (alive) setSharp(true); };
      img.src = original;
    } else {
      setSharp(true);
    }
    return () => { alive = false; };
  }, [hero]);

  return (
    <div className="h4-backdrop" aria-hidden style={{ backgroundColor: hero?.dominant_color || undefined }}>
      {src && <img src={src} alt="" decoding="async" className={sharp ? 'is-sharp' : ''} />}
      <div className="h4-backdrop-scrim" />
    </div>
  );
}
