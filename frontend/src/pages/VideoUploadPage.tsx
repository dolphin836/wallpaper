import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import * as tus from 'tus-js-client';
import toast from 'react-hot-toast';
import { AiOutlineCloudUpload, AiOutlineClose, AiOutlinePause, AiOutlinePlayCircle } from 'react-icons/ai';
import { useAuthStore } from '../store/auth';
import { resolveBaseURL } from '../api/client';
import usePageTitle from '../hooks/usePageTitle';

const MAX_SIZE = 200 * 1024 * 1024; // 200 MiB — must match TusHandler tusMaxSize.
const ACCEPT = 'video/mp4,video/quicktime,video/webm,video/x-matroska,.mp4,.mov,.webm,.mkv';

type UploadState = 'idle' | 'uploading' | 'paused' | 'done' | 'error';

// VideoUploadPage runs a single-file resumable upload against
// /api/v1/uploads/tus. Pause / resume / cancel are native to tus; on
// reload the previous tus URL is recovered from localStorage so the
// user can pick up where they left off after a browser restart.
export default function VideoUploadPage() {
  usePageTitle('Upload video');
  const { isAuthenticated, token } = useAuthStore();
  const navigate = useNavigate();
  useEffect(() => {
    if (!isAuthenticated) navigate('/login');
  }, [isAuthenticated, navigate]);

  const [file, setFile] = useState<File | null>(null);
  const [state, setState] = useState<UploadState>('idle');
  const [progress, setProgress] = useState(0); // 0–100
  const [bytesSent, setBytesSent] = useState(0);
  const [bytesTotal, setBytesTotal] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const uploadRef = useRef<tus.Upload | null>(null);

  const reset = () => {
    if (uploadRef.current) {
      uploadRef.current.abort(true).catch(() => {});
      uploadRef.current = null;
    }
    setFile(null);
    setState('idle');
    setProgress(0);
    setBytesSent(0);
    setBytesTotal(0);
    setError(null);
  };

  const startUpload = (f: File) => {
    if (!token) {
      toast.error('Please sign in first');
      return;
    }
    const endpoint = `${resolveBaseURL()}/uploads/tus`;
    const upload = new tus.Upload(f, {
      endpoint,
      // tus default chunk size = entire file in one PATCH, which means
      // pause / resume reuses the chunk boundary. 8 MB is small enough
      // to retry quickly on flaky connections but large enough to keep
      // HTTP overhead negligible.
      chunkSize: 8 * 1024 * 1024,
      retryDelays: [0, 1000, 3000, 5000, 10000],
      metadata: {
        filename: f.name,
        filetype: f.type || 'video/mp4',
      },
      headers: {
        Authorization: `Bearer ${token}`,
      },
      // Keep the upload URL in localStorage so a refresh / browser
      // restart can resume. tus-js-client manages this when storeFingerprintForResuming is true.
      storeFingerprintForResuming: true,
      removeFingerprintOnSuccess: true,
      onError(err) {
        setState('error');
        setError(err.message || 'Upload failed');
      },
      onProgress(sent, total) {
        setBytesSent(sent);
        setBytesTotal(total);
        setProgress(Math.round((sent / total) * 100));
      },
      onSuccess() {
        setState('done');
        setProgress(100);
        toast.success('Video uploaded — pending admin review');
      },
    });

    upload.findPreviousUploads().then((previous) => {
      if (previous.length > 0) {
        upload.resumeFromPreviousUpload(previous[0]);
      }
      upload.start();
      uploadRef.current = upload;
      setState('uploading');
      setError(null);
    });
  };

  const onPick = (f: File) => {
    if (!f.type.startsWith('video/') && !/\.(mp4|mov|webm|mkv)$/i.test(f.name)) {
      toast.error('Only video files are accepted');
      return;
    }
    if (f.size > MAX_SIZE) {
      toast.error(`Video must be ≤ 200 MB. This one is ${(f.size / 1024 / 1024).toFixed(1)} MB.`);
      return;
    }
    setFile(f);
    setBytesTotal(f.size);
    startUpload(f);
  };

  const pause = () => {
    if (uploadRef.current && state === 'uploading') {
      uploadRef.current.abort();
      setState('paused');
    }
  };
  const resume = () => {
    if (file && state === 'paused') {
      startUpload(file);
    }
  };

  return (
    <div className="bg-paper-2 min-h-full">
      <main className="px-6 sm:px-10 lg:px-16 py-10 max-w-[820px] mx-auto">
        <div className="mb-6">
          <div className="mono text-[10px] tracking-[0.18em] uppercase text-muted">Upload</div>
          <h1 className="display text-[32px] sm:text-[40px] leading-tight mt-1">Upload a video wallpaper</h1>
          <p className="text-ink-2 mt-2 max-w-2xl">
            One video at a time, up to 200&nbsp;MB. We&apos;ll transcode to H.264 and review
            before publishing — you&apos;ll see the status on{' '}
            <Link to="/profile" className="underline">your uploads</Link>.
          </p>
          <div className="mt-3 mono text-[11px] text-muted">
            Looking to upload images instead?{' '}
            <Link to="/upload" className="underline text-ink">/upload</Link>
          </div>
        </div>

        {state === 'idle' && (
          <label className="block border-2 border-dashed border-hair rounded-lg bg-paper p-10 text-center cursor-pointer hover:border-ink-2 transition-colors duration-200">
            <input
              type="file"
              accept={ACCEPT}
              className="sr-only"
              onChange={(e) => {
                const f = e.target.files?.[0];
                if (f) onPick(f);
              }}
            />
            <AiOutlineCloudUpload size={36} className="mx-auto text-muted-2 mb-3" />
            <div className="display text-[20px]">Choose a video</div>
            <div className="text-[12px] text-muted mt-1">MP4, MOV, WebM, MKV — max 200&nbsp;MB</div>
          </label>
        )}

        {file && state !== 'idle' && (
          <div className="border border-hair rounded-lg bg-paper p-5">
            <div className="flex items-center justify-between gap-3 mb-3">
              <div className="min-w-0">
                <div className="truncate text-ink">{file.name}</div>
                <div className="mono text-[11px] text-muted mt-0.5">
                  {humanize(bytesSent)} / {humanize(bytesTotal)} · {progress}%
                </div>
              </div>
              <div className="flex items-center gap-2">
                {state === 'uploading' && (
                  <button onClick={pause} className="btn-pill" title="Pause">
                    <AiOutlinePause size={14} /> Pause
                  </button>
                )}
                {state === 'paused' && (
                  <button onClick={resume} className="btn-pill" title="Resume">
                    <AiOutlinePlayCircle size={14} /> Resume
                  </button>
                )}
                {state !== 'done' && (
                  <button onClick={reset} className="btn-pill" title="Cancel">
                    <AiOutlineClose size={14} /> Cancel
                  </button>
                )}
              </div>
            </div>
            <div className="h-1.5 bg-paper-3 rounded-full overflow-hidden">
              <div
                className="h-full bg-ink transition-[width] duration-200"
                style={{ width: `${progress}%`, transitionTimingFunction: 'var(--ease-out-quart)' }}
              />
            </div>
            {state === 'error' && (
              <div className="mt-3 text-[13px] text-red-600">
                {error}{' '}
                <button onClick={() => file && startUpload(file)} className="underline">
                  Retry
                </button>
              </div>
            )}
            {state === 'done' && (
              <div className="mt-4 flex items-center gap-3">
                <span className="text-[13px]">
                  Uploaded — pending admin review.
                </span>
                <Link to="/profile" className="btn-pill btn-pill--action" style={{ padding: '8px 14px' }}>
                  <span className="lhs"><span>View my uploads</span></span>
                  <span className="arrow">→</span>
                </Link>
                <button onClick={reset} className="text-[12px] underline text-ink-2">
                  Upload another
                </button>
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}

function humanize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}
