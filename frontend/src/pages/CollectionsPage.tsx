import { useState, useEffect, useCallback, useRef } from 'react';
import { Trans, useTranslation } from 'react-i18next';
import type { Collection } from '../types';
import { getCollections } from '../api';
import PageMeta from '../components/PageMeta';
import ErrorState from '../components/ErrorState';
import EmptyState from '../components/EmptyState';
import Pagination from '../components/Pagination';
import {
  CollectionListCard,
  CollectionListCardSkeleton,
} from '../components/CollectionListCard';

const PAGE_SIZE = 12;

export default function CollectionsPage() {
  const { t } = useTranslation('collections');

  const [pages, setPages] = useState<Record<number, Collection[]>>({});
  const [cursors, setCursors] = useState<Record<number, number | undefined>>({ 1: undefined });
  // Total page count comes back on the first response (server returns
  // .total). That lets the Pagination control show the real ceiling
  // (e.g. "1 2 3 … 12") from the very first paint instead of
  // discovering pages cursor-by-cursor and showing "1 2" → "1 2 3".
  const [serverTotal, setServerTotal] = useState<number | null>(null);
  const [current, setCurrent] = useState(1);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  const fetchPage = useCallback(async (page: number) => {
    if (pages[page]) return;
    const cursor = cursors[page];
    if (page > 1 && cursor === undefined) return;
    setLoading(true);
    try {
      const res = await getCollections({ cursor, limit: PAGE_SIZE });
      const items = res.data.data.items || [];
      const nextCursor = res.data.data.next_cursor;
      const hasMore = res.data.data.has_more;
      const total = res.data.data.total;
      setPages((prev) => ({ ...prev, [page]: items }));
      if (hasMore && nextCursor) {
        setCursors((prev) => ({ ...prev, [page + 1]: nextCursor }));
      }
      if (typeof total === 'number') {
        setServerTotal(total);
      }
      setError(false);
    } catch {
      setError(true);
    } finally {
      setLoading(false);
    }
  }, [pages, cursors]);

  useEffect(() => { fetchPage(current); }, [current, fetchPage]);

  const visible = pages[current] || [];
  // Real page total from the server count. Falls back to 1 only while
  // the very first request is in flight.
  const total = serverTotal !== null ? Math.max(1, Math.ceil(serverTotal / PAGE_SIZE)) : 1;

  const rootRef = useRef<HTMLDivElement | null>(null);
  const applyTints = useCallback((tints: string[] | null) => {
    const root = rootRef.current;
    if (!root) return;
    if (!tints?.length) {
      root.style.removeProperty('--c-list-c1');
      root.style.removeProperty('--c-list-c2');
      root.style.removeProperty('--c-list-c3');
      return;
    }
    const [c1, c2 = c1, c3 = c2] = tints;
    root.style.setProperty('--c-list-c1', c1);
    root.style.setProperty('--c-list-c2', c2);
    root.style.setProperty('--c-list-c3', c3);
  }, []);

  return (
    <div ref={rootRef} className="c-list min-h-full">
      <div className="c-list-mesh" aria-hidden />
      <PageMeta
        title={t('meta.titleThemes')}
        description={t('meta.descriptionThemes')}
      />

      <main className="c5-shell">
        <header className="c5-header">
          <div className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
            {t('list.kickerThemes')}
          </div>
          <h1 className="display c5-header-title">
            <Trans i18nKey="list.headingThemes" ns="collections" components={[<em key="0" />]} />
          </h1>
          <p className="c5-header-intro">
            {t('list.introThemes')}
          </p>
        </header>

        {loading && visible.length === 0 ? (
          <CollectionsSkeleton current={current} />
        ) : error && visible.length === 0 ? (
          <ErrorState />
        ) : visible.length === 0 ? (
          <EmptyState
            title={t('list.emptyTitle')}
            message={t('list.emptyMessage')}
          />
        ) : (
          <div className="c5-list">
            {visible.map((c, index) => (
              <CollectionListCard
                key={c.id}
                collection={c}
                eager={current === 1 && index === 0}
                onTintsChange={applyTints}
              />
            ))}
          </div>
        )}

        <Pagination
          current={current}
          total={total}
          maxReachable={Math.max(1, ...Object.entries(cursors)
            .filter(([, v]) => v !== undefined)
            .map(([k]) => Number(k)))}
          onChange={setCurrent}
        />
      </main>
    </div>
  );
}

/* The loading view mirrors the resolved horizontal card list exactly. */
function CollectionsSkeleton({ current }: { current: number }) {
  return (
    <div className="c5-list" aria-hidden>
      {Array.from({ length: PAGE_SIZE }).map((_, i) => (
        <CollectionListCardSkeleton key={`${current}-${i}`} />
      ))}
    </div>
  );
}
