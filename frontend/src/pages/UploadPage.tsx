import { useState, useEffect, useCallback, useRef } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { Trans, useTranslation } from 'react-i18next';
import { useDropzone } from 'react-dropzone';
import * as tus from 'tus-js-client';
import { resolveUploadBaseURL } from '../api/client';
import {
  AiOutlineCloudUpload,
  AiOutlineClose,
  AiOutlineCheck,
  AiOutlineCloseCircle,
  AiOutlineLoading3Quarters,
  AiOutlineReload,
} from 'react-icons/ai';
import toast from 'react-hot-toast';
import { track } from '../lib/track';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';

const MAX_SIZE = 200 * 1024 * 1024;
const MAX_FILES = 20;
const MAX_VIDEO_FILES = 10;
const IMAGE_UPLOAD_TIMEOUT_MS = 15 * 60 * 1000;
const MIN_VIDEO_LONG_EDGE = 1920;
const MIN_VIDEO_SHORT_EDGE = 1080;

type FileStatus = 'pending' | 'uploading' | 'success' | 'error';
type UploadPhase = 'sending' | 'confirming';
type PreparationStatus = 'preparing' | 'ready' | 'error';

interface UploadFile {
  id: string;
  file: File;
  preview: string;
  width?: number;
  height?: number;
  status: FileStatus;
  preparation: PreparationStatus;
  progress: number;
  phase?: UploadPhase;
  error?: string;
}

interface UploadSummary {
  success: number;
  failed: number;
  blocked: number;
}

const isVideoFile = (f: File) =>
  (f.type || '').startsWith('video/') ||
  /\.(mp4|mov|webm|mkv)$/i.test(f.name);

const isHeicFile = (f: File) =>
  /\.hei[cf]$/i.test(f.name) || f.type === 'image/heic' || f.type === 'image/heif';

const meetsMinimumVideoResolution = (width?: number, height?: number) => {
  if (!width || !height) return false;
  return Math.max(width, height) >= MIN_VIDEO_LONG_EDGE
    && Math.min(width, height) >= MIN_VIDEO_SHORT_EDGE;
};

const formatFileSize = (bytes: number) => {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

export default function UploadPage() {
  const { t } = useTranslation('upload');
  usePageTitle(t('meta.pageTitle'));
  const { isAuthenticated, user } = useAuthStore();
  const navigate = useNavigate();
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadSummary, setUploadSummary] = useState<UploadSummary | null>(null);

  useEffect(() => {
    if (!isAuthenticated) {
      navigate('/login');
    }
  }, [isAuthenticated, navigate]);

  const onDrop = useCallback((accepted: File[]) => {
    const remaining = MAX_FILES - files.length;
    if (remaining <= 0) {
      toast.error(t('toast.maxFiles', { max: MAX_FILES }));
      return;
    }
    const oversized = accepted.filter((f) => f.size > MAX_SIZE);
    if (oversized.length > 0) {
      toast.error(t('toast.oversized', { num: oversized.length }));
    }
    const sizeOK = accepted.filter((f) => f.size <= MAX_SIZE);
    if (sizeOK.length === 0) return;

    // Images and videos can share one queue. Videos still upload one after
    // another through tus, but a batch may now contain up to ten of them.
    let videoSlots = MAX_VIDEO_FILES - files.filter((f) => isVideoFile(f.file)).length;
    let skippedVideos = 0;
    const withinVideoLimit = sizeOK.filter((f) => {
      if (!isVideoFile(f)) return true;
      if (videoSlots <= 0) {
        skippedVideos++;
        return false;
      }
      videoSlots--;
      return true;
    });
    if (skippedVideos > 0) {
      toast.error(t('toast.maxVideos', { max: MAX_VIDEO_FILES }));
    }

    const toAdd = withinVideoLimit.slice(0, remaining);
    if (withinVideoLimit.length > remaining) {
      toast.error(t('toast.maxFiles', { max: MAX_FILES }));
    }
    if (toAdd.length === 0) return;

    const newFiles: UploadFile[] = toAdd.map((f) => {
      const heic = isHeicFile(f);
      return {
        id: crypto.randomUUID(),
        file: f,
        preview: heic ? '' : URL.createObjectURL(f),
        status: 'pending' as FileStatus,
        // Browsers do not consistently decode HEIC previews. The backend can,
        // so HEIC files are ready immediately while other media wait for the
        // preview element to confirm that their metadata can be read.
        preparation: heic ? 'ready' : 'preparing',
        progress: 0,
      };
    });
    setUploadSummary(null);
    setFiles((prev) => [...prev, ...newFiles]);
  }, [files, t]);

  const removeFile = (index: number) => {
    if (uploading) return;
    const target = files[index];
    if (!target) return;
    setUploadSummary(null);
    if (target.preview) URL.revokeObjectURL(target.preview);
    setFiles((prev) => prev.filter((item) => item.id !== target.id));
  };

  const { getRootProps, getInputProps, isDragActive, open } = useDropzone({
    onDrop,
    accept: {
      'image/*': [],
      'image/heic': ['.heic'],
      'image/heif': ['.heif'],
      'video/mp4': ['.mp4'],
      'video/quicktime': ['.mov'],
      'video/webm': ['.webm'],
      'video/x-matroska': ['.mkv'],
    },
    maxFiles: MAX_FILES,
    maxSize: MAX_SIZE,
    disabled: uploading,
    noClick: files.length > 0, // After first file, the dropzone shrinks; clicks go through the "Add more" button below.
  });

  const tusRef = useRef<tus.Upload | null>(null);

  useEffect(() => {
    return () => {
      files.forEach((f) => URL.revokeObjectURL(f.preview));
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const updateFile = (index: number, updates: Partial<UploadFile>) => {
    setFiles((prev) => prev.map((f, i) => (i === index ? { ...f, ...updates } : f)));
  };

  const updateFileDimensions = useCallback((id: string, width: number, height: number) => {
    if (width <= 0 || height <= 0) return;
    setFiles((prev) => prev.map((f) => (
      f.id === id && (f.width !== width || f.height !== height || f.preparation !== 'ready')
        ? { ...f, width, height, preparation: 'ready' }
        : f
    )));
  }, []);

  const markPreparationFailed = useCallback((id: string) => {
    setFiles((prev) => prev.map((f) => (
      f.id === id ? { ...f, preparation: 'error' } : f
    )));
  }, []);

  const clearQueue = () => {
    if (uploading) return;
    files.forEach((item) => {
      if (item.preview) URL.revokeObjectURL(item.preview);
    });
    setFiles([]);
    setUploadSummary(null);
  };

  const handleUpload = async () => {
    if (files.length === 0) {
      toast.error(t('toast.selectAtLeastOne'));
      return;
    }

    const hasPreparingFile = files.some((item) => item.preparation === 'preparing');
    if (hasPreparingFile) {
      toast.error(t('toast.waitForPreparation'));
      return;
    }
    const uploadableIndexes = files
      .map((item, index) => ({ item, index }))
      .filter(({ item }) => item.status !== 'success'
        && item.preparation === 'ready'
        && (!isVideoFile(item.file) || meetsMinimumVideoResolution(item.width, item.height)))
      .map(({ index }) => index);
    if (uploadableIndexes.length === 0) {
      toast.error(t('toast.noUploadableFiles'));
      return;
    }

    setUploadSummary(null);
    setUploading(true);
    let success = 0;
    let failed = 0;

    for (let i = 0; i < files.length; i++) {
      if (files[i].status === 'success') {
        success++;
        continue;
      }
      if (!uploadableIndexes.includes(i)) continue;
      updateFile(i, { status: 'uploading', progress: 0, phase: 'sending', error: undefined });
      try {
        if (isVideoFile(files[i].file)) {
          await uploadVideoTus(i, files[i].file, files[i].width!, files[i].height!);
        } else {
          await uploadImageMultipart(i, files[i].file);
        }
        updateFile(i, { status: 'success', progress: 100, phase: undefined });
        success++;
      } catch (err) {
        const msg = err instanceof Error ? err.message : t('errors.uploadFailed');
        updateFile(i, { status: 'error', progress: 0, phase: undefined, error: msg });
        failed++;
      }
    }

    setUploading(false);
    const blocked = files.filter((item) => item.status !== 'success' && (
      item.preparation === 'error'
      || (isVideoFile(item.file)
        && item.preparation === 'ready'
        && !meetsMinimumVideoResolution(item.width, item.height))
    )).length;
    setUploadSummary({ success, failed, blocked });
    track('upload_complete', { succeeded: success, failed, blocked });
    if (failed === 0 && blocked === 0) {
      toast.success(
        success === 1
          ? t('toast.successOne')
          : t('toast.successMany', { num: success }),
      );
    } else if (failed > 0) {
      toast.error(t('toast.partialFail', { success, failed }));
    } else {
      toast.success(t('toast.validUploaded', { num: success }));
    }
  };

  const uploadImageMultipart = (i: number, f: File) =>
    new Promise<void>((resolve, reject) => {
      const formData = new FormData();
      formData.append('file', f);
      const xhr = new XMLHttpRequest();
      xhr.open('POST', `${resolveUploadBaseURL()}/wallpapers`);
      xhr.timeout = IMAGE_UPLOAD_TIMEOUT_MS;
      const token = localStorage.getItem('token');
      if (token) xhr.setRequestHeader('Authorization', `Bearer ${token}`);
      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable) {
          // Reserve the final 5% for origin acknowledgement. Browser upload
          // progress only means the nearest Cloudflare edge accepted the
          // bytes; it does not mean the API and MinIO have persisted them.
          updateFile(i, {
            phase: 'sending',
            progress: Math.min(95, Math.round((e.loaded / e.total) * 95)),
          });
        }
      };
      xhr.upload.onload = () => updateFile(i, { phase: 'confirming', progress: 95 });
      xhr.onload = () => {
        if (xhr.status >= 200 && xhr.status < 300) return resolve();
        let msg = `HTTP ${xhr.status}`;
        try {
          const body = JSON.parse(xhr.responseText);
          if (body.message) msg = body.message;
        } catch { /* keep default */ }
        reject(new Error(msg));
      };
      xhr.onerror = () => reject(new Error(t('errors.network')));
      xhr.ontimeout = () => reject(new Error(t('errors.timeout')));
      xhr.onabort = () => reject(new Error(t('errors.network')));
      xhr.send(formData);
    });

  const uploadVideoTus = (i: number, f: File, width: number, height: number) =>
    new Promise<void>((resolve, reject) => {
      const token = localStorage.getItem('token');
      if (!token) return reject(new Error(t('errors.signInFirst')));
      const uploadBase = resolveUploadBaseURL();
      const base = uploadBase.startsWith('http')
        ? uploadBase
        : `${window.location.origin}${uploadBase}`;
      const upload = new tus.Upload(f, {
        endpoint: `${base}/uploads/tus`,
        chunkSize: 8 * 1024 * 1024,
        retryDelays: [0, 1000, 3000, 5000, 10000],
        metadata: {
          filename: f.name,
          filetype: f.type || 'video/mp4',
          width: String(width),
          height: String(height),
        },
        headers: { Authorization: `Bearer ${token}` },
        storeFingerprintForResuming: true,
        removeFingerprintOnSuccess: true,
        onError: (err) => reject(new Error(err.message || t('errors.uploadFailed'))),
        onProgress: (sent, total) => {
          const sentAll = sent >= total;
          updateFile(i, {
            phase: sentAll ? 'confirming' : 'sending',
            progress: sentAll ? 95 : Math.min(94, Math.round((sent / total) * 95)),
          });
        },
        onSuccess: () => resolve(),
      });
      upload.findPreviousUploads().then((prev) => {
        if (prev.length > 0) upload.resumeFromPreviousUpload(prev[0]);
        upload.start();
        tusRef.current = upload;
      });
    });

  const totalDone = files.filter((f) => f.status === 'success').length;
  const totalError = files.filter((f) => f.status === 'error').length;
  const blockedCount = files.filter((f) => isVideoFile(f.file)
    && !!f.width && !!f.height
    && !meetsMinimumVideoResolution(f.width, f.height)).length;
  const preparingCount = files.filter((f) => f.preparation === 'preparing').length;
  const unreadableCount = files.filter((f) => f.preparation === 'error').length;
  const totalPending = files.filter((f) => (f.status === 'pending' || f.status === 'uploading')
    && f.preparation === 'ready'
    && (!isVideoFile(f.file) || meetsMinimumVideoResolution(f.width, f.height))).length;
  const uploadableCount = files.filter((f) => f.status !== 'success'
    && f.preparation === 'ready'
    && (!isVideoFile(f.file) || meetsMinimumVideoResolution(f.width, f.height))).length;
  const overallProgress = files.length > 0
    ? Math.round(files.reduce((sum, f) => sum + f.progress, 0) / files.length)
    : 0;
  const allDone = files.length > 0 && blockedCount === 0 && unreadableCount === 0
    && files.every((f) => f.status === 'success');

  const uploadControls = files.length > 0 && (
    <div className={`upload-bar${allDone ? ' is-done' : ''}`}>
      <div className="upload-bar-inner">
        <div className="upload-bar-status">
          {uploading ? (
            <div className="upload-bar-progress-row">
              <div className="upload-bar-progress">
                <div
                  className="upload-bar-progress-fill"
                  style={{ width: `${overallProgress}%` }}
                />
              </div>
              <span className="mono text-[11px] tracking-[0.06em] text-ink-2 tabular-nums shrink-0">
                {totalDone}/{files.length} · {overallProgress}%
              </span>
            </div>
          ) : allDone ? (
            <div className="flex items-center gap-2 text-ink">
              <AiOutlineCheck size={16} className="text-accent" />
              <span className="text-[13px]">{t('bar.allDone')}</span>
            </div>
          ) : (
            <div className="text-[13px] text-ink-2">
              {totalPending === 1 ? t('bar.readyOne') : t('bar.ready', { num: totalPending })}
              {totalError > 0 && (
                <span className="text-red-500"> · {t('bar.needRetry', { num: totalError })}</span>
              )}
              {blockedCount > 0 && (
                <span className="text-red-500"> · {t('bar.blocked', { num: blockedCount })}</span>
              )}
              {preparingCount > 0 && (
                <span className="text-muted"> · {t('bar.preparing', { num: preparingCount })}</span>
              )}
              {unreadableCount > 0 && (
                <span className="text-red-500"> · {t('bar.unreadable', { num: unreadableCount })}</span>
              )}
            </div>
          )}
        </div>

        {!uploading && !allDone && (
          <Link
            to={user?.username ? `/user/${user.username}` : '/'}
            className="upload-bar-link"
          >
            {t('bar.cancel')}
          </Link>
        )}

        <button
          onClick={handleUpload}
          disabled={uploading || allDone || uploadableCount === 0 || preparingCount > 0}
          className="upload-bar-go"
        >
          {uploading ? (
            <>
              <AiOutlineLoading3Quarters size={14} className="animate-spin" />
              {t('bar.uploading')}
            </>
          ) : preparingCount > 0 ? (
            <>
              <AiOutlineLoading3Quarters size={14} className="animate-spin" />
              {t('bar.preparingButton', { num: preparingCount })}
            </>
          ) : totalError > 0 ? (
            t('bar.retryFailed')
          ) : allDone ? (
            t('bar.done')
          ) : uploadableCount === 1 ? (
            t('bar.uploadOne')
          ) : (
            t('bar.uploadMany', { num: uploadableCount })
          )}
        </button>
      </div>
    </div>
  );

  if (!isAuthenticated) return null;

  return (
    <div className="upload-page min-h-full">
      <div className="upload-mesh" aria-hidden />

      <div className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-10 pb-20">
        {/* Editorial header */}
        <header className="mb-10">
          <div className="kicker text-muted">{t('header.kicker')}</div>
          <h1 className="display text-[clamp(36px,5vw,64px)] leading-[1.02] mt-3 tracking-[-0.015em] text-ink">
            <Trans i18nKey="header.heading" ns="upload" components={[<span className="upload-title-tail" key="0" />]} />
          </h1>
          <p className="text-ink-2 mt-4 max-w-[640px] text-[14.5px] leading-relaxed">
            {t('header.intro', { maxFiles: MAX_FILES, maxVideos: MAX_VIDEO_FILES })}
          </p>
        </header>

        {/* Review-flow notice */}
        <div className="upload-notice mb-8">
          <div className="upload-notice-dot" aria-hidden />
          <div>
            <div className="mono text-[10px] tracking-[0.18em] uppercase text-ink-2 mb-1">{t('notice.kicker')}</div>
            <p className="text-[13px] leading-[1.55] text-ink-2">
              {t('notice.body')}
            </p>
          </div>
        </div>

        {/* Drop canvas */}
        <div
          {...getRootProps()}
          className={`upload-drop${isDragActive ? ' is-active' : ''}${uploading ? ' is-disabled' : ''}${
            files.length > 0 ? ' is-compact' : ''
          }`}
        >
          <input {...getInputProps()} />
          <div className="upload-drop-icon" aria-hidden>
            <AiOutlineCloudUpload size={files.length > 0 ? 28 : 44} />
          </div>
          {files.length === 0 ? (
            <>
              <p className="display text-[24px] sm:text-[28px] text-ink leading-tight mt-3">
                {isDragActive ? t('dropzone.dropActive') : t('dropzone.dropIdle')}
              </p>
              <p className="text-ink-2 text-[13px] mt-2 max-w-md">
                <Trans
                  i18nKey="dropzone.orPick"
                  ns="upload"
                  components={[
                    <button type="button" onClick={open} className="text-ink underline underline-offset-2 decoration-1 hover:text-accent" key="0" />,
                  ]}
                />
              </p>
              <div className="upload-drop-meta">
                <span>JPG · PNG · HEIC</span>
                <span>·</span>
                <span>MP4 · MOV · WebM</span>
                <span>·</span>
                <span>≤ 200 MB</span>
                <span>·</span>
                <span>{t('dropzone.videoMinimum')}</span>
                <span>·</span>
                <span>{t('dropzone.upToFiles', { max: MAX_FILES })}</span>
                <span>·</span>
                <span>{t('dropzone.upToVideos', { max: MAX_VIDEO_FILES })}</span>
              </div>
            </>
          ) : (
            <button
              type="button"
              onClick={open}
              disabled={uploading || files.length >= MAX_FILES}
              className="upload-drop-add"
            >
              {t('dropzone.addMore', { current: files.length, max: MAX_FILES })}
            </button>
          )}
        </div>

        {files.length > 0 && (
          <section className="mt-10">
            <div className="label-rule mb-4">
              {t('queue.label', { num: files.length })} {totalDone > 0 && <span className="text-accent">· {t('queue.done', { num: totalDone })}</span>}
              {totalError > 0 && <span className="text-red-500"> · {t('queue.failed', { num: totalError })}</span>}
            </div>

            <div className="upload-grid">
              {files.map((f, idx) => (
                <UploadTile
                  key={f.id}
                  file={f}
                  index={idx}
                  uploading={uploading}
                  onRemove={() => removeFile(idx)}
                  onDimensions={(width, height) => updateFileDimensions(f.id, width, height)}
                  onPreparationError={() => markPreparationFailed(f.id)}
                />
              ))}
            </div>
            {uploadSummary && !uploading ? (
              <div className={`upload-result${uploadSummary.failed > 0 || uploadSummary.blocked > 0 ? ' is-partial' : ''}`} role="status">
                <div className="upload-result-icon" aria-hidden>
                  {uploadSummary.failed > 0 || uploadSummary.blocked > 0
                    ? <AiOutlineCloseCircle size={22} />
                    : <AiOutlineCheck size={22} />}
                </div>
                <div className="upload-result-copy">
                  <div className="display text-[19px] leading-tight text-ink">
                    {uploadSummary.failed > 0 || uploadSummary.blocked > 0
                      ? t('result.partialTitle')
                      : t('result.successTitle')}
                  </div>
                  <div className="mt-1 text-[13px] text-ink-2 tabular-nums">
                    {t('result.summary', { success: uploadSummary.success, failed: uploadSummary.failed })}
                    {uploadSummary.blocked > 0 && (
                      <span className="text-red-500"> · {t('result.blocked', { num: uploadSummary.blocked })}</span>
                    )}
                  </div>
                  <p className="mt-1.5 text-[12px] leading-relaxed text-muted">
                    {t('result.hint')}
                  </p>
                </div>
                <div className="upload-result-actions">
                  {uploadSummary.failed > 0 && (
                    <button type="button" onClick={handleUpload} className="upload-result-button is-primary">
                      <AiOutlineReload size={14} />
                      {t('result.retry', { num: uploadSummary.failed })}
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={clearQueue}
                    className={`upload-result-button${uploadSummary.failed === 0 ? ' is-primary' : ' is-secondary'}`}
                  >
                    {t('result.newBatch')}
                  </button>
                  <Link
                    to={user?.username ? `/user/${user.username}` : '/'}
                    className="upload-result-link"
                  >
                    {t('result.viewUploads')}
                  </Link>
                </div>
              </div>
            ) : uploadControls}
          </section>
        )}
      </div>
    </div>
  );
}

/* Single file tile — preview thumb + status overlay. Matches the
   .dev-spec-card chrome from the device pages so the queue reads
   as part of the same family. */
function UploadTile({
  file: f,
  index,
  uploading,
  onRemove,
  onDimensions,
  onPreparationError,
}: {
  file: UploadFile;
  index: number;
  uploading: boolean;
  onRemove: () => void;
  onDimensions: (width: number, height: number) => void;
  onPreparationError: () => void;
}) {
  const { t } = useTranslation('upload');
  const isVideo = isVideoFile(f.file);
  return (
    <div className={`upload-tile${f.status === 'error' || f.preparation === 'error' || (isVideo && !!f.width && !!f.height && !meetsMinimumVideoResolution(f.width, f.height)) ? ' is-error' : ''}${f.status === 'success' ? ' is-success' : ''}`}>
      <div className="upload-tile-screen">
        {f.preview && isVideo ? (
          <video
            src={f.preview}
            muted
            loop
            playsInline
            autoPlay
            onLoadedMetadata={(event) => {
              onDimensions(event.currentTarget.videoWidth, event.currentTarget.videoHeight);
            }}
            onError={onPreparationError}
            className="upload-tile-media"
          />
        ) : f.preview ? (
          <img
            src={f.preview}
            alt=""
            onLoad={(event) => {
              onDimensions(event.currentTarget.naturalWidth, event.currentTarget.naturalHeight);
            }}
            onError={onPreparationError}
            className="upload-tile-media"
          />
        ) : (
          <div className="upload-tile-heic">
            <svg width="22" height="22" viewBox="0 0 384 512" fill="currentColor" aria-hidden>
              <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
            </svg>
          </div>
        )}

        {f.preparation === 'preparing' && (
          <div className="upload-tile-overlay is-preparing">
            <AiOutlineLoading3Quarters size={18} className="text-paper animate-spin" />
            <span className="mono text-[10px] tracking-[0.06em] text-paper mt-2">
              {t('queue.preparing')}
            </span>
          </div>
        )}

        {f.preparation === 'error' && f.status !== 'uploading' && (
          <div className="upload-tile-overlay is-error">
            <div className="upload-tile-badge is-error">
              <AiOutlineCloseCircle size={20} />
            </div>
            <span className="text-[10px] text-paper text-center leading-snug mt-2 px-2">
              {t('queue.unreadable')}
            </span>
          </div>
        )}

        {f.status === 'uploading' && (
          <div className="upload-tile-overlay">
            <AiOutlineLoading3Quarters size={20} className="text-paper animate-spin mb-2" />
            <div className="upload-tile-progress">
              <div className="upload-tile-progress-fill" style={{ width: `${f.progress}%` }} />
            </div>
            <span className="mono text-[10px] tracking-[0.06em] text-paper mt-1.5 tabular-nums">
              {f.phase === 'confirming' ? t('queue.confirming') : `${f.progress}%`}
            </span>
          </div>
        )}

        {f.status === 'success' && (
          <div className="upload-tile-overlay is-success" aria-hidden>
            <div className="upload-tile-badge is-success">
              <AiOutlineCheck size={20} />
            </div>
          </div>
        )}

        {f.status === 'error' && (
          <div className="upload-tile-overlay is-error">
            <div className="upload-tile-badge is-error">
              <AiOutlineCloseCircle size={20} />
            </div>
            {f.error && (
              <span className="text-[10px] text-paper text-center leading-snug mt-2 px-2 line-clamp-2">
                {f.error}
              </span>
            )}
          </div>
        )}

        {f.status === 'pending' && isVideo && f.width && f.height && !meetsMinimumVideoResolution(f.width, f.height) && (
          <div className="upload-tile-overlay is-error">
            <div className="upload-tile-badge is-error">
              <AiOutlineCloseCircle size={20} />
            </div>
            <span className="text-[10px] text-paper text-center leading-snug mt-2 px-2">
              {t('queue.lowResolution')}
            </span>
          </div>
        )}

        {!uploading && f.status !== 'success' && (
          <button
            onClick={onRemove}
            title={t('queue.remove')}
            className="upload-tile-x"
          >
            <AiOutlineClose size={13} />
          </button>
        )}
      </div>
      <div className="upload-tile-foot">
        <span className="mono text-[10px] text-muted tabular-nums">
          {String(index + 1).padStart(2, '0')}
        </span>
        <span className="upload-tile-meta mono tabular-nums">
          {f.width && f.height
            ? `${f.width.toLocaleString()} × ${f.height.toLocaleString()}`
            : '— × —'}
          <span aria-hidden> · </span>
          {formatFileSize(f.file.size)}
        </span>
      </div>
    </div>
  );
}
