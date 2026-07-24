import { useCallback, useRef, useState } from 'react';

/**
 * Keeps a skeleton collection aligned with the CSS-resolved layout.
 * The first placeholder supplies the real item width; the container supplies
 * the real gap and available width. This avoids duplicating responsive grid
 * breakpoints or card dimensions in JavaScript.
 */
export default function useSkeletonRows(rows: number) {
  const [count, setCount] = useState(Math.max(1, rows));
  const observerRef = useRef<ResizeObserver | null>(null);

  const containerRef = useCallback((node: HTMLDivElement | null) => {
    observerRef.current?.disconnect();
    observerRef.current = null;
    if (!node) return;

    const update = () => {
      const firstItem = node.firstElementChild as HTMLElement | null;
      if (!firstItem) return;

      const containerWidth = node.clientWidth;
      const styles = window.getComputedStyle(node);
      const itemWidth = Number.parseFloat(window.getComputedStyle(firstItem).width);
      const gap = Number.parseFloat(styles.columnGap || styles.gap) || 0;
      if (containerWidth <= 0 || itemWidth <= 0) return;

      const columns = Math.max(
        1,
        Math.floor((containerWidth + gap + 0.5) / (itemWidth + gap)),
      );
      const nextCount = columns * Math.max(1, rows);
      setCount((current) => current === nextCount ? current : nextCount);
    };

    update();
    const observer = new ResizeObserver(update);
    observer.observe(node);
    const firstItem = node.firstElementChild;
    if (firstItem) observer.observe(firstItem);
    observerRef.current = observer;
  }, [rows]);

  return { containerRef, count };
}
