import { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { useParams, useNavigate, useLocation, Link } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import InAppConfirm from '../components/InAppConfirm';
import {
  AiFillHeart,
  AiOutlineHeart,
  AiFillStar,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
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
import { useWallpaperActions } from '../hooks/useWallpaperActions';
import Pagination from '../components/Pagination';
import EmptyState from '../components/EmptyState';
import ErrorState from '../components/ErrorState';

const PAGE_SIZE = 12;

/* Framed-print tile — paper mat + image + chips + hover action
   rail. Modal navigation via location.state.background so clicking
   opens the detail overlay (same UX as discover salon tiles).
   onHover lets the parent drive the page mesh from this
   wallpaper's palette while hovered. */
function FramedTile({
  wallpaper: w, index, onHover,
}: {
  wallpaper: Wallpaper;
  index: number;
  onHover?: (palette: string | undefined, dominant?: string) => void;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const [loaded, setLoaded] = useState(false);
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };
  const isVideo = (w.file_type || '').startsWith('video/');
  const resLabel = (() => {
    const px = Math.max(w.width || 0, w.height || 0);
    if (px >= 7680) return '8K';
    if (px >= 3840) return '4K';
    if (px >= 2560) return '2K';
    if (px >= 1920) return '1080P';
    if (px >= 1280) return '720P';
    return '';
  })();
  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      className="cd-frame"
      style={{ animationDelay: `${index * 35}ms` }}
      onMouseEnter={() => onHover?.(w.color_palette, w.dominant_color)}
      onMouseLeave={() => onHover?.(undefined)}
    >
      <div className="cd-mat">
        <img
          src={w.preview_url || w.thumb_url}
          alt={w.title || `Wallpaper ${w.id}`}
          loading="lazy"
          className={`cd-frame-img${loaded ? ' is-loaded' : ''}`}
          onLoad={() => setLoaded(true)}
          onError={() => setLoaded(true)}
          style={{ backgroundColor: w.dominant_color || undefined }}
        />
        {/* Top-left chip stack — same vocabulary as the discover
            salon variant. Resolution + Video + Mac (dynamic) + AI
            chips; .is-ai keeps the violet wash so synthetic
            content reads at a glance. */}
        <div className="cd-frame-chips">
          {resLabel && <span className="tile-chip">{resLabel}</span>}
          {isVideo && (
            <span className="tile-chip">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z"/></svg>
              Video
            </span>
          )}
          {w.is_dynamic && (
            <span className="tile-chip">
              <svg viewBox="0 0 384 512" fill="currentColor" aria-hidden><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
              Mac
            </span>
          )}
          {w.is_ai_generated && (
            <span className="tile-chip is-ai">
              <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z"/></svg>
              AI
            </span>
          )}
        </div>
        <div className="tile-actions">
          <button
            type="button"
            onClick={(e) => stop(e, acts.handleFavorite)}
            disabled={acts.favLoading}
            className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
            title={acts.favorited ? 'Unfavorite' : 'Favorite'}
          >
            {acts.favLoading
              ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
              : acts.favorited
                ? <AiFillStar size={15} />
                : <AiOutlineStar size={15} />}
          </button>
          <button
            type="button"
            onClick={(e) => stop(e, acts.handleLike)}
            disabled={acts.likeLoading}
            className={`t-act ${acts.liked ? 'is-liked' : ''}`}
            title={acts.liked ? 'Unlike' : 'Like'}
          >
            {acts.likeLoading
              ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
              : acts.liked
                ? <AiFillHeart size={15} />
                : <AiOutlineHeart size={15} />}
          </button>
          {acts.canDownload && (
            <button
              type="button"
              onClick={(e) => stop(e, acts.handleDownload)}
              disabled={acts.downloading}
              className={`t-act ${acts.downloaded ? 'is-downloaded' : ''}`}
              title={acts.downloaded ? 'Downloaded' : 'Download (1 coin)'}
            >
              {acts.downloading
                ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                : acts.downloaded
                  ? <AiOutlineCheckCircle size={15} />
                  : <AiOutlineDownload size={15} />}
            </button>
          )}
        </div>
      </div>
    </Link>
  );
}

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
  const [error, setError] = useState(false);
  const [liking, setLiking] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editTitle, setEditTitle] = useState('');
  const [editDesc, setEditDesc] = useState('');
  const [saving, setSaving] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setError(false);
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
      .catch((e) => {
        // 404 stays an explicit 'not found' (handled below via the
        // collection null path with EmptyState). Anything else is a
        // server/network failure — surface the shared retry UI.
        if (e?.response?.status !== 404) setError(true);
      })
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
    setLoadingPage(true);
    // Walk forward from the highest-cached cursor to the
    // requested page, recording cursors as we go. Prevents the
    // "click last page → nothing happens" failure mode when
    // cursors[page] was undefined.
    const localCursors: Record<number, number | undefined> = { ...cursors };
    const accumPages: Record<number, Wallpaper[]> = {};
    let startPage = 1;
    while (startPage <= page && localCursors[startPage] === undefined && startPage > 1) startPage++;
    let nextCursor: number | undefined = localCursors[startPage];
    let landed = startPage;
    let lastHasMore = true;
    try {
      for (let p = startPage; p <= page; p++) {
        const res = await getCollectionWallpapers(collection.slug, { cursor: nextCursor, limit: PAGE_SIZE });
        const { items, next_cursor, has_more } = res.data.data;
        accumPages[p] = items;
        landed = p;
        lastHasMore = has_more;
        if (has_more && next_cursor) {
          localCursors[p + 1] = next_cursor;
          nextCursor = next_cursor;
        } else {
          nextCursor = undefined;
          break;
        }
      }
      setPages((prev) => ({ ...prev, ...accumPages }));
      setCursors(localCursors);
      if (lastHasMore && landed === page) {
        setHasMoreUpTo(landed);
      } else {
        setKnownTotalPages(landed);
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

  // Mesh CSS variable from the collection's accent_color. Sets
  // --c-accent on the page root; the mesh's radial gradients
  // color-mix this through 3 stops by default.
  const accentStyle = useMemo<React.CSSProperties>(() => {
    if (!collection?.accent_color) return {};
    return { '--c-accent': collection.accent_color } as React.CSSProperties;
  }, [collection?.accent_color]);

  // Hover-driven palette swap — same recipe as home / weekly: the
  // tile's color_palette overrides --c-c1/c2/c3 on the root while
  // hovered, mesh transitions in. On mouse leave we remove the
  // vars so the mesh falls back to the accent-color default.
  const rootRef = useRef<HTMLDivElement | null>(null);
  const applyPalette = useCallback((palette: string | undefined, dominant?: string) => {
    const root = rootRef.current;
    if (!root) return;
    if (!palette && !dominant) {
      root.style.removeProperty('--c-c1');
      root.style.removeProperty('--c-c2');
      root.style.removeProperty('--c-c3');
      return;
    }
    const parts = (palette || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length >= 3) {
      root.style.setProperty('--c-c1', parts[0]);
      root.style.setProperty('--c-c2', parts[Math.floor(parts.length / 2)]);
      root.style.setProperty('--c-c3', parts[parts.length - 1]);
    } else if (dominant) {
      root.style.setProperty('--c-c1', dominant);
      root.style.setProperty('--c-c2', dominant);
      root.style.setProperty('--c-c3', dominant);
    }
  }, []);

  // Not-found state stays an explicit empty view; everything else
  // (initial load) renders the full structure with skeletons so the
  // page doesn't reflow once data lands.
  if (!loading && !collection && error) return <ErrorState />;
  if (!loading && !collection) return <EmptyState message="Collection not found." />;

  const isOwner = !!collection && user?.id === collection.user_id;
  const visible = pages[currentPage] || [];
  const total = knownTotalPages ?? (hasMoreUpTo ? hasMoreUpTo + 1 : 1);
  const cover = collection?.cover_url || visible[0]?.preview_url || visible[0]?.thumb_url;
  const curatorInitial = (curator?.nickname || curator?.username || 'U').charAt(0).toUpperCase();

  return (
    <div ref={rootRef} className="c-detail min-h-full" style={accentStyle}>
      <div className="c-detail-mesh" aria-hidden />
      <PageMeta
        title={collection?.title || 'Collection'}
        description={collection?.description || (collection ? `Collection of ${collection.wallpaper_count} wallpapers` : '')}
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

        {/* Hero — framed cover (same recipe as the tiles below, just
            larger) + meta column. The paper mat + hairline + accent
            halo treatment is shared with the framed tiles so the
            page reads as one cohesive 'gallery wall + headline
            piece' rather than a hero + grid of unrelated cards. */}
        <section className="c-detail-hero-row">
          <div className="c-detail-hero-frame">
            <div className="c-detail-hero-mat">
              {cover ? (
                <img src={cover} alt={collection?.title || ''} className="c-detail-hero-img" />
              ) : loading ? (
                <div className="c-detail-hero-img skeleton-card" />
              ) : (
                <div className="c-detail-cover-empty">No cover yet</div>
              )}
            </div>
          </div>

          {/* Meta column. When still loading we render bar
              placeholders shaped roughly like kicker / title / desc
              / sub so the right side doesn't snap from blank → full
              when the API responds. */}
          {!collection ? (
            <div className="c-detail-meta">
              <div className="c-detail-skel-bar w-28 h-3" />
              <div className="c-detail-skel-bar w-2/3 h-12 mt-3" />
              <div className="c-detail-skel-bar w-full h-3 mt-5" />
              <div className="c-detail-skel-bar w-5/6 h-3 mt-2" />
              <div className="c-detail-skel-bar w-1/2 h-3 mt-7" />
            </div>
          ) : (
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
          )}
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
              {collection && visible.length > 0
                ? `${visible.length} of ${collection.wallpaper_count}`
                : collection
                  ? `${collection.wallpaper_count} ${collection.wallpaper_count === 1 ? 'piece' : 'pieces'}`
                  : ''}
            </span>
          </div>

          {/* Framed-prints grid — each wallpaper sits inside a paper
              "mat" with a hairline border + soft drop shadow, like a
              framed print on a gallery wall. 3:4 portrait keeps the
              eye moving down the wall; hover lifts the frame, the
              mat edge tints to the collection's accent, and the
              action rail (favorite/like/download) fades in over the
              image. Distinct from Weekly's 5-up 4:5 portrait tiles
              (no mat, no border — those read as 'magazine spread')
              and Discover's edge-to-edge utility grid. */}
          {(loading || (loadingPage && visible.length === 0)) ? (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-6">
              {Array.from({ length: 8 }).map((_, i) => (
                // Skeleton mirrors the real FramedTile: paper mat
                // (visible chrome) + image chamber (shimmer) + a
                // small chip placeholder so the geometry around
                // the corner doesn't shift when chips paint in.
                <div key={i} className="cd-frame">
                  <div className="cd-mat skeleton-card">
                    <div className="cd-frame-chip-skel" />
                  </div>
                </div>
              ))}
            </div>
          ) : visible.length === 0 ? (
            <div className="text-center py-20 text-muted text-sm">No wallpapers in this collection yet.</div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-6">
              {visible.map((w, i) => (
                <FramedTile key={w.id} wallpaper={w} index={i} onHover={applyPalette} />
              ))}
            </div>
          )}

          <Pagination current={currentPage} total={total} onChange={setCurrentPage} />
        </section>
      </main>
    </div>
  );
}
