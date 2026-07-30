import { useEffect, useState } from 'react';

interface ProtectedImageBlobState {
  source: string;
  url: string;
  loading: boolean;
  failed: boolean;
}

interface ProtectedImageBlobOptions {
  timeoutMs?: number;
  retries?: number;
}

const EMPTY_STATE: ProtectedImageBlobState = {
  source: '',
  url: '',
  loading: false,
  failed: false,
};

/**
 * Loads a short-lived, cookie-bound original into memory and exposes only a
 * blob: URL to image elements. This is deliberately a modest download
 * deterrent, not DRM: a determined visitor can still inspect the response or
 * capture the decoded pixels.
 */
export default function useProtectedImageBlob(
  source: string,
  options: ProtectedImageBlobOptions = {},
) {
  const [state, setState] = useState<ProtectedImageBlobState>(EMPTY_STATE);
  const timeoutMs = Math.max(0, options.timeoutMs ?? 0);
  const retries = Math.max(0, Math.floor(options.retries ?? 0));

  useEffect(() => {
    if (!source) return;

    let active = true;
    let controller: AbortController | null = null;
    let objectURL = '';
    let retryTimer: ReturnType<typeof setTimeout> | null = null;

    const load = async (attempt: number) => {
      const requestController = new AbortController();
      controller = requestController;
      const timeout = timeoutMs > 0
        ? setTimeout(() => requestController.abort(), timeoutMs)
        : null;

      try {
        const response = await fetch(source, {
          credentials: 'include',
          // The signed view URL is stable for the current media version and its
          // response is private-cacheable. Let the browser reuse/revalidate it on
          // refresh; download URLs remain no-store on the backend.
          cache: 'default',
          signal: requestController.signal,
        });
        if (!response.ok) throw new Error(`protected image request failed: ${response.status}`);
        const blob = await response.blob();
        if (!active) return;
        objectURL = URL.createObjectURL(blob);
        setState({ source, url: objectURL, loading: false, failed: false });
      } catch {
        if (!active) return;
        if (attempt < retries) {
          retryTimer = setTimeout(() => void load(attempt + 1), 400);
          return;
        }
        setState({ source, url: '', loading: false, failed: true });
      } finally {
        if (timeout) clearTimeout(timeout);
      }
    };

    void load(0);

    return () => {
      active = false;
      controller?.abort();
      if (retryTimer) clearTimeout(retryTimer);
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [retries, source, timeoutMs]);

  if (state.source !== source) {
    return { blobURL: '', loading: !!source, failed: false };
  }
  return { blobURL: state.url, loading: state.loading, failed: state.failed };
}
