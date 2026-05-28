import { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import InAppConfirm from '../components/InAppConfirm';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiOutlineDelete,
  AiOutlineEdit,
  AiOutlineClose,
  AiOutlineCheck,
  AiOutlineArrowLeft,
} from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { CollectionDetail as CollectionDetailType, Wallpaper, User } from '../types';
import {
  getCollection,
  getCollectionWallpapers,
  likeCollection,
  unlikeCollection,
  deleteCollection,
  updateCollection,
  getUserProfile,
} from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperCard from '../components/WallpaperCard';
import Pagination from '../components/Pagination';
import EmptyState from '../components/EmptyState';
import { CollectionDetailSkeleton, WallpaperGridSkeleton } from '../components/Skeletons';

const PAGE_SIZE = 12;

function relativeTime(iso: string): string {
  const dt = new Date(iso).getTime();
  if (!dt) return '';
  const diff = (Date.now() - dt) / 1000;
  if (diff < 60) return 'JUST NOW';
  if (diff < 3600) return `${Math.floor(diff / 60)} MIN AGO`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} HR AGO`;
  const days = Math.floor(diff / 86400);
  if (days < 30) return `${days} ${days === 1 ? 'DAY' : 'DAYS'} AGO`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} ${months === 1 ? 'MONTH' : 'MONTHS'} AGO`;
  const years = Math.floor(months / 12);
  return `${years} ${years === 1 ? 'YEAR' : 'YEARS'} AGO`;
}

export default function CollectionDetailPage() {
  const { slug: id } = useParams<{ slug: string }>();
  const navigate = useNavigate();
  const { user } = useAuthStore();

  const [collection, setCollection] = useState<CollectionDetailType | null>(null);
  const [curator, setCurator] = useState<User | null>(null);
  const [pages, setPages] = useState<Record<number, Wallpaper[]>>({});
  const [cursors, setCursors] = useState<Record<number, number | undefined>>({ 1: undefined });
  const [hasMoreUpTo, setHasMoreUpTo] = useState<number | null>(null);
  const [knownTotalPages, setKnownTotalPages] = useState<number | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [loading, setLoading] = useState(true);
  const [loadingPage, setLoadingPage] = useState(false);
  const [liking, setLiking] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    getCollection(id)
      .then(async (res) => {
        const c = res.data.data;
        setCollection(c);
        // Curator info isn't embedded in the collection response; fetch
        // separately so the hero can show the @handle. Non-fatal if it
        // fails — caption just falls back to "@user-{id}".
        try {
          const u = await getUserProfile(String(c.user_id));
          setCurator(u.data.data);
        } catch { /* curator info optional */ }
      })
      .catch(() => toast.error('Failed to load collection'))
      .finally(() => setLoading(false));
  }, [id]);

  // Reset page cache whenever the collection itself changes (different slug).
  useEffect(() => {
    setPages({});
    setCursors({ 1: undefined });
    setHasMoreUpTo(null);
    setKnownTotalPages(null);
    setCurrentPage(1);
  }, [collection?.id]);

  const fetchPage = useCallback(async (page: number) => {
    if (!collection || pages[page]) return;
    const cursor = cursors[page];
    if (page > 1 && cursor === undefined) return;
    setLoadingPage(true);
    try {
      const res = await getCollectionWallpapers(collection.slug, { cursor, limit: PAGE_SIZE });
      const { items, next_cursor, has_more } = res.data.data;
      setPages((prev) => ({ ...prev, [page]: items }));
      if (has_more && next_cursor) {
        setCursors((prev) => ({ ...prev, [page + 1]: next_cursor }));
        setHasMoreUpTo(page);
      } else {
        setKnownTotalPages(page);
      }
    } catch {
      toast.error('Failed to load wallpapers');
    } finally {
      setLoadingPage(false);
    }
  }, [collection, pages, cursors]);

  useEffect(() => { fetchPage(currentPage); }, [currentPage, fetchPage]);

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

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const handleDelete = () => {
    if (!collection) return;
    setShowDeleteConfirm(true);
  };
  const doDelete = async () => {
    if (!collection) return;
    setShowDeleteConfirm(false);
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
    return (
      <div className="bg-paper text-ink min-h-full">
        <CollectionDetailSkeleton />
      </div>
    );
  }
  if (!collection) return <EmptyState message="Collection not found." />;

  const isOwner = user?.id === collection.user_id;
  const visible = pages[currentPage] || [];
  const total = knownTotalPages ?? (hasMoreUpTo ? hasMoreUpTo + 1 : 1);
  const cover = visible[0]?.preview_url || visible[0]?.thumb_url || collection.cover_url;
  const curatorInitial = (curator?.nickname || curator?.username || 'U').charAt(0).toUpperCase();

  return (
    <div className="bg-paper text-ink min-h-full">
      <PageMeta
        title={collection.title}
        description={collection.description || `Collection of ${collection.wallpaper_count} wallpapers`}
        image={cover}
      />
      <InAppConfirm
        open={showDeleteConfirm}
        title="Delete this collection?"
        message="This removes the collection. Wallpapers inside the collection are not deleted."
        confirmLabel="Delete"
        destructive
        onConfirm={doDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      {/* Back link */}
      <div className="px-6 sm:px-10 pt-5">
        <Link
          to="/collections"
          className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full border border-hair text-ink text-[13px] no-underline hover:bg-paper-2 transition-colors"
        >
          <AiOutlineArrowLeft size={13} /> All collections
        </Link>
      </div>

      {/* Hero spread — px-6/sm:px-10 mirrors the wallpaper grid below
          so the cover image + meta column don't bleed flush to the
          viewport edges while everything underneath is inset. */}
      <div className="grid grid-cols-1 lg:grid-cols-2 mt-5 border-b border-hair bg-paper px-6 sm:px-10">
        <div className="relative aspect-[3/2] overflow-hidden bg-paper-3">
          {cover ? (
            <img src={cover} alt={collection.title} className="absolute inset-0 w-full h-full object-cover" />
          ) : (
            <div className="absolute inset-0 flex items-center justify-center text-muted text-sm">No cover yet</div>
          )}
          {/* Inset corner brackets — always visible on this editorial cover. */}
          <span className="plate-brackets">
            <span className="br-tl" style={{ top: 16, left: 16, borderColor: '#fff', opacity: 0.7 }} />
            <span className="br-tr" style={{ top: 16, right: 16, borderColor: '#fff', opacity: 0.7 }} />
            <span className="br-bl" style={{ bottom: 16, left: 16, borderColor: '#fff', opacity: 0.7 }} />
            <span className="br-br" style={{ bottom: 16, right: 16, borderColor: '#fff', opacity: 0.7 }} />
          </span>
        </div>

        {/* Right column: vertical padding only — horizontal breathing
            comes from the outer container. lg:pl-10 puts a gap between
            the cover and the meta text on desktop. */}
        <div className="py-8 lg:py-10 lg:pl-10 flex flex-col justify-between min-h-[280px] lg:min-h-[420px]">
          <div>
            <div className="kicker text-muted">
              Collection №{String(collection.id).padStart(3, '0')} · {collection.wallpaper_count}{' '}
              {collection.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
              {!collection.is_public && ' · PRIVATE'}
            </div>

            {editing ? (
              <div className="mt-3 space-y-3 max-w-[480px]">
                <input
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  maxLength={100}
                  className="w-full px-4 py-3 display text-[28px] leading-tight border border-hair bg-paper text-ink focus:outline-none focus:border-ink"
                />
                <textarea
                  value={editDesc}
                  onChange={(e) => setEditDesc(e.target.value)}
                  rows={3}
                  maxLength={500}
                  placeholder="Optional description"
                  className="w-full px-4 py-3 italic-d text-[16px] border border-hair bg-paper text-ink-2 focus:outline-none focus:border-ink resize-none"
                />
                <div className="flex gap-2">
                  <button
                    onClick={handleSave}
                    disabled={saving || !editTitle.trim()}
                    className="px-4 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50"
                  >
                    <AiOutlineCheck className="inline mr-1" /> {saving ? 'Saving…' : 'Save'}
                  </button>
                  <button
                    onClick={() => setEditing(false)}
                    className="px-4 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2"
                  >
                    <AiOutlineClose className="inline mr-1" /> Cancel
                  </button>
                </div>
              </div>
            ) : (
              <>
                <h1 className="display text-[44px] sm:text-[64px] lg:text-[76px] leading-[0.92] mt-3 tracking-[-0.02em] text-ink">
                  {collection.title}
                </h1>
                {collection.description && (
                  <p className="display italic-d text-[17px] sm:text-[19px] leading-[1.45] text-ink-2 mt-5 max-w-[520px]">
                    “{collection.description}”
                  </p>
                )}
              </>
            )}
          </div>

          {/* Curator row */}
          <div className="flex items-center gap-3 mt-7 flex-wrap">
            <div className="w-9 h-9 rounded-full overflow-hidden border border-hair bg-paper-2 flex items-center justify-center display text-[16px] flex-shrink-0">
              {curator?.avatar_url
                ? <img src={curator.avatar_url} alt="" className="w-full h-full object-cover" />
                : curatorInitial}
            </div>
            <div className="min-w-0 flex-1">
              <Link
                to={curator ? `/user/${curator.username}` : '#'}
                className="display text-[17px] leading-tight no-underline text-ink hover:underline"
              >
                @{curator?.username || `user-${collection.user_id}`}
              </Link>
              <div className="mono text-[10px] tracking-[0.06em] uppercase text-muted mt-0.5">
                Updated {relativeTime(collection.updated_at).toLowerCase()} · {collection.like_count} likes
              </div>
            </div>

            <div className="flex items-center gap-2 ml-auto">
              <button
                onClick={handleLike}
                disabled={liking}
                className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-paper border border-hair text-ink text-[12px] font-medium hover:bg-paper-2 disabled:opacity-60 transition-colors"
              >
                {collection.is_liked ? <AiFillHeart size={13} className="text-rose-600" /> : <AiOutlineHeart size={13} />}
                {collection.like_count}
              </button>
              {isOwner && (
                <>
                  <button
                    onClick={startEdit}
                    className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-paper border border-hair text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors"
                    title="Edit"
                  >
                    <AiOutlineEdit size={13} /> Edit
                  </button>
                  <button
                    onClick={handleDelete}
                    className="inline-flex items-center justify-center w-8 h-8 rounded-full border border-hair text-rose-600 hover:bg-rose-50 transition-colors"
                    title="Delete collection"
                  >
                    <AiOutlineDelete size={14} />
                  </button>
                </>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Grid */}
      <div className="bg-paper-2 px-6 sm:px-10 py-7">
        <div className="label-rule mb-4">
          Wallpapers · {visible.length} of {collection.wallpaper_count}
        </div>

        {loadingPage && visible.length === 0 ? (
          <WallpaperGridSkeleton count={8} cols="4" />
        ) : visible.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">No wallpapers in this collection yet.</div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
            {visible.map((w) => (
              <WallpaperCard key={w.id} wallpaper={w} fixedAspect hideActions />
            ))}
          </div>
        )}

        <Pagination current={currentPage} total={total} onChange={setCurrentPage} />
      </div>
    </div>
  );
}
