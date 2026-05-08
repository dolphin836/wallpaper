import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDropzone } from 'react-dropzone';
import { resolveBaseURL } from '../api/client';
import {
  AiOutlineCloudUpload,
  AiOutlineClose,
  AiOutlineCheck,
  AiOutlineCloseCircle,
  AiOutlineLoading3Quarters,
} from 'react-icons/ai';
import toast from 'react-hot-toast';
import { useAuthStore } from '../store/auth';
import usePageTitle from '../hooks/usePageTitle';

const MAX_SIZE = 200 * 1024 * 1024;
const MAX_FILES = 20;

type FileStatus = 'pending' | 'uploading' | 'success' | 'error';

interface UploadFile {
  file: File;
  preview: string;
  status: FileStatus;
  progress: number;
  error?: string;
}

export default function UploadPage() {
  usePageTitle('Upload');
  const { isAuthenticated } = useAuthStore();
  const navigate = useNavigate();
  const [files, setFiles] = useState<UploadFile[]>([]);
  const [uploading, setUploading] = useState(false);

  useEffect(() => {
    if (!isAuthenticated) {
      navigate('/login');
    }
  }, [isAuthenticated, navigate]);

  const onDrop = useCallback((accepted: File[]) => {
    const remaining = MAX_FILES - files.length;
    if (remaining <= 0) {
      toast.error(`Maximum ${MAX_FILES} files allowed`);
      return;
    }
    const toAdd = accepted.slice(0, remaining);
    const oversized = toAdd.filter((f) => f.size > MAX_SIZE);
    if (oversized.length > 0) {
      toast.error(`${oversized.length} file(s) exceed 200MB limit and were skipped`);
    }
    const valid = toAdd.filter((f) => f.size <= MAX_SIZE);
    if (valid.length === 0) return;

    const newFiles: UploadFile[] = valid.map((f) => {
      const isHEIC = /\.heic$/i.test(f.name) || f.type === 'image/heic' || f.type === 'image/heif';
      return {
        file: f,
        preview: isHEIC ? '' : URL.createObjectURL(f),
        status: 'pending' as FileStatus,
        progress: 0,
      };
    });
    setFiles((prev) => [...prev, ...newFiles]);
  }, [files.length]);

  const removeFile = (index: number) => {
    if (uploading) return;
    setFiles((prev) => {
      URL.revokeObjectURL(prev[index].preview);
      return prev.filter((_, i) => i !== index);
    });
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'image/*': [], 'image/heic': ['.heic'], 'image/heif': ['.heif'] },
    maxFiles: MAX_FILES,
    maxSize: MAX_SIZE,
    disabled: uploading,
  });

  useEffect(() => {
    return () => {
      files.forEach((f) => URL.revokeObjectURL(f.preview));
    };
  }, []);

  const updateFile = (index: number, updates: Partial<UploadFile>) => {
    setFiles((prev) => prev.map((f, i) => (i === index ? { ...f, ...updates } : f)));
  };

  const handleUpload = async () => {
    if (files.length === 0) {
      toast.error('Please select at least one image');
      return;
    }

    setUploading(true);
    let success = 0;
    let failed = 0;

    for (let i = 0; i < files.length; i++) {
      if (files[i].status === 'success') {
        success++;
        continue;
      }

      updateFile(i, { status: 'uploading', progress: 0 });

      const formData = new FormData();
      formData.append('file', files[i].file);

      try {
        await new Promise<void>((resolve, reject) => {
          const xhr = new XMLHttpRequest();
          xhr.open('POST', `${resolveBaseURL()}/wallpapers`);

          const token = localStorage.getItem('token');
          if (token) {
            xhr.setRequestHeader('Authorization', `Bearer ${token}`);
          }

          xhr.upload.onprogress = (e) => {
            if (e.lengthComputable) {
              const pct = Math.round((e.loaded / e.total) * 100);
              updateFile(i, { progress: pct });
            }
          };

          xhr.onload = () => {
            if (xhr.status >= 200 && xhr.status < 300) {
              resolve();
            } else {
              let msg = `HTTP ${xhr.status}`;
              try {
                const body = JSON.parse(xhr.responseText);
                if (body.message) msg = body.message;
              } catch { /* use default */ }
              reject(new Error(msg));
            }
          };

          xhr.onerror = () => reject(new Error('Network error'));
          xhr.ontimeout = () => reject(new Error('Upload timeout'));
          xhr.send(formData);
        });

        updateFile(i, { status: 'success', progress: 100 });
        success++;
      } catch (err) {
        const msg = err instanceof Error ? err.message : 'Upload failed';
        updateFile(i, { status: 'error', progress: 0, error: msg });
        failed++;
      }
    }

    setUploading(false);
    if (failed === 0) {
      toast.success(`${success} wallpaper(s) uploaded successfully`);
      sessionStorage.removeItem('home_feed_cache');
      setTimeout(() => navigate('/'), 1000);
    } else {
      toast.error(`${success} succeeded, ${failed} failed — you can retry failed ones`);
    }
  };

  const totalDone = files.filter((f) => f.status === 'success').length;
  const totalError = files.filter((f) => f.status === 'error').length;
  const overallProgress = files.length > 0 ? Math.round((totalDone / files.length) * 100) : 0;

  if (!isAuthenticated) return null;

  return (
    <div className="max-w-4xl mx-auto px-6 py-6">
      <h1 className="text-2xl font-bold text-gray-900 mb-8">Upload Wallpapers</h1>

      <div
        {...getRootProps()}
        className={`border-2 border-dashed rounded-2xl p-8 text-center transition-colors duration-200 ${
          uploading
            ? 'border-gray-200 bg-gray-50 cursor-not-allowed'
            : isDragActive
              ? 'border-indigo-400 bg-indigo-50 cursor-pointer'
              : 'border-gray-300 bg-gray-50 hover:border-indigo-400 hover:bg-indigo-50 cursor-pointer'
        }`}
      >
        <input {...getInputProps()} />
        <div className="space-y-3">
          <AiOutlineCloudUpload className="mx-auto text-gray-400" size={48} />
          <p className="text-sm text-gray-600">
            Drag & drop images here, or click to select
          </p>
          <p className="text-xs text-gray-400">
            JPG, PNG, HEIC (macOS Dynamic Wallpaper) &middot; Max 200MB &middot; Up to {MAX_FILES} files
          </p>
        </div>
      </div>

      {files.length > 0 && (
        <>
          {/* Overall progress bar */}
          {uploading && (
            <div className="mt-6">
              <div className="flex items-center justify-between text-sm text-gray-600 mb-2">
                <span>Uploading {totalDone}/{files.length}</span>
                <span>{overallProgress}%</span>
              </div>
              <div className="h-2 bg-gray-200 rounded-full overflow-hidden">
                <div
                  className="h-full bg-indigo-600 rounded-full transition-all duration-300"
                  style={{ width: `${overallProgress}%` }}
                />
              </div>
            </div>
          )}

          <div className="mt-6 grid grid-cols-2 sm:grid-cols-4 md:grid-cols-5 gap-4">
            {files.map((f, idx) => (
              <div key={idx} className="relative group">
                <div className="aspect-square relative rounded-lg overflow-hidden">
                  {f.preview ? (
                    <img
                      src={f.preview}
                      alt=""
                      className={`w-full h-full object-cover transition-opacity duration-200 ${
                        f.status === 'uploading' ? 'opacity-60' : f.status === 'error' ? 'opacity-40' : ''
                      }`}
                    />
                  ) : (
                    <div className={`w-full h-full flex flex-col items-center justify-center bg-gradient-to-br from-gray-800 to-gray-900 ${
                      f.status === 'uploading' ? 'opacity-60' : f.status === 'error' ? 'opacity-40' : ''
                    }`}>
                      <svg width="24" height="24" viewBox="0 0 384 512" fill="white" className="mb-2 opacity-60"><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
                      <span className="text-[10px] text-white/50 font-medium text-center px-1 truncate w-full">{f.file.name}</span>
                    </div>
                  )}

                  {/* Per-file progress overlay */}
                  {f.status === 'uploading' && (
                    <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/20">
                      <AiOutlineLoading3Quarters size={24} className="text-white animate-spin mb-2" />
                      <div className="w-3/4 h-1.5 bg-white/30 rounded-full overflow-hidden">
                        <div
                          className="h-full bg-white rounded-full transition-all duration-200"
                          style={{ width: `${f.progress}%` }}
                        />
                      </div>
                      <span className="text-white text-xs mt-1 font-medium">{f.progress}%</span>
                    </div>
                  )}

                  {/* Success overlay */}
                  {f.status === 'success' && (
                    <div className="absolute inset-0 flex items-center justify-center bg-black/30">
                      <div className="w-10 h-10 bg-green-500 rounded-full flex items-center justify-center">
                        <AiOutlineCheck size={22} className="text-white" />
                      </div>
                    </div>
                  )}

                  {/* Error overlay */}
                  {f.status === 'error' && (
                    <div className="absolute inset-0 flex flex-col items-center justify-center bg-black/40 px-2">
                      <div className="w-10 h-10 bg-red-500 rounded-full flex items-center justify-center mb-1.5">
                        <AiOutlineCloseCircle size={22} className="text-white" />
                      </div>
                      {f.error && (
                        <span className="text-[10px] text-white/90 text-center leading-tight line-clamp-2">
                          {f.error}
                        </span>
                      )}
                    </div>
                  )}
                </div>

                {/* Remove button — only when not uploading */}
                {!uploading && f.status !== 'success' && (
                  <button
                    onClick={() => removeFile(idx)}
                    className="absolute top-1.5 right-1.5 w-6 h-6 flex items-center justify-center bg-black/50 text-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity"
                  >
                    <AiOutlineClose size={14} />
                  </button>
                )}
              </div>
            ))}
          </div>

          <div className="mt-6 flex items-center justify-between">
            <div className="text-sm text-gray-500">
              <span>{files.length} images</span>
              {totalDone > 0 && <span className="text-green-600 ml-2">{totalDone} done</span>}
              {totalError > 0 && <span className="text-red-500 ml-2">{totalError} failed</span>}
            </div>
            <button
              onClick={handleUpload}
              disabled={uploading || files.every((f) => f.status === 'success')}
              className="px-6 py-3 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors duration-200 disabled:opacity-50"
            >
              {uploading ? (
                <span className="flex items-center gap-2">
                  <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Uploading...
                </span>
              ) : totalError > 0 ? (
                'Retry Failed'
              ) : (
                `Upload ${files.length} image${files.length > 1 ? 's' : ''}`
              )}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
