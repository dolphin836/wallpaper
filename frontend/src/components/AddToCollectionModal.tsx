import { useState, useEffect, useRef } from 'react';
import { AiOutlineClose, AiOutlinePlus, AiOutlineCheck } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { CollectionBrief } from '../types';
import { getMyCollections, createCollection, addToCollection } from '../api';

interface Props {
  wallpaperId: number;
  onClose: () => void;
}

/**
 * Add-to-collection picker. Rendered as a centered paper card (modal-on-
 * scrim rather than the spec's button-anchored popover, because the detail
 * page itself is already a modal panel and anchoring inside would have to
 * juggle two stacked-overlay z-orders + breakout edges).
 *
 * Each row is a checkbox-style toggle in the editorial paper / ink
 * vocabulary: 14×14 square that fills accent-orange + white check when
 * the wallpaper sits in that list. The bottom "+ New list" affordance
 * expands inline into a dashed-border text input on click.
 */
export default function AddToCollectionModal({ wallpaperId, onClose }: Props) {
  const [collections, setCollections] = useState<CollectionBrief[]>([]);
  const [loading, setLoading] = useState(true);
  const [newTitle, setNewTitle] = useState('');
  const [creating, setCreating] = useState(false);
  const [composing, setComposing] = useState(false);
  const [addedIds, setAddedIds] = useState<Set<number>>(new Set());
  const newInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    getMyCollections()
      .then((res) => setCollections(res.data.data || []))
      .catch(() => toast.error('Failed to load collections'))
      .finally(() => setLoading(false));
  }, []);

  // Focus the input as soon as the composer expands so the user can start
  // typing without an extra click.
  useEffect(() => {
    if (composing) newInputRef.current?.focus();
  }, [composing]);

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
    const title = newTitle.trim();
    if (!title || creating) return;
    setCreating(true);
    try {
      const res = await createCollection({ title });
      const newCol = res.data.data;
      await addToCollection(newCol.id, wallpaperId);
      setCollections((prev) => [{ id: newCol.id, title: newCol.title, wallpaper_count: 1 }, ...prev]);
      setAddedIds((prev) => new Set(prev).add(newCol.id));
      setNewTitle('');
      setComposing(false);
      toast.success('Collection created');
    } catch {
      toast.error('Failed to create collection');
    } finally {
      setCreating(false);
    }
  };

  return (
    <div
      onClick={onClose}
      className="fixed inset-0 z-[60] flex items-start justify-center pt-[20vh] px-4"
      style={{ background: 'rgba(15,12,8,0.55)' }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-paper border border-ink w-full max-w-[320px] max-h-[60vh] flex flex-col"
        style={{ boxShadow: '0 16px 40px rgba(0,0,0,0.18)' }}
      >
        {/* Header — kicker label + 22px round close X */}
        <div className="flex items-center justify-between px-3.5 pt-3.5">
          <span className="kicker text-muted">Add to a list</span>
          <button
            onClick={onClose}
            className="w-[22px] h-[22px] rounded-full border border-hair text-ink-2 hover:bg-paper-2 inline-flex items-center justify-center transition-colors"
            aria-label="Close"
          >
            <AiOutlineClose size={11} />
          </button>
        </div>

        {/* List */}
        <ul className="list-none m-0 p-0 mt-2.5 mx-3.5 border-t border-hair overflow-y-auto flex-1">
          {loading ? (
            <li className="py-6 flex justify-center">
              <div className="w-5 h-5 border-2 border-hair border-t-ink rounded-full animate-spin" />
            </li>
          ) : collections.length === 0 ? (
            <li className="py-6 text-center text-[12px] text-muted">No lists yet. Create one below.</li>
          ) : (
            collections.map((c) => {
              const checked = addedIds.has(c.id);
              return (
                <li key={c.id} className="border-b border-hair last:border-b-0">
                  <button
                    onClick={() => handleAdd(c.id)}
                    disabled={checked}
                    className="w-full flex items-center gap-2.5 py-2.5 text-left disabled:cursor-default"
                  >
                    {/* 14×14 square checkbox — accent fill + white check
                        when the wallpaper has been added to this list. */}
                    <span
                      className="w-[14px] h-[14px] rounded-[3px] inline-flex items-center justify-center flex-shrink-0 transition-colors"
                      style={{
                        background: checked ? 'var(--color-accent)' : 'transparent',
                        border: `1.5px solid ${checked ? 'var(--color-accent)' : 'var(--color-hair)'}`,
                      }}
                    >
                      {checked && <AiOutlineCheck size={9} strokeWidth={3} className="text-white" />}
                    </span>
                    <span className="flex-1 text-[13px] text-ink truncate">{c.title}</span>
                    <span className="mono text-[10px] tracking-[0.06em] text-muted">{c.wallpaper_count}</span>
                  </button>
                </li>
              );
            })
          )}
        </ul>

        {/* Composer — dashed-border button that expands to an inline input. */}
        <div className="px-3.5 pb-3.5 pt-2.5">
          {composing ? (
            <div className="flex items-center gap-2">
              <input
                ref={newInputRef}
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') handleCreate();
                  if (e.key === 'Escape') { setComposing(false); setNewTitle(''); }
                }}
                placeholder="New list name"
                maxLength={100}
                className="flex-1 px-3 py-2 text-[13px] border border-dashed border-hair bg-paper text-ink placeholder:text-muted focus:outline-none focus:border-ink"
              />
              <button
                onClick={handleCreate}
                disabled={!newTitle.trim() || creating}
                className="px-3 py-2 bg-ink text-paper text-[12px] font-medium rounded-full disabled:opacity-50 transition-colors"
              >
                {creating ? '…' : 'Add'}
              </button>
            </div>
          ) : (
            <button
              onClick={() => setComposing(true)}
              className="w-full py-2 px-3 border border-dashed border-hair bg-transparent text-ink-2 text-[12px] font-medium inline-flex items-center justify-center gap-1.5 hover:border-ink-2 hover:text-ink transition-colors"
            >
              <AiOutlinePlus size={13} /> New list
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
