import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { getWeeklyCurrent, type WeeklyCurrent } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import WallpaperTile from '../components/WallpaperTile';
import useSkeletonRows from '../hooks/useSkeletonRows';
import useProtectedImageBlob from '../hooks/useProtectedImageBlob';
import type { Wallpaper } from '../types';
import { createWallpaperDetailNavigation } from '../lib/wallpaperDetailNavigation';

/**
 * Home v4 — immersive weekly backdrop, mirroring the Mac client
 * (docs/design-system.md):
 *   • The weekly hero pick IS the page background — fixed full-bleed,
 *     loaded progressively (dominant color → thumb → preview → original) under
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
  const { containerRef: weeklyGridRef, count: weeklySkeletonCount } = useSkeletonRows(2);

  useEffect(() => {
    getWeeklyCurrent()
      .then((r) => { setData(r.data.data); setWeeklyError(false); })
      .catch(() => setWeeklyError(true))
      .finally(() => setLoading(false));
  }, []);

  const picks = useMemo(() => data?.picks || [], [data?.picks]);
  const hero = picks.find((p) => p.is_hero) || picks[0] || null;
  const detailNavigation = useMemo(
    () => createWallpaperDetailNavigation(picks),
    [picks],
  );

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

            <div ref={weeklyGridRef} className="h4-weekly-grid mt-7">
              {loading && picks.length === 0
                ? Array.from({ length: weeklySkeletonCount }).map((_, i) => (
                    <div key={`hsk-${i}`} className="h3-tile h3-home skeleton-card" style={{ aspectRatio: '1.618' }} />
                  ))
                : picks.map((w) => (
                    <WallpaperTile
                      key={w.id}
                      w={w}
                      variant="home"
                      detailNavigation={detailNavigation}
                    />
                  ))}
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

/* ─── Fixed full-bleed backdrop:
       dominant color → thumb (blurred) → preview → original. ─── */
function HomeBackdrop({ hero }: { hero: Partial<Wallpaper> | null }) {
  const [loadedThumb, setLoadedThumb] = useState('');
  const [loadedPreview, setLoadedPreview] = useState('');
  const [failedPreview, setFailedPreview] = useState('');
  const [loadedOriginal, setLoadedOriginal] = useState('');
  const thumb = hero?.thumb_url || hero?.preview_url || '';
  const preview = hero?.preview_url && hero.preview_url !== thumb
    ? hero.preview_url
    : '';
  const protectedOriginal = hero?.original_url
    && !hero.file_type?.startsWith('video/')
    && !hero.is_dynamic
      ? hero.original_url
      : '';
  const { blobURL: originalBlobURL } = useProtectedImageBlob(protectedOriginal, {
    timeoutMs: 20_000,
    retries: 1,
  });
  const thumbReady = !!thumb && loadedThumb === thumb;
  const previewReady = !!preview && loadedPreview === preview;
  const previewFailed = !!preview && failedPreview === preview;
  const originalReady = !!originalBlobURL && loadedOriginal === originalBlobURL;
  const thumbIsFinal = !preview || previewFailed;

  return (
    <div className="h4-backdrop" aria-hidden style={{ backgroundColor: hero?.dominant_color || undefined }}>
      {thumb && (
        <img
          src={thumb}
          alt=""
          decoding="async"
          fetchPriority="high"
          className={`h4-backdrop-image h4-backdrop-thumb${thumbReady ? ' is-visible' : ''}${thumbIsFinal ? ' is-final' : ''}`}
          onLoad={() => setLoadedThumb(thumb)}
        />
      )}
      {preview && (
        <img
          src={preview}
          alt=""
          decoding="async"
          fetchPriority="high"
          className={`h4-backdrop-image h4-backdrop-preview${previewReady ? ' is-visible' : ''}`}
          onLoad={() => setLoadedPreview(preview)}
          onError={() => setFailedPreview(preview)}
        />
      )}
      {originalBlobURL && (
        <img
          src={originalBlobURL}
          alt=""
          decoding="async"
          className={`h4-backdrop-image h4-backdrop-original${originalReady ? ' is-visible' : ''}`}
          onLoad={() => setLoadedOriginal(originalBlobURL)}
        />
      )}
      <div className="h4-backdrop-scrim" />
    </div>
  );
}
