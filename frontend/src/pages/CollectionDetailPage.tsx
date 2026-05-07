import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';
import { AiFillHeart, AiOutlineHeart, AiOutlineDelete, AiOutlineEdit, AiOutlineClose, AiOutlineCheck } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { CollectionDetail as CollectionDetailType, Wallpaper } from '../types';
import { getCollection, getCollectionWallpapers, likeCollection, unlikeCollection, deleteCollection, updateCollection } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

export default function CollectionDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuthStore();

  const [collection, setCollection] = useState<CollectionDetailType | null>(null);
  usePageTitle(collection ? collection.title : 'Collection');
  const [wallpapers, setWallpapers] = useState<Wallpaper[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [liking, setLiking] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!id) return;
    const collectionId = Number(id);
    setLoading(true);

    Promise.all([
      getCollection(collectionId),
      getCollectionWallpapers(collectionId, { limit: 20 }),
    ])
      .then(([colRes, wpRes]) => {
        setCollection(colRes.data.data);
        const { items, next_cursor, has_more } = wpRes.data.data;
        setWallpapers(items);
        setCursor(next_cursor);
        setHasMore(has_more);
      })
      .catch(() => toast.error('Failed to load collection'))
      .finally(() => setLoading(false));
  }, [id]);

  const loadMore = useCallback(async () => {
    if (loadingMore || !id) return;
    setLoadingMore(true);
    try {
      const res = await getCollectionWallpapers(Number(id), { cursor, limit: 20 });
      const { items, next_cursor, has_more } = res.data.data;
      setWallpapers((prev) => [...prev, ...items]);
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load more');
    } finally {
      setLoadingMore(false);
    }
  }, [id, cursor, loadingMore]);

  const handleLike = async () => {
    if (!collection || liking) return;
    setLiking(true);
    try {
      if (collection.is_liked) {
        await unlikeCollection(collection.id);
        setCollection({ ...collection, is_liked: false, like_count: collection.like_count - 1 });
      } else {
        await likeCollection(collection.id);
        setCollection({ ...collection, is_liked: true, like_count: collection.like_count + 1 });
      }
    } catch {
      toast.error('Failed to update like');
    } finally {
      setLiking(false);
    }
  };

  const handleDelete = async () => {
    if (!collection || !window.confirm('Are you sure you want to delete this collection?')) return;
    try {
      await deleteCollection(collection.id);
      toast.success('Collection deleted');
      navigate('/collections');
    } catch {
      toast.error('Failed to delete collection');
    }
  };

  const startEdit = () => {
    if (!collection) return;
    setEditTitle(collection.title);
    setEditDesc(collection.description);
    setEditing(true);
  };

  const handleSave = async () => {
    if (!collection || saving) return;
    if (!editTitle.trim()) { toast.error('Title is required'); return; }
    setSaving(true);
    try {
      await updateCollection(collection.id, { title: editTitle.trim(), description: editDesc.trim(), is_public: collection.is_public });
      setCollection({ ...collection, title: editTitle.trim(), description: editDesc.trim() });
      setEditing(false);
      toast.success('Collection updated');
    } catch {
      toast.error('Failed to update');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <Spinner />;
  }

  if (!collection) {
    return <EmptyState message="Collection not found." />;
  }

  const isOwner = user?.id === collection.user_id;

  return (
    <div className="px-6 py-6">
      <div className="mb-8">
        <div className="flex items-start justify-between gap-4">
          <div className="flex-1 min-w-0">
            {editing ? (
              <div className="space-y-3">
                <input
                  type="text"
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  className="w-full text-2xl font-bold bg-transparent border-b-2 border-indigo-500 text-gray-900 dark:text-white outline-none pb-1"
                  autoFocus
                />
                <textarea
                  value={editDesc}
                  onChange={(e) => setEditDesc(e.target.value)}
                  rows={2}
                  placeholder="Description (optional)"
                  className="w-full text-sm bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 rounded-lg px-3 py-2 text-gray-700 dark:text-gray-300 outline-none focus:ring-2 focus:ring-indigo-500 resize-none"
                />
                <div className="flex gap-2">
                  <button
                    onClick={handleSave}
                    disabled={saving}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-lg transition-colors disabled:opacity-50"
                  >
                    <AiOutlineCheck size={16} />
                    Save
                  </button>
                  <button
                    onClick={() => setEditing(false)}
                    className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-gray-600 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 hover:bg-gray-200 dark:hover:bg-gray-600 rounded-lg transition-colors"
                  >
                    <AiOutlineClose size={16} />
                    Cancel
                  </button>
                </div>
              </div>
            ) : (
              <>
                <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">{collection.title}</h1>
                {collection.description && (
                  <p className="text-gray-500 dark:text-gray-400 mb-3">{collection.description}</p>
                )}
                <div className="flex items-center gap-4 text-sm text-gray-400">
                  <span>{collection.wallpaper_count} wallpapers</span>
                  <span>{collection.view_count} views</span>
                </div>
              </>
            )}
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              onClick={handleLike}
              disabled={liking}
              className={`flex items-center gap-1.5 px-4 py-2 text-sm font-medium rounded-lg border transition-colors duration-200 disabled:opacity-50 ${
                collection.is_liked
                  ? 'text-red-500 border-red-300'
                  : 'text-gray-500 border-gray-200 hover:border-gray-300'
              }`}
            >
              {collection.is_liked ? <AiFillHeart size={18} /> : <AiOutlineHeart size={18} />}
              {collection.like_count}
            </button>

            {isOwner && !editing && (
              <>
                <button
                  onClick={startEdit}
                  className="p-2 text-gray-400 hover:text-indigo-600 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                  title="Edit collection"
                >
                  <AiOutlineEdit size={20} />
                </button>
                <button
                  onClick={handleDelete}
                  className="p-2 text-gray-400 hover:text-red-500 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
                  title="Delete collection"
                >
                  <AiOutlineDelete size={20} />
                </button>
              </>
            )}
          </div>
        </div>
      </div>

      {wallpapers.length > 0 ? (
        <WallpaperGrid wallpapers={wallpapers} viewMode="justified" />
      ) : (
        <EmptyState message="This collection is empty." />
      )}

      {hasMore && (
        <div className="flex justify-center mt-8">
          <button
            onClick={loadMore}
            disabled={loadingMore}
            className="px-6 py-2.5 text-sm font-medium text-indigo-600 border border-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors duration-200 disabled:opacity-50"
          >
            {loadingMore ? (
              <span className="flex items-center gap-2">
                <div className="w-4 h-4 border-2 border-indigo-200 border-t-indigo-600 rounded-full animate-spin" />
                Loading...
              </span>
            ) : (
              'Load More'
            )}
          </button>
        </div>
      )}
    </div>
  );
}
