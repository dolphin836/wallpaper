import { useEffect } from 'react';

const SITE_NAME = 'Wallpaper Exchange';

export default function usePageTitle(title?: string) {
  useEffect(() => {
    document.title = title ? `${title} — ${SITE_NAME}` : `${SITE_NAME} — Discover, Share & Download HD Wallpapers`;
  }, [title]);
}
