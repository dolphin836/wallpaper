import { useState, useEffect } from 'react';
import { AiOutlineClose, AiOutlinePlus, AiOutlineCheck } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { CollectionBrief } from '../types';
import { getMyCollections, createCollection, addToCollection } from '../api';

interface Props {
  wallpaperId: number;
  onClose: () => void;
}

export default function AddToCollectionModal({ wallpaperId, onClose }: Props) {
  const [collections, setCollections] = useState<CollectionBrief[]>([]);
  const [loading, setLoading] = useState(true);
  const [newTitle, setNewTitle] = useState('');
  const [creating, setCreating] = useState(false);
  const [addedIds, setAddedIds] = useState<Set<number>>(new Set());

  useEffect(() => {
    getMyCollections()
      .then((res) => setCollections(res.data.data || []))
      .catch(() => toast.error('Failed to load collections'))
      .finally(() => setLoading(false));
  }, []);

  const handleAdd = async (collectionId: number) => {
    if (addedIds.has(collectionId)) return;
    try {
      await addToCollection(collectionId, wallpaperId);
      setAddedIds((prev) => new Set(prev).add(collectionId));
      toast.success('Added to collection');
    } catch {
      toast.error('Failed to add');
    }
  };

  const handleCreate = async () => {
    if (!newTitle.trim() || creating) return;
    setCreating(true);
    try {
      const res = await createCollection({ title: newTitle.trim() });
      const newCol = res.data.data;
      await addToCollection(newCol.id, wallpaperId);
      setCollections((prev) => [{ id: newCol.id, title: newCol.title, wallpaper_count: 1 }, ...prev]);
      setAddedIds((prev) => new Set(prev).add(newCol.id));
      setNewTitle('');
      toast.success('Collection created & wallpaper added');
    } catch {
      toast.error('Failed to create collection');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={onClose}>
      <div className="bg-white dark:bg-gray-800 rounded-2xl shadow-xl w-full max-w-md mx-4 max-h-[80vh] flex flex-col" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between p-5 border-b border-gray-100 dark:border-gray-700">
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">Add to Collection</h3>
          <button onClick={onClose} className="p-1.5 text-gray-400 hover:text-gray-600 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700">
            <AiOutlineClose size={20} />
          </button>
        </div>

        <div className="p-4 border-b border-gray-100 dark:border-gray-700">
          <div className="flex gap-2">
            <input
              type="text"
              value={newTitle}
              onChange={(e) => setNewTitle(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && handleCreate()}
              placeholder="New collection name..."
              className="flex-1 px-3.5 py-2.5 text-sm border border-gray-200 dark:border-gray-600 rounded-xl bg-gray-50 dark:bg-gray-700 text-gray-900 dark:text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            />
            <button
              onClick={handleCreate}
              disabled={!newTitle.trim() || creating}
              className="px-4 py-2.5 text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 rounded-xl transition-colors disabled:opacity-50 shrink-0"
            >
              <AiOutlinePlus size={18} />
            </button>
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-2">
          {loading ? (
            <div className="flex justify-center py-8">
              <div className="w-6 h-6 border-2 border-indigo-200 border-t-indigo-600 rounded-full animate-spin" />
            </div>
          ) : collections.length === 0 ? (
            <div className="text-center py-8 text-sm text-gray-400">No collections yet. Create one above!</div>
          ) : (
            collections.map((c) => (
              <button
                key={c.id}
                onClick={() => handleAdd(c.id)}
                disabled={addedIds.has(c.id)}
                className="w-full flex items-center justify-between px-4 py-3 rounded-xl hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors text-left"
              >
                <div>
                  <div className="text-sm font-medium text-gray-900 dark:text-white">{c.title}</div>
                  <div className="text-xs text-gray-400">{c.wallpaper_count} wallpapers</div>
                </div>
                {addedIds.has(c.id) ? (
                  <AiOutlineCheck size={18} className="text-green-500 shrink-0" />
                ) : (
                  <AiOutlinePlus size={18} className="text-gray-300 shrink-0" />
                )}
              </button>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
