import { useQuery } from '@tanstack/react-query';
import { getCategories } from '../api';
import type { Category } from '../types';

// Categories are seed data (10 rows, admin-only changes), but every page —
// and every detail-modal mount on top of it — used to refetch them. One
// cached query deduplicates all of those.
export function useCategories() {
  const query = useQuery({
    queryKey: ['categories'],
    queryFn: async (): Promise<Category[]> =>
      (await getCategories()).data.data ?? [],
    staleTime: 10 * 60 * 1000,
  });
  return { categories: query.data ?? [], loading: query.isLoading };
}
