import { useState, useEffect, useRef, useMemo } from 'react';
import { useTranslation } from 'react-i18next';
import { AiOutlineClose, AiOutlinePlus, AiOutlineCheck, AiOutlineSearch } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { CollectionBrief } from '../types';
import { getMyCollections, createCollection, addToCollection } from '../api';

interface Props {
  wallpaperId: number;
  onClose: () => void;
}

const DEFAULT_LIMIT = 8;
const SEARCH_LIMIT = 50;

/**
 * Add-to-collection picker. Rendered as a centered paper card.
 *
 * Three rules drive the UX:
 *   - Only the user's own collections (kind=0 on the backend) — weekly
 *     theme collections are filtered out.
 *   - Default view is the 8 most-recent user collections; anything older
 *     surfaces through the title search box.
 *   - Collections that already hold this wallpaper come back with
 *     `contains_wallpaper = true` from the API and are rendered with a
 *     "Already added" tag + a disabled checkbox so the user can't add
 *     the same wallpaper twice.
 */
export default function AddToCollectionModal({ wallpaperId, onClose }: Props) {
  const { t } = useTranslation('collections');
  const [collections, setCollections] = useState<CollectionBrief[]>([]);
  const [loading, setLoading] = useState(true);
  const [newTitle, setNewTitle] = useState('');
  const [creating, setCreating] = useState(false);
  const [composing, setComposing] = useState(false);
  // Track collections the user added in this session — separate from
  // server-side contains_wallpaper so we can flip the row to "Added"
  // without re-fetching.
  const [addedIds, setAddedIds] = useState<Set<number>>(new Set());
  const [search, setSearch] = useState('');
  const newInputRef = useRef<HTMLInputElement>(null);
  const searchInputRef = useRef<HTMLInputElement>(null);

  // Debounce the search query so we don't fire one request per
  // keystroke. 250ms feels responsive without being chatty.
  const debouncedSearch = useDebounced(search, 250);

  useEffect(() => {
    const trimmed = debouncedSearch.trim();
    setLoading(true);
    getMyCollections({
      wallpaper_id: wallpaperId,
      q: trimmed || undefined,
      // When searching, widen the window so a match a few pages back
      // still surfaces; default view sticks to the latest 8.
      limit: trimmed ? SEARCH_LIMIT : DEFAULT_LIMIT,
    })
      .then((res) => setCollections(res.data.data || []))
      .catch(() => toast.error(t('modal.toastLoadFailed')))
      .finally(() => setLoading(false));
  }, [wallpaperId, debouncedSearch, t]);

  useEffect(() => {
    if (composing) newInputRef.current?.focus();
  }, [composing]);

  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || creating) return;
      if (composing) {
        setComposing(false);
        setNewTitle('');
        return;
      }
      onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [composing, creating, onClose]);

  const handleAdd = async (collectionId: number, alreadyContains: boolean) => {
    // Server-side contains + same-session adds both block re-adding.
    if (alreadyContains || addedIds.has(collectionId)) return;
    try {
      await addToCollection(collectionId, wallpaperId);
      setAddedIds((prev) => new Set(prev).add(collectionId));
      toast.success(t('modal.toastAdded'));
    } catch {
      toast.error(t('modal.toastAddFailed'));
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
      toast.success(t('create.success'));
    } catch {
      toast.error(t('create.error'));
    } finally {
      setCreating(false);
    }
  };

  const isSearching = search.trim().length > 0;
  const headerCount = useMemo(() => {
    if (loading) return '';
    if (isSearching) {
      return ` · ${collections.length === 1 ? t('modal.matchOne') : t('modal.matches', { num: collections.length })}`;
    }
    return collections.length > 0 ? ` · ${t('modal.latest', { num: collections.length })}` : '';
  }, [loading, isSearching, collections.length, t]);

  return (
    <div
      onClick={() => { if (!creating) onClose(); }}
      className="fixed inset-0 z-[60] flex items-start justify-center pt-[15vh] px-4"
      style={{ background: 'rgba(15,12,8,0.55)' }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="bg-paper border border-hair w-full max-w-[360px] max-h-[70vh] flex flex-col rounded-2xl"
        style={{ boxShadow: '0 24px 48px rgba(0,0,0,0.22)' }}
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-to-collection-title"
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 pt-4 pb-3">
          <div className="min-w-0">
            <h2 id="add-to-collection-title" className="kicker text-muted">{t('modal.title')}{headerCount}</h2>
          </div>
          <button
            onClick={onClose}
            disabled={creating}
            className="w-7 h-7 rounded-full border border-hair text-ink-2 hover:bg-paper-2 inline-flex items-center justify-center transition-colors flex-shrink-0 disabled:opacity-50"
            aria-label={t('modal.close')}
          >
            <AiOutlineClose size={12} />
          </button>
        </div>

        {/* Search */}
        <div className="px-4 pb-3">
          <div className="relative">
            <AiOutlineSearch size={14} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted pointer-events-none" />
            <input
              ref={searchInputRef}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder={t('modal.searchPlaceholder')}
              aria-label={t('modal.searchAria')}
              className="w-full pl-9 pr-8 py-2 text-[13px] border border-hair rounded-full bg-paper-2 text-ink placeholder:text-muted focus:outline-none focus:border-ink-2 focus:bg-paper transition-colors"
            />
            {search && (
              <button
                onClick={() => setSearch('')}
                className="absolute right-2 top-1/2 -translate-y-1/2 w-5 h-5 rounded-full text-muted hover:text-ink hover:bg-paper inline-flex items-center justify-center"
                aria-label={t('modal.clearSearch')}
              >
                <AiOutlineClose size={10} />
              </button>
            )}
          </div>
        </div>

        {/* List */}
        <ul className="list-none m-0 p-0 mx-4 border-t border-hair overflow-y-auto flex-1">
          {loading ? (
            <li className="py-6 flex justify-center">
              <div className="w-5 h-5 border-2 border-hair border-t-ink rounded-full animate-spin" role="status" aria-label={t('modal.loadingLists')} />
            </li>
          ) : collections.length === 0 ? (
            <li className="py-6 text-center text-[12px] text-muted" aria-live="polite">
              {isSearching ? t('modal.noMatch', { query: search }) : t('modal.emptyHint')}
            </li>
          ) : (
            collections.map((c) => {
              const sessionAdded = addedIds.has(c.id);
              const serverHas = c.contains_wallpaper === true;
              const inList = sessionAdded || serverHas;
              const disabled = inList;
              return (
                <li key={c.id} className="border-b border-hair last:border-b-0">
                  <button
                    onClick={() => handleAdd(c.id, serverHas)}
                    disabled={disabled}
                    title={inList ? t('modal.alreadyInTitle') : t('modal.addToTitle')}
                    className={`w-full flex items-center gap-2.5 py-2.5 text-left transition-opacity ${disabled ? 'cursor-default opacity-70' : 'hover:opacity-100'}`}
                  >
                    <span
                      className="w-[15px] h-[15px] rounded-[4px] inline-flex items-center justify-center flex-shrink-0 transition-colors"
                      style={{
                        background: inList ? 'var(--color-accent)' : 'transparent',
                        border: `1.5px solid ${inList ? 'var(--color-accent)' : 'var(--color-hair)'}`,
                      }}
                    >
                      {inList && <AiOutlineCheck size={10} strokeWidth={3} className="text-white" />}
                    </span>
                    <span className={`flex-1 text-[13px] truncate ${inList ? 'text-muted' : 'text-ink'}`}>
                      {c.title}
                    </span>
                    {inList ? (
                      <span className="mono text-[9px] tracking-[0.14em] uppercase text-accent flex-shrink-0">
                        {serverHas && !sessionAdded ? t('modal.alreadyIn') : t('modal.added')}
                      </span>
                    ) : (
                      <span className="mono text-[10px] tracking-[0.06em] text-muted flex-shrink-0">{c.wallpaper_count}</span>
                    )}
                  </button>
                </li>
              );
            })
          )}
        </ul>

        {/* Composer */}
        <div className="px-4 pb-4 pt-3">
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
                placeholder={t('modal.newListPlaceholder')}
                aria-label={t('modal.newListPlaceholder')}
                maxLength={100}
                className="flex-1 px-3 py-2 text-[13px] border border-dashed border-hair rounded-full bg-paper text-ink placeholder:text-muted focus:outline-none focus:border-ink"
              />
              <button
                onClick={handleCreate}
                disabled={!newTitle.trim() || creating}
                className="px-4 py-2 bg-ink text-paper text-[12px] font-medium rounded-full disabled:opacity-50 transition-colors"
              >
                {creating ? '…' : t('modal.add')}
              </button>
            </div>
          ) : (
            <button
              onClick={() => setComposing(true)}
              className="w-full py-2 px-3 border border-dashed border-hair rounded-full bg-transparent text-ink-2 text-[12px] font-medium inline-flex items-center justify-center gap-1.5 hover:border-ink-2 hover:text-ink transition-colors"
            >
              <AiOutlinePlus size={13} /> {t('modal.newList')}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

/** Small debounce helper, scoped to this file so we don't pull in a util library. */
function useDebounced<T>(value: T, ms: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return debounced;
}
