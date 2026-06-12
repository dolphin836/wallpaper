import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import './index.css'
import i18n from './i18n'
import App from './App.tsx'

// Shared cache for read-mostly server state. Conservative defaults: data is
// fresh for 1min (no refetch storms while navigating between the grid and
// detail modals), one retry, no focus refetch (this is a media-browsing
// site, not a dashboard).
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 60 * 1000,
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
})

// Server responses carry content localized via Accept-Language (category /
// tag names, collection titles), so a language switch makes every cached
// query stale at once — drop them all and refetch in the new language.
i18n.on('languageChanged', () => {
  void queryClient.invalidateQueries()
})

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
)
