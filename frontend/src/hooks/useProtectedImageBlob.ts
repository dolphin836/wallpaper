import { useEffect, useState } from 'react';

interface ProtectedImageBlobState {
  source: string;
  url: string;
  loading: boolean;
  failed: boolean;
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
export default function useProtectedImageBlob(source: string) {
  const [state, setState] = useState<ProtectedImageBlobState>(EMPTY_STATE);

  useEffect(() => {
    if (!source) return;

    const controller = new AbortController();
    let objectURL = '';

    void fetch(source, {
      credentials: 'include',
      // The signed view URL is stable for the current media version and its
      // response is private-cacheable. Let the browser reuse/revalidate it on
      // refresh; download URLs remain no-store on the backend.
      cache: 'default',
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`protected image request failed: ${response.status}`);
        return response.blob();
      })
      .then((blob) => {
        if (controller.signal.aborted) return;
        objectURL = URL.createObjectURL(blob);
        setState({ source, url: objectURL, loading: false, failed: false });
      })
      .catch((error: unknown) => {
        if (controller.signal.aborted || (error instanceof DOMException && error.name === 'AbortError')) return;
        setState({ source, url: '', loading: false, failed: true });
      });

    return () => {
      controller.abort();
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [source]);

  if (state.source !== source) {
    return { blobURL: '', loading: !!source, failed: false };
  }
  return { blobURL: state.url, loading: state.loading, failed: state.failed };
}
