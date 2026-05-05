import { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDropzone } from 'react-dropzone';
import { AiOutlineCloudUpload, AiOutlineClose } from 'react-icons/ai';
import toast from 'react-hot-toast';
import { uploadWallpaper } from '../api';
import { useAuthStore } from '../store/auth';

const MAX_SIZE = 20 * 1024 * 1024;
const MAX_FILES = 20;

interface FileWithPreview {
  file: File;
  preview: string;
}

export default function UploadPage() {
  const { isAuthenticated } = useAuthStore();
  const navigate = useNavigate();
  const [files, setFiles] = useState<FileWithPreview[]>([]);
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState(0);

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
      toast.error(`${oversized.length} file(s) exceed 20MB limit and were skipped`);
    }
    const valid = toAdd.filter((f) => f.size <= MAX_SIZE);
    if (valid.length === 0) return;

    const newFiles = valid.map((f) => ({
      file: f,
      preview: URL.createObjectURL(f),
    }));
    setFiles((prev) => [...prev, ...newFiles]);
  }, [files.length]);

  const removeFile = (index: number) => {
    setFiles((prev) => {
      URL.revokeObjectURL(prev[index].preview);
      return prev.filter((_, i) => i !== index);
    });
  };

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: { 'image/*': [] },
    maxFiles: MAX_FILES,
    maxSize: MAX_SIZE,
  });

  useEffect(() => {
    return () => {
      files.forEach((f) => URL.revokeObjectURL(f.preview));
    };
  }, []);

  const handleUpload = async () => {
    if (files.length === 0) {
      toast.error('Please select at least one image');
      return;
    }

    setLoading(true);
    setProgress(0);
    let success = 0;
    let failed = 0;

    for (let i = 0; i < files.length; i++) {
      const formData = new FormData();
      formData.append('file', files[i].file);
      try {
        await uploadWallpaper(formData);
        success++;
      } catch {
        failed++;
      }
      setProgress(i + 1);
    }

    setLoading(false);
    if (failed === 0) {
      toast.success(`${success} wallpaper(s) uploaded successfully`);
    } else {
      toast.error(`${success} succeeded, ${failed} failed`);
    }
    setFiles([]);
    navigate('/');
  };

  if (!isAuthenticated) return null;

  return (
    <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <h1 className="text-2xl font-bold text-gray-900 mb-8">Upload Wallpapers</h1>

      <div
        {...getRootProps()}
        className={`border-2 border-dashed rounded-2xl p-8 text-center cursor-pointer transition-colors duration-200 ${
          isDragActive
            ? 'border-indigo-400 bg-indigo-50'
            : 'border-gray-300 bg-gray-50 hover:border-indigo-400 hover:bg-indigo-50'
        }`}
      >
        <input {...getInputProps()} />
        <div className="space-y-3">
          <AiOutlineCloudUpload className="mx-auto text-gray-400" size={48} />
          <p className="text-sm text-gray-600">
            Drag & drop images here, or click to select
          </p>
          <p className="text-xs text-gray-400">
            Max 20MB per file &middot; Up to {MAX_FILES} images at a time
          </p>
        </div>
      </div>

      {files.length > 0 && (
        <>
          <div className="mt-6 grid grid-cols-2 sm:grid-cols-4 md:grid-cols-5 gap-4">
            {files.map((f, idx) => (
              <div key={idx} className="relative group aspect-square">
                <img
                  src={f.preview}
                  alt=""
                  className="w-full h-full object-cover rounded-lg"
                />
                <button
                  onClick={() => removeFile(idx)}
                  className="absolute top-1.5 right-1.5 w-6 h-6 flex items-center justify-center bg-black/50 text-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <AiOutlineClose size={14} />
                </button>
              </div>
            ))}
          </div>

          <div className="mt-6 flex items-center justify-between">
            <span className="text-sm text-gray-500">
              {files.length} / {MAX_FILES} images selected
            </span>
            <button
              onClick={handleUpload}
              disabled={loading}
              className="px-6 py-3 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors duration-200 disabled:opacity-50"
            >
              {loading ? (
                <span className="flex items-center gap-2">
                  <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  Uploading {progress}/{files.length}...
                </span>
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
