import { useState, useEffect, useCallback, useMemo } from 'react';
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
import WallpaperGrid from '../components/WallpaperGrid';
import Pagination from '../components/Pagination';
import EmptyState from '../components/EmptyState';

const PAGE_SIZE = 12;

function relativeTime(iso: string): string {
  const dt = new Date(iso).getTime();
  if (!dt) return '';
  const diff = (Date.now() - dt) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} hr ago`;
  const days = Math.floor(diff / 86400);
  if (days < 30) return `${days} ${days === 1 ? 'day' : 'days'} ago`;
  const months = Math.floor(days / 30);
  if (months < 12) return `${months} ${months === 1 ? 'month' : 'months'} ago`;
  const years = Math.floor(months / 12);
  return `${years} ${years === 1 ? 'year' : 'years'} ago`;
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
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    getCollection(id)
      .then(async (res) => {
        const c = res.data.data;
        setCollection(c);
        // Fetch the curator separately so the meta column can show
        // their handle + avatar. Optional — caption degrades to
        // "user-N" on failure.
        try {
          const u = await getUserProfile(String(c.user_id));
          setCurator(u.data.data);
        } catch { /* curator info optional */ }
      })
      .catch(() => toast.error('Failed to load collection'))
      .finally(() => setLoading(false));
  }, [id]);

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
      await updateCollection(collection.id, {
        title: editTitle.trim(),
        description: editDesc.trim(),
        is_public: collection.is_public,
      });
      setCollection({ ...collection, title: editTitle.trim(), description: editDesc.trim() });
      setEditing(false);
      toast.success('Collection updated');
    } catch {
      toast.error('Failed to update');
    } finally {
      setSaving(false);
    }
  };

  // Mesh CSS variable from the collection's accent_color. This is the
  // key differentiator: every collection's detail page literally takes
  // on its own colour (warm, cool, neon, muted — depends on the curator
  // or the editor's pick). Sets a CSS var on the page root that the
  // mesh and accents read.
  const accentStyle = useMemo<React.CSSProperties>(() => {
    if (!collection?.accent_color) return {};
    return { '--c-accent': collection.accent_color } as React.CSSProperties;
  }, [collection?.accent_color]);

  if (loading) {
    return (
      <div className="c-detail min-h-full">
        <div className="c-detail-mesh" aria-hidden />
        <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-10">
          <div className="c-detail-hero skeleton-card" style={{ aspectRatio: '5/3' }} />
        </main>
      </div>
    );
  }
  if (!collection) return <EmptyState message="Collection not found." />;

  const isOwner = user?.id === collection.user_id;
  const visible = pages[currentPage] || [];
  const total = knownTotalPages ?? (hasMoreUpTo ? hasMoreUpTo + 1 : 1);
  const cover = collection.cover_url || visible[0]?.preview_url || visible[0]?.thumb_url;
  const curatorInitial = (curator?.nickname || curator?.username || 'U').charAt(0).toUpperCase();

  return (
    <div className="c-detail min-h-full" style={accentStyle}>
      <div className="c-detail-mesh" aria-hidden />
      <PageMeta
        title={collection.title}
        description={collection.description || `Collection of ${collection.wallpaper_count} wallpapers`}
        image={cover}
      />
      <InAppConfirm
        open={showDeleteConfirm}
        title="Delete this collection?"
        message="This removes the collection. Wallpapers inside are not deleted."
        confirmLabel="Delete"
        destructive
        onConfirm={doDelete}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 py-8">
        <Link to="/collections" className="c-backlink">
          <AiOutlineArrowLeft size={11} />
          <span>All collections</span>
        </Link>

        {/* Hero — cover + minimal meta side-by-side. Cover sits on a
            soft accent-tinted halo (no stacked-paper layers; cleaner
            single-object presentation). Meta column has: kicker,
            title, count meta, actions. No italic description, no
            curator avatar/handle row — keeping the content side
            quiet so the cover is the focal point. */}
        <section className="c-detail-hero-row">
          <div className="c-detail-frame">
            {cover ? (
              <img src={cover} alt={collection.title} className="c-detail-cover" />
            ) : (
              <div className="c-detail-cover-empty">No cover yet</div>
            )}
            <span className="c-detail-accent-dot" aria-hidden />
          </div>

          <div className="c-detail-meta">
            <div className="c-detail-kicker">
              {collection.kind === 1 ? 'Editor Theme' : 'Collection'}
              {!collection.is_public && ' · Private'}
            </div>

            {editing ? (
              <div className="mt-4 space-y-3">
                <input
                  value={editTitle}
                  onChange={(e) => setEditTitle(e.target.value)}
                  maxLength={100}
                  className="w-full px-4 py-3 display text-[28px] leading-tight border border-hair bg-paper text-ink focus:outline-none focus:border-ink rounded-lg"
                />
                <textarea
                  value={editDesc}
                  onChange={(e) => setEditDesc(e.target.value)}
                  rows={3}
                  maxLength={500}
                  placeholder="Optional description"
                  className="w-full px-4 py-3 text-[15px] border border-hair bg-paper text-ink-2 focus:outline-none focus:border-ink resize-none rounded-lg"
                />
                <div className="flex gap-2">
                  <button
                    onClick={handleSave}
                    disabled={saving || !editTitle.trim()}
                    className="c-detail-btn-primary"
                  >
                    <AiOutlineCheck size={13} /> {saving ? 'Saving…' : 'Save'}
                  </button>
                  <button
                    onClick={() => setEditing(false)}
                    className="c-detail-btn-ghost"
                  >
                    <AiOutlineClose size={13} /> Cancel
                  </button>
                </div>
              </div>
            ) : (
              <>
                <h1 className="c-detail-title">{collection.title}</h1>
                {collection.description && (
                  <p className="c-detail-desc">{collection.description}</p>
                )}
              </>
            )}

            {/* Curator + meta row. Avatar + handle + 'by' line + the
                count/updated meta. All roman — no italic anywhere
                (display-italic-on-display-italic was the previous
                problem). The handle is set in the same display serif
                as the title, but at body weight, so it reads as a
                signature line rather than another headline. */}
            <div className="c-detail-byline">
              <Link
                to={curator ? `/user/${curator.username}` : '#'}
                className="c-detail-byline-link"
              >
                <span className="c-detail-byline-avatar">
                  {curator?.avatar_url
                    ? <img src={curator.avatar_url} alt="" />
                    : curatorInitial}
                </span>
                <span className="c-detail-byline-meta">
                  <span className="c-detail-byline-handle">
                    A set by @{curator?.username || `user-${collection.user_id}`}
                  </span>
                  <span className="c-detail-byline-sub">
                    {collection.wallpaper_count} {collection.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
                    {collection.updated_at ? ` · updated ${relativeTime(collection.updated_at)}` : ''}
                  </span>
                </span>
              </Link>
            </div>

            {!editing && (
              <div className="c-detail-actions">
                <button
                  onClick={handleLike}
                  disabled={liking}
                  className={`c-detail-like${collection.is_liked ? ' is-liked' : ''}`}
                >
                  {collection.is_liked ? <AiFillHeart size={14} /> : <AiOutlineHeart size={14} />}
                  <span>{collection.like_count}</span>
                </button>
                {isOwner && (
                  <>
                    <button onClick={startEdit} className="c-detail-btn-ghost">
                      <AiOutlineEdit size={13} /> Edit
                    </button>
                    <button
                      onClick={() => setShowDeleteConfirm(true)}
                      className="c-detail-btn-delete"
                      title="Delete collection"
                    >
                      <AiOutlineDelete size={14} />
                    </button>
                  </>
                )}
              </div>
            )}
          </div>
        </section>

        {/* Wallpaper matrix — uniform, symmetric. Unlike Weekly's
            non-symmetric 'hero + 3×3 with № markers', collections are
            presented as a clean even set: this is the *theme*, equally
            valid pieces of it. */}
        <section className="c-detail-grid-section">
          <div className="c-detail-grid-head">
            <span className="mono text-[10px] tracking-[0.22em] uppercase text-muted">
              The set
            </span>
            <span className="mono text-[10px] tracking-[0.18em] uppercase text-muted">
              {visible.length > 0 ? `${visible.length} of ${collection.wallpaper_count}` : `${collection.wallpaper_count} ${collection.wallpaper_count === 1 ? 'piece' : 'pieces'}`}
            </span>
          </div>

          {/* Salon-wall mosaic — 11-col CSS grid with mixed col/row
              spans gives an "art-gallery hang" rhythm. Distinct from
              Discover (uniform Grid or row-justified) and from Weekly
              (5-up 4:5 portrait tiles). Reads as a curated wall of
              pieces, not a catalog. */}
          {loadingPage && visible.length === 0 ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="tile-cell skeleton-card aspect-[3/2]" />
              ))}
            </div>
          ) : visible.length === 0 ? (
            <div className="text-center py-20 text-muted text-sm">No wallpapers in this collection yet.</div>
          ) : (
            <WallpaperGrid
              wallpapers={visible}
              viewMode="salon"
              sizeMode="md"
            />
          )}

          <Pagination current={currentPage} total={total} onChange={setCurrentPage} />
        </section>
      </main>
    </div>
  );
}
