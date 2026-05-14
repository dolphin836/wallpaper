import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { track } from '../lib/track';

export default function usePageView() {
  const location = useLocation();
  useEffect(() => {
    track('page_view');
  }, [location.pathname, location.search]);
}
