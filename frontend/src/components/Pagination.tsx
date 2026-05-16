interface Props {
  current: number;
  total: number;
  onChange: (page: number) => void;
}

/**
 * Editorial pager: paper pill Prev/Next on either side, mono 32×32 circles
 * for page numbers, with an uppercase "PAGE X OF Y" status line below.
 *
 * Ellipsis logic for `total > 7`:
 *   - always show first page
 *   - … when current > 3
 *   - current ± 1
 *   - … when current < total - 2
 *   - always show last page
 */
export default function Pagination({ current, total, onChange }: Props) {
  if (total <= 1) return null;

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
          ← Prev
        </button>
        <div className="pager-pages">
          {pages.map((p, i) =>
            p === 'ellipsis' ? (
              <span key={`e${i}`} className="pager-ellipsis">…</span>
            ) : (
              <button
                key={p}
                className={p === current ? 'is-current' : ''}
                onClick={() => p !== current && onChange(p)}
                disabled={p === current}
              >
                {p}
              </button>
            )
          )}
        </div>
        <button
          className="pager-nav"
          disabled={current === total}
          onClick={() => onChange(current + 1)}
        >
          Next →
        </button>
      </div>
      <div className="pager-status">PAGE {current} OF {total}</div>
    </>
  );
}
