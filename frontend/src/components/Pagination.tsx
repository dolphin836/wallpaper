import { useTranslation } from 'react-i18next';

interface Props {
  current: number;
  total: number;
  onChange: (page: number) => void;
  /** Highest page number the user can jump to. Used with cursor-
   *  based backends where only pages the user has already paged
   *  through have a cached cursor — pages > maxReachable show
   *  but stay disabled. Defaults to total (all clickable). */
  maxReachable?: number;
}

/**
 * Editorial pager: paper pill Prev/Next on either side, mono 32×32 circles
 * for page numbers, with an uppercase "PAGE X OF Y" status line below.
 *
 * Cursor-aware: any page > maxReachable is rendered but disabled, so the
 * user can still see how many pages exist and step forward via Next /
 * the next visible number, but can't randomly jump to the last page (the
 * backend can't honour those jumps without an offset API).
 *
 * Ellipsis logic for `total > 7`:
 *   - always show first page
 *   - … when current > 3
 *   - current ± 1
 *   - … when current < total - 2
 *   - always show last page
 */
export default function Pagination({ current, total, onChange, maxReachable }: Props) {
  const { t } = useTranslation();
  if (total <= 1) return null;
  const reachable = maxReachable ?? total;

  const pages: (number | 'ellipsis')[] = [];
  if (total <= 7) {
    for (let i = 1; i <= total; i++) pages.push(i);
  } else {
    pages.push(1);
    if (current > 3) pages.push('ellipsis');
    const start = Math.max(2, current - 1);
    const end = Math.min(total - 1, current + 1);
    for (let i = start; i <= end; i++) pages.push(i);
    if (current < total - 2) pages.push('ellipsis');
    pages.push(total);
  }

  return (
    <>
      <div className="pager">
        <button
          className="pager-nav"
          disabled={current === 1}
          onClick={() => onChange(current - 1)}
        >
          {t('pager.prev')}
        </button>
        <div className="pager-pages">
          {pages.map((p, i) =>
            p === 'ellipsis' ? (
              <span key={`e${i}`} className="pager-ellipsis">…</span>
            ) : (
              <button
                key={p}
                className={p === current ? 'is-current' : ''}
                onClick={() => p !== current && p <= reachable && onChange(p)}
                disabled={p === current || p > reachable}
                title={p > reachable ? t('pager.walkForward', { page: p }) : undefined}
              >
                {p}
              </button>
            )
          )}
        </div>
        <button
          className="pager-nav"
          disabled={current >= total || current >= reachable}
          onClick={() => onChange(current + 1)}
        >
          {t('pager.next')}
        </button>
      </div>
      <div className="pager-status">{t('pager.status', { current, total })}</div>
    </>
  );
}
