import { useState, useEffect, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { MdEmojiEvents } from 'react-icons/md';
import type { UserListItem } from '../types';
import { getUsers } from '../api';
import PageMeta from '../components/PageMeta';
import Pagination from '../components/Pagination';
import Avatar from '../components/Avatar';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';

type Sort = 'recent' | 'uploads' | 'coins';
const PAGE_SIZE = 12;

// Visible labels live in the `browse` namespace; the Sort values
// themselves are API params and stay untranslated.
const SORT_LABEL_KEYS: Record<Sort, string> = {
  recent: 'uploaders.sortRecent',
  uploads: 'uploaders.sortUploads',
  coins: 'uploaders.sortCoins',
};

function formatNumber(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
  if (n >= 1000) return (n / 1000).toFixed(n >= 10_000 ? 0 : 1) + 'K';
  return n.toLocaleString();
}

// formatJoined removed — the new card design drops the explicit
// "joined …" line. Bring back if a future variant needs it.

export default function UploadersPage() {
  const { t } = useTranslation('browse');
  const [items, setItems] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  // The "Top this month" / "Most uploaded" / "Recently joined" chips map to
  // the existing sort options. "Following" is in the design but the product
  // has no follow feature yet, so we skip that chip.
  const [sort, setSort] = useState<Sort>('uploads');

  const fetchUsers = useCallback(async (p: number, s: Sort) => {
    setLoading(true);
    try {
      const apiSort = s === 'recent' ? '' : s;
      const res = await getUsers({ page: p, limit: PAGE_SIZE, sort: apiSort });
      setItems(res.data.data.items ?? []);
      setTotal(res.data.data.total);
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchUsers(page, sort); }, [page, sort, fetchUsers]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="uploaders-page min-h-full">
      <div className="uploaders-mesh" aria-hidden />
      <PageMeta
        title={t('uploaders.metaTitle')}
        description={t('uploaders.metaDescription')}
      />

      <div className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-12">
        {/* Header */}
        <div className="flex items-end justify-between gap-6 flex-wrap mb-8">
          <div>
            <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              {t('uploaders.contributorsKicker', { num: total })}
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            {(['coins', 'uploads', 'recent'] as Sort[]).map((key) => (
              <button
                key={key}
                onClick={() => { setSort(key); setPage(1); }}
                className={`px-3.5 py-1.5 rounded-full text-[12px] font-medium transition-colors ${
                  sort === key
                    ? 'bg-ink text-paper border border-ink'
                    : 'bg-paper text-ink-2 border border-hair hover:bg-paper-2 hover:border-ink-2'
                }`}
              >
                {t(SORT_LABEL_KEYS[key])}
              </button>
            ))}
          </div>
        </div>

        {/* CTA banner — directly invites the visitor to upload, so
            the page isn't just a passive directory. Always visible
            (signed-out → /register inside /upload's auth gate;
            signed-in → straight to /upload). */}
        <Link to="/upload" className="uploaders-cta">
          <div className="uploaders-cta-text">
            <span className="uploaders-cta-eyebrow">{t('uploaders.ctaEyebrow')}</span>
            <span className="uploaders-cta-headline">{t('uploaders.ctaHeadline')}</span>
          </div>
          <span className="uploaders-cta-arrow">{t('uploaders.ctaArrow')}</span>
        </Link>

        {/* Identity-first card grid — the user is the subject,
            their wallpapers are secondary. Each card shows avatar,
            nickname, optional bio, and a three-stat block (uploads
            / downloads / coins). When the user has uploads, a
            small 3-thumb strip + 'and N more' shows below the
            stats; when not, the thumb strip is omitted entirely so
            the card stays clean. Top 3 contributors on the first
            page get an accent ring + 'TOP' badge. */}
        {loading && items.length === 0 ? (
          <UploaderWallSkeleton count={9} />
        ) : error && items.length === 0 ? (
          <ErrorState />
        ) : items.length === 0 ? (
          <EmptyState
            title={t('uploaders.emptyTitle')}
            message={t('uploaders.emptyMessage')}
            actionLabel={t('uploaders.emptyAction')}
            actionHref="/contribute"
          />
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
            {items.map((u, i) => (
              <UploaderWallCard
                key={u.id}
                u={u}
                rank={page === 1 ? i + 1 : 999}
              />
            ))}
          </div>
        )}

        <Pagination current={page} total={totalPages} onChange={setPage} />
      </div>
    </div>
  );
}

// Tints — three CSS-var colour stops powering the per-card aura.
// Preference order: (1) the user's recent wallpapers' dominant
// colours from the API, (2) a deterministic hash of the username
// when they haven't uploaded anything yet, so every card still
// has its own colour signal.
function hashHue(s: string, seed = 0): number {
  let h = seed;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) - h) + s.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h);
}
function resolveTints(u: UserListItem): [string, string, string] {
  const t = u.recent_tints ?? [];
  if (t.length >= 3) return [t[0], t[1], t[2]];
  if (t.length === 2) return [t[0], t[1], t[0]];
  if (t.length === 1) return [t[0], t[0], t[0]];
  // No uploads — derive a stable triad from the username so every
  // user still gets a unique-feeling card.
  const name = u.username || String(u.id);
  const base = hashHue(name) % 360;
  const h2 = (base + 60 + hashHue(name, 17) % 80) % 360;
  const h3 = (base + 180 + hashHue(name, 31) % 60) % 360;
  return [
    `oklch(80% 0.10 ${base})`,
    `oklch(78% 0.12 ${h2})`,
    `oklch(82% 0.08 ${h3})`,
  ];
}

// Uploader card — identity-first.
// Hero: avatar (with accent ring for top-3 contributors on the
// page) + nickname + @handle + optional bio. Middle: a 3-cell stat
// grid (Uploads / Downloads / Coins). Bottom: a small 3-thumb
// strip from the user's recent uploads — collapsed entirely when
// the user hasn't uploaded anything, so the card stays clean for
// non-contributors instead of awkward placeholders. Click → user
// profile.
function UploaderWallCard({ u, rank }: { u: UserListItem; rank: number }) {
  const { t } = useTranslation('browse');
  const display = u.nickname || u.username;
  const thumbs = (u.recent_thumbs ?? []).slice(0, 3);
  const isTop = rank <= 3 && u.wallpaper_count > 0;
  const [c1, c2, c3] = resolveTints(u);
  // Per-card animation delay so neighbours don't drift in lockstep
  // — staggered up to ~9s via the user id modulo.
  const auraStyle = {
    ['--u-c1' as string]: c1,
    ['--u-c2' as string]: c2,
    ['--u-c3' as string]: c3,
    ['--u-aura-delay' as string]: `${(u.id % 9) * 1.1}s`,
  } as React.CSSProperties;
  return (
    <Link
      to={`/user/${u.username}`}
      className={`uploader-card no-underline${isTop ? ' is-top' : ''}`}
      style={auraStyle}
    >
      <div className="uploader-card-aura" aria-hidden />
      {isTop && (
        <span
          className={`uploader-card-badge is-rank-${rank}`}
          title={t('uploaders.topContributor', { rank })}
        >
          <MdEmojiEvents size={12} />
          <span>{t('uploaders.topBadge', { rank })}</span>
        </span>
      )}

      <div className="uploader-card-head">
        {/* Three-segment conic ring around the avatar — the user's
            recent dominant colours rotated 120° each. Pure-CSS,
            same colour stops as the aura behind the card. */}
        <span className="uploader-card-ring" aria-hidden>
          <Avatar
            src={u.avatar_url}
            name={display}
            size={60}
            className="uploader-card-avatar"
          />
        </span>
        <div className="uploader-card-id">
          <div className="uploader-card-name">{display}</div>
          <div className="uploader-card-handle">@{u.username}</div>
        </div>
      </div>

      {u.bio
        ? <p className="uploader-card-bio">{u.bio}</p>
        : <div className="uploader-card-bio-empty" aria-hidden />}

      <div className="uploader-card-stats">
        <Stat label={t('uploaders.statUploads')}   value={formatNumber(u.wallpaper_count)} />
        <Stat label={t('uploaders.statDownloads')} value={formatNumber(u.total_downloads ?? 0)} />
        <Stat label={t('uploaders.statCoins')}     value={formatNumber(u.coins ?? 0)} />
      </div>

      {thumbs.length > 0 && (
        <div className="uploader-card-thumbs">
          {thumbs.map((src, i) => (
            <div key={i} className="uploader-card-thumb">
              <img src={src} alt="" loading="lazy" />
            </div>
          ))}
          {u.wallpaper_count > thumbs.length && (
            <div className="uploader-card-thumb-more">
              +{u.wallpaper_count - thumbs.length}
            </div>
          )}
        </div>
      )}

      <div className="uploader-card-cta">{t('uploaders.viewProfile')}</div>
    </Link>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="uploader-stat">
      <div className="uploader-stat-num">{value}</div>
      <div className="uploader-stat-label">{label}</div>
    </div>
  );
}

// Skeleton — same overall card shape with paper-2 placeholders.
function UploaderWallSkeleton({ count }: { count: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-5">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="uploader-card is-skel">
          <div className="uploader-card-head">
            <span className="uploader-card-ring is-skel" aria-hidden>
              <span className="uploader-card-skel-avatar" />
            </span>
            <div className="uploader-card-id">
              <div className="uploader-card-skel-bar" style={{ width: '50%', height: 14 }} />
              <div className="uploader-card-skel-bar mt-2" style={{ width: '35%', height: 9 }} />
            </div>
          </div>
          <div className="uploader-card-bio-empty" />
          <div className="uploader-card-stats">
            {Array.from({ length: 3 }).map((__, j) => (
              <div key={j} className="uploader-stat">
                <div className="uploader-card-skel-bar mx-auto" style={{ width: 36, height: 16 }} />
                <div className="uploader-card-skel-bar mx-auto mt-2" style={{ width: 48, height: 8 }} />
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}
