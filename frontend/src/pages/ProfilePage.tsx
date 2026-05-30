import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useParams, useNavigate, Link, useLocation } from 'react-router-dom';
import {
  AiOutlineHeart,
  AiFillHeart,
  AiOutlineStar,
  AiFillStar,
  AiOutlineDownload,
  AiOutlineCheckCircle,
  AiOutlineLoading3Quarters,
  AiOutlineLock,
  AiOutlineEdit,
  AiOutlineCamera,
  AiOutlineCheck,
  AiOutlineClose,
  AiOutlinePicture,
  AiOutlineAppstore,
  AiOutlineThunderbolt,
  AiOutlinePlus,
} from 'react-icons/ai';
import { useWallpaperActions } from '../hooks/useWallpaperActions';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection, CoinTransaction } from '../types';
import {
  getUserProfile,
  getUserWallpapers,
  getUserCollections,
  getMyFavorites,
  getMyLikes,
  getMyDownloads,
  getUserFavorites,
  getUserLikes,
  getUserDownloads,
  getMyCoins,
  getCoinTransactions,
  updateProfile,
  uploadAvatar,
  changePassword,
  updatePrivacy,
} from '../api';
import { useAuthStore } from '../store/auth';
import PageMeta from '../components/PageMeta';
import EmptyState from '../components/EmptyState';
import ErrorState from '../components/ErrorState';
import {
  ProfileSkeleton,
} from '../components/Skeletons';
import Pagination from '../components/Pagination';
import AvatarCropModal from '../components/AvatarCropModal';

const PAGE_SIZE = 12; // ledger only — fixed-density list

// Wallpaper grids show 4 rows per page; cols match the tile grid
// breakpoints (cols-2 at xs, sm-3, md-4, lg-5). The wallpaper-list
// fetches and the Pagination total both read this so the last row
// is never partially filled.
const COLS_AT_WIDTH = (w: number): number =>
  w >= 1024 ? 5 : w >= 768 ? 4 : w >= 640 ? 3 : 2;
function calcGridPageSize(w: number): number {
  return COLS_AT_WIDTH(w) * 4;
}

type ListKey = 'favorites' | 'likes' | 'downloads';
type TabKey = 'uploads' | 'collections' | 'favorites' | 'likes' | 'downloads' | 'ledger';

interface ListState {
  items: Wallpaper[];
  page: number;
  cursors: number[]; // cursors[N] = cursor to fetch page N+1
  total: number;
  hidden: boolean;   // viewer doesn't have permission to see the list
  loaded: boolean;
  loading: boolean;
}
const emptyList = (): ListState => ({
  items: [], page: 1, cursors: [0], total: 0, hidden: false, loaded: false, loading: false,
});

function formatJoined(iso: string): string {
  if (!iso) return '';
  return new Date(iso).toLocaleDateString('en-US', { month: 'long', year: 'numeric' }).toUpperCase();
}

function relativeTime(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  if (ms < 60_000) return 'Just now';
  if (ms < 3_600_000) return `${Math.floor(ms / 60_000)} min ago`;
  if (ms < 86_400_000) return `Today, ${new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false })}`;
  const days = Math.floor(ms / 86_400_000);
  if (days < 30) return `${days} ${days === 1 ? 'day' : 'days'} ago`;
  const months = Math.floor(days / 30);
  return `${months} ${months === 1 ? 'month' : 'months'} ago`;
}

function dayLabel(iso: string): string {
  // Mono uppercase "MAY 15" for ledger day groupings.
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }).toUpperCase();
}

// Friendly ledger label per transaction type. Falls back to the raw type
// when it's not in the table so new types still render without code change.
const LEDGER_LABELS: Record<string, string> = {
  register_bonus:   'Signup bonus',
  upload_reward:    'Uploaded a wallpaper',
  download_cost:    'Downloaded a wallpaper',
  download_earned:  'Someone downloaded yours',
};

export default function ProfilePage() {
  const { username, tab: tabParam } = useParams<{ username: string; tab?: string }>();
  const navigate = useNavigate();
  const { user: currentUser, updateCoins, updateUser } = useAuthStore();

  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);

  // Grid page size — 4 rows × cols-at-current-viewport. Tracks
  // window resize so the wallpaper grids stay row-aligned across
  // breakpoints. Ledger uses the fixed PAGE_SIZE instead.
  const [gridPageSize, setGridPageSize] = useState<number>(
    () => (typeof window !== 'undefined' ? calcGridPageSize(window.innerWidth) : 20),
  );
  useEffect(() => {
    let raf = 0;
    const onResize = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        setGridPageSize(calcGridPageSize(window.innerWidth));
      });
    };
    window.addEventListener('resize', onResize);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('resize', onResize);
    };
  }, []);

  // ─── Tab state ─── URL-driven: /user/:username[/:tab]. Missing tab
  // segment means the implicit default ("uploads"). Unknown tab slugs
  // fall back to the default too so a typo in the URL doesn't blank
  // the page.
  const TAB_KEYS: TabKey[] = ['uploads', 'collections', 'favorites', 'likes', 'downloads', 'ledger'];
  const activeTab: TabKey = (TAB_KEYS as string[]).includes(tabParam || '')
    ? (tabParam as TabKey)
    : 'uploads';
  const isOwner = currentUser?.id === user?.id;

  // Uploads — two sub-lists (in-progress vs published) for owner; stranger sees only published.
  const [pubList, setPubList] = useState<ListState>(emptyList());
  const [inProgress, setInProgress] = useState<ListState>(emptyList());

  // Lists — favorites / likes / downloads
  const [favList, setFavList] = useState<ListState>(emptyList());
  const [likeList, setLikeList] = useState<ListState>(emptyList());
  const [dlList, setDlList] = useState<ListState>(emptyList());

  // Collections — single-page-load grab of the user's owned collections.
  const [collections, setCollections] = useState<Collection[]>([]);
  const [collectionsLoaded, setCollectionsLoaded] = useState(false);
  const [collectionsPage, setCollectionsPage] = useState(1);
  const [collectionsTotal, setCollectionsTotal] = useState(0);

  // Ledger — paginated transactions
  const [txs, setTxs] = useState<CoinTransaction[]>([]);
  const [txPage, setTxPage] = useState(1);
  const [txCursors, setTxCursors] = useState<number[]>([0]);
  const [txTotal, setTxTotal] = useState(0);
  const [txLoading, setTxLoading] = useState(false);
  const [txLoaded, setTxLoaded] = useState(false);

  // Profile edit modal state
  const avatarInputRef = useRef<HTMLInputElement>(null);
  const [cropFile, setCropFile] = useState<File | null>(null);
  const [editingProfile, setEditingProfile] = useState(false);
  const [editNickname, setEditNickname] = useState('');
  const [editBio, setEditBio] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);
  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [oldPw, setOldPw] = useState('');
  const [newPw, setNewPw] = useState('');
  const [savingPw, setSavingPw] = useState(false);

  // ─── Fetchers ───

  const setListFor = (key: 'pub' | 'inprogress' | ListKey, updater: (prev: ListState) => ListState) => {
    if (key === 'pub') setPubList(updater);
    else if (key === 'inprogress') setInProgress(updater);
    else if (key === 'favorites') setFavList(updater);
    else if (key === 'likes') setLikeList(updater);
    else if (key === 'downloads') setDlList(updater);
  };

  // Mirror each list into a ref so fetchList can read the latest
  // cursors without growing its useCallback deps. Without these
  // refs the captured closure's `cursors` array stayed empty after
  // page 1 — clicking page 2 fed limit-only params and refetched
  // page 1, which is what surfaced as "pagination not working".
  const pubListRef = useRef(pubList);
  const inProgressRef = useRef(inProgress);
  const favListRef = useRef(favList);
  const likeListRef = useRef(likeList);
  const dlListRef = useRef(dlList);
  pubListRef.current = pubList;
  inProgressRef.current = inProgress;
  favListRef.current = favList;
  likeListRef.current = likeList;
  dlListRef.current = dlList;

  // Generic page-fetch helper that talks to whichever endpoint the tab maps to.
  const fetchList = useCallback(async (
    target: 'pub' | 'inprogress' | ListKey,
    page: number,
  ) => {
    if (!user) return;
    const isMe = currentUser?.id === user.id;
    const stateGetter = (): ListState => {
      if (target === 'pub')        return pubListRef.current;
      if (target === 'inprogress') return inProgressRef.current;
      if (target === 'favorites')  return favListRef.current;
      if (target === 'likes')      return likeListRef.current;
      return dlListRef.current;
    };
    const current = stateGetter();
    const cursor = current.cursors[page - 1] ?? 0;
    setListFor(target, (p) => ({ ...p, loading: true }));
    try {
      let res;
      const params = cursor > 0 ? { cursor, limit: gridPageSize } : { limit: gridPageSize };
      if (target === 'pub') {
        res = await getUserWallpapers(user.username, { ...params, status: 1 });
      } else if (target === 'inprogress') {
        // Pending = Processing (0) + PendingReview (5). Backend supports
        // comma-separated statuses and emits a single paginated stream.
        res = await getUserWallpapers(user.username, { ...params, status: '0,5' });
      } else if (isMe) {
        // Owner: use the /me/* endpoints (existing behavior — these don't
        // 403 and don't apply privacy gates).
        if (target === 'favorites') res = await getMyFavorites(params);
        else if (target === 'likes') res = await getMyLikes(params);
        else res = await getMyDownloads(params);
      } else {
        // Stranger: use the per-user endpoints which return `private: true`
        // when the owner has hidden that list.
        const fn = target === 'favorites' ? getUserFavorites
                 : target === 'likes' ? getUserLikes
                 : getUserDownloads;
        res = await fn(user.username, params);
      }
      const data = res.data.data as { items: Wallpaper[]; next_cursor: number; has_more: boolean; total?: number; private?: boolean };
      if (data.private) {
        setListFor(target, () => ({ items: [], page, cursors: [0], total: 0, hidden: true, loaded: true, loading: false }));
        return;
      }
      setListFor(target, (prev) => {
        const cursors = prev.cursors.slice(0, page);
        if (data.has_more && data.next_cursor > 0) cursors[page] = data.next_cursor;
        return {
          items: data.items || [],
          page,
          cursors,
          total: data.total ?? 0,
          hidden: false,
          loaded: true,
          loading: false,
        };
      });
    } catch {
      toast.error('Failed to load');
      setListFor(target, (p) => ({ ...p, loading: false, loaded: true }));
    }
  // We intentionally don't depend on the list states themselves to avoid
  // recreating fetchList on every page bump — the closure captures the
  // current state via the setListFor + setter pair only.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, currentUser?.id, gridPageSize]);

  // Collections grid uses its own page-size + cursor table. The
  // grid is 4 cols at lg (one fewer than the wallpaper grid) so
  // pageSize = colsAtWidth × 4, capped to a sensible upper bound.
  const collectionsPageSize = useMemo(() => {
    const cols = (typeof window !== 'undefined' && window.innerWidth >= 1024) ? 4
      : (typeof window !== 'undefined' && window.innerWidth >= 768) ? 3
      : (typeof window !== 'undefined' && window.innerWidth >= 640) ? 2
      : 1;
    return cols * 4;
    // gridPageSize changes on resize and we reuse that as a proxy
    // for "viewport changed". Re-running per resize keeps the page
    // count aligned with the current viewport.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gridPageSize]);
  const collectionsCursorsRef = useRef<number[]>([0]);
  const fetchCollections = useCallback(async (page = 1) => {
    if (!user) return;
    const cursor = collectionsCursorsRef.current[page - 1] ?? 0;
    try {
      const params = cursor > 0
        ? { cursor, limit: collectionsPageSize }
        : { limit: collectionsPageSize };
      const res = await getUserCollections(user.username, params);
      const data = res.data.data as { items: Collection[]; next_cursor: number; has_more: boolean; total?: number };
      setCollections(data.items || []);
      setCollectionsPage(page);
      setCollectionsTotal(data.total ?? 0);
      collectionsCursorsRef.current = collectionsCursorsRef.current.slice(0, page);
      if (data.has_more && data.next_cursor > 0) {
        collectionsCursorsRef.current[page] = data.next_cursor;
      }
    } catch {
      toast.error('Failed to load collections');
    } finally {
      setCollectionsLoaded(true);
    }
  }, [user, collectionsPageSize]);

  const fetchLedger = useCallback(async (page: number) => {
    setTxLoading(true);
    try {
      const cursor = txCursors[page - 1] ?? 0;
      const res = await getCoinTransactions({ cursor: cursor > 0 ? cursor : undefined, limit: PAGE_SIZE });
      const data = res.data.data;
      setTxs(data?.items ?? []);
      setTxTotal(data?.total ?? 0);
      setTxPage(page);
      setTxCursors((prev) => {
        const next = prev.slice(0, page);
        if (data?.has_more && data?.next_cursor) next[page] = data.next_cursor;
        return next;
      });
      setTxLoaded(true);
    } catch {
      toast.error('Failed to load ledger');
    } finally {
      setTxLoading(false);
    }
  }, [txCursors]);

  // ─── Initial load ───
  useEffect(() => {
    if (!username) return;
    setLoading(true);
    setPubList(emptyList()); setInProgress(emptyList());
    setFavList(emptyList()); setLikeList(emptyList()); setDlList(emptyList());
    setCollections([]); setCollectionsLoaded(false); setCollectionsPage(1); setCollectionsTotal(0); collectionsCursorsRef.current = [0];
    setTxs([]); setTxPage(1); setTxCursors([0]); setTxTotal(0); setTxLoaded(false);

    setError(false);
    getUserProfile(username)
      .then((res) => setUser(res.data.data))
      .catch((e) => {
        if (e?.response?.status !== 404) setError(true);
      })
      .finally(() => setLoading(false));
  }, [username]);

  // Initial uploads page once we know the user.
  useEffect(() => {
    if (!user) return;
    fetchList('pub', 1);
    if (currentUser?.id === user.id) {
      fetchList('inprogress', 1);
      // Owner sees the ledger on the Coins tab — preload coins balance via
      // /coins so the header card stays accurate.
      getMyCoins().then((res) => updateCoins(res.data.data.coins)).catch(() => { /* silent */ });
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  // Tab click → push canonical URL. uploads goes to /user/:username
  // (no tab suffix, that's the default); others go to
  // /user/:username/:tab. Reload / share-link / back-button all land
  // on the same view.
  const onTabChange = (tab: TabKey) => {
    if (tab === 'uploads') navigate(`/user/${username}`);
    else navigate(`/user/${username}/${tab}`);
  };
  // Lazy-load each tab on first activation. Driven by activeTab so it
  // fires both for in-page clicks and for direct deep-links (e.g. the
  // top-nav coin pill → /user/:username/ledger).
  useEffect(() => {
    if (!user) return;
    if (activeTab === 'collections' && !collectionsLoaded) fetchCollections();
    if (activeTab === 'favorites'  && !favList.loaded)  fetchList('favorites', 1);
    if (activeTab === 'likes'      && !likeList.loaded) fetchList('likes', 1);
    if (activeTab === 'downloads'  && !dlList.loaded)   fetchList('downloads', 1);
    if (activeTab === 'ledger'     && !txLoaded)        fetchLedger(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [activeTab, user?.id]);

  // ─── Avatar + profile edit handlers ───
  const handleAvatarChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;
    if (file.size > 10 * 1024 * 1024) { toast.error('图片需小于 10MB'); return; }
    setCropFile(file);
  };
  const uploadCroppedAvatar = async (blob: Blob) => {
    const fd = new FormData();
    fd.append('avatar', blob, 'avatar.jpg');
    try {
      const res = await uploadAvatar(fd);
      const url = res.data.data.avatar_url;
      setUser((prev) => prev ? { ...prev, avatar_url: url } : prev);
      updateUser({ avatar_url: url });
      setCropFile(null);
      toast.success('Avatar updated');
    } catch { toast.error('Avatar upload failed'); }
  };
  const startEdit = () => {
    setEditNickname(user?.nickname || '');
    setEditBio(user?.bio || '');
    setEditingProfile(true);
  };
  const saveProfile = async () => {
    const nickname = editNickname.trim();
    if (!nickname) { toast.error('Nickname is required'); return; }
    if (nickname.length > 64) { toast.error('Nickname too long (max 64)'); return; }
    const bio = editBio.trim();
    if (bio.length > 500) { toast.error('Bio too long (max 500)'); return; }
    if (nickname === (user?.nickname || '') && bio === (user?.bio || '')) {
      setEditingProfile(false); return;
    }
    setSavingProfile(true);
    try {
      const res = await updateProfile({ nickname, bio });
      const updated = res.data.data;
      setUser((prev) => prev ? { ...prev, nickname: updated.nickname, bio: updated.bio } : prev);
      updateUser({ nickname: updated.nickname });
      setEditingProfile(false);
      toast.success('Profile updated');
    } catch { toast.error('Failed to save profile'); } finally { setSavingProfile(false); }
  };
  const handleChangePassword = async () => {
    if (newPw.length < 8) { toast.error('Password must be at least 8 characters'); return; }
    setSavingPw(true);
    try {
      await changePassword({ old_password: oldPw, new_password: newPw });
      toast.success('Password changed');
      setShowPasswordModal(false); setOldPw(''); setNewPw('');
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } } };
      const msg = e?.response?.data?.message;
      toast.error(msg === 'wrong password' ? 'Current password is incorrect' : 'Failed to change password');
    } finally { setSavingPw(false); }
  };

  // ─── Privacy toggle ───
  const togglePrivacy = async (list: ListKey) => {
    if (!user) return;
    const key = `${list}_public` as 'likes_public' | 'favorites_public' | 'downloads_public';
    const next = !user[key];
    try {
      const res = await updatePrivacy({ [key]: next });
      setUser(res.data.data);
      updateUser({ [key]: next });
      toast.success(next ? `Your ${list} list is now public.` : `Your ${list} list is now private.`);
    } catch { toast.error('Failed to update privacy'); }
  };

  if (loading) {
    return (
      <div className="bg-paper text-ink min-h-full">
        <ProfileSkeleton />
      </div>
    );
  }
  if (!user && error) return <ErrorState />;
  if (!user) return <EmptyState message="User not found." />;

  const display = user.nickname || user.username;
  const balance = isOwner ? (currentUser?.coins ?? 0) : (user.coins ?? 0);

  // ─── Counts shown in the tab pills ───
  const counts = {
    uploads:     pubList.loaded ? pubList.total : (isOwner && inProgress.loaded ? inProgress.total + pubList.total : undefined),
    collections: collectionsLoaded ? collections.length : undefined,
    favorites:   favList.loaded && !favList.hidden ? favList.total : undefined,
    likes:       likeList.loaded && !likeList.hidden ? likeList.total : undefined,
    downloads:   dlList.loaded && !dlList.hidden ? dlList.total : undefined,
    ledger:      txLoaded ? txTotal : undefined,
  };

  const allTabs: { key: TabKey; label: string; ownerOnly?: boolean }[] = [
    { key: 'uploads',     label: 'Uploads' },
    { key: 'collections', label: 'Collections' },
    { key: 'favorites',   label: 'Favorites' },
    { key: 'likes',       label: 'Likes' },
    { key: 'downloads',   label: 'Downloads',   ownerOnly: true },
    { key: 'ledger',      label: 'Coin ledger', ownerOnly: true },
  ];
  const tabs = isOwner ? allTabs : allTabs.filter((t) => !t.ownerOnly);

  return (
    <div className="profile-page min-h-full">
      <div className="profile-mesh" aria-hidden />
      <PageMeta
        title={`${display}'s profile`}
        description={`Wallpapers, collections, and uploads from ${display} on Wallpaper Exchange.`}
        image={user.avatar_url}
        type="profile"
      />

      <main className="relative z-10 max-w-[1280px] mx-auto px-6 sm:px-10 lg:px-14 pt-10 pb-16">

      <ProfileHeader
        user={user}
        isOwner={isOwner}
        balance={balance}
        editing={editingProfile}
        editNickname={editNickname}
        editBio={editBio}
        savingProfile={savingProfile}
        onEditNicknameChange={setEditNickname}
        onEditBioChange={setEditBio}
        onStartEdit={startEdit}
        onCancelEdit={() => setEditingProfile(false)}
        onSaveProfile={saveProfile}
        onChangePassword={() => setShowPasswordModal(true)}
        onAvatarPick={() => avatarInputRef.current?.click()}
        avatarInputRef={avatarInputRef}
        onAvatarChange={handleAvatarChange}
      />

      <ProfileTabs tabs={tabs} active={activeTab} counts={counts} onChange={onTabChange} />

      <div className="mt-6">
        {activeTab === 'uploads' && (
          <UploadsPanel
            isOwner={isOwner}
            inProgress={inProgress}
            pub={pubList}
            pageSize={gridPageSize}
            onPubPage={(p) => fetchList('pub', p)}
            onInProgressPage={(p) => fetchList('inprogress', p)}
          />
        )}
        {activeTab === 'collections' && (
          <CollectionsPanel
            isOwner={isOwner}
            user={user}
            collections={collections}
            loaded={collectionsLoaded}
            page={collectionsPage}
            total={collectionsTotal}
            pageSize={collectionsPageSize}
            onPage={(p) => fetchCollections(p)}
          />
        )}
        {activeTab === 'favorites' && (
          <ListPanel
            listKey="favorites"
            state={favList}
            isOwner={isOwner}
            isPublic={!!user.favorites_public}
            pageSize={gridPageSize}
            onPage={(p) => fetchList('favorites', p)}
            onTogglePrivacy={() => togglePrivacy('favorites')}
          />
        )}
        {activeTab === 'likes' && (
          <ListPanel
            listKey="likes"
            state={likeList}
            isOwner={isOwner}
            isPublic={!!user.likes_public}
            pageSize={gridPageSize}
            onPage={(p) => fetchList('likes', p)}
            onTogglePrivacy={() => togglePrivacy('likes')}
          />
        )}
        {activeTab === 'downloads' && (
          <ListPanel
            listKey="downloads"
            state={dlList}
            isOwner={isOwner}
            isPublic={!!user.downloads_public}
            pageSize={gridPageSize}
            onPage={(p) => fetchList('downloads', p)}
            onTogglePrivacy={() => togglePrivacy('downloads')}
          />
        )}
        {activeTab === 'ledger' && (
          <LedgerPanel
            txs={txs}
            page={txPage}
            total={txTotal}
            loading={txLoading}
            balance={currentUser?.coins ?? 0}
            onPage={fetchLedger}
          />
        )}
      </div>

      {cropFile && (
        <AvatarCropModal
          file={cropFile}
          onCancel={() => setCropFile(null)}
          onSave={uploadCroppedAvatar}
        />
      )}

      {showPasswordModal && (
        <div
          onClick={() => setShowPasswordModal(false)}
          className="fixed inset-0 z-[60] flex items-start justify-center pt-[20vh] px-4"
          style={{ background: 'rgba(15,12,8,0.55)' }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="bg-paper border border-ink w-full max-w-[360px] p-5"
            style={{ boxShadow: '0 16px 40px rgba(0,0,0,0.18)' }}
          >
            <div className="kicker text-muted mb-3">Change password</div>
            <input
              type="password" placeholder="Current password"
              value={oldPw} onChange={(e) => setOldPw(e.target.value)}
              className="w-full px-3.5 py-3 bg-paper text-[14px] mb-2"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <input
              type="password" placeholder="New password (min 8 chars)"
              value={newPw} onChange={(e) => setNewPw(e.target.value)}
              className="w-full px-3.5 py-3 bg-paper text-[14px]"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <div className="flex justify-end gap-2 mt-3">
              <button
                onClick={() => setShowPasswordModal(false)}
                className="px-3.5 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2"
              >Cancel</button>
              <button
                onClick={handleChangePassword}
                disabled={savingPw}
                className="px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50"
              >{savingPw ? 'Saving…' : 'Confirm'}</button>
            </div>
          </div>
        </div>
      )}
      </main>
    </div>
  );
}

// ─── Sub-components ──────────────────────────────────────────────────

interface ProfileHeaderProps {
  user: User;
  isOwner: boolean;
  balance: number;
  editing: boolean;
  editNickname: string;
  editBio: string;
  savingProfile: boolean;
  onEditNicknameChange: (v: string) => void;
  onEditBioChange: (v: string) => void;
  onStartEdit: () => void;
  onCancelEdit: () => void;
  onSaveProfile: () => void;
  onChangePassword: () => void;
  onAvatarPick: () => void;
  avatarInputRef: React.RefObject<HTMLInputElement | null>;
  onAvatarChange: (e: React.ChangeEvent<HTMLInputElement>) => void;
}

function ProfileHeader(p: ProfileHeaderProps) {
  const display = p.user.nickname || p.user.username;
  const initial = display.charAt(0).toUpperCase();

  return (
    <header className="profile-hero">
      {/* Avatar — bigger now (140px), centered with the title row. */}
      <div className="profile-hero-avatar">
        <div className="profile-hero-avatar-frame">
          {p.user.avatar_url
            ? <img src={p.user.avatar_url} alt="" />
            : <span className="display text-[56px] text-ink">{initial}</span>}
        </div>
        {p.isOwner && (
          <>
            <button
              onClick={p.onAvatarPick}
              title="Change avatar"
              className="profile-hero-avatar-edit"
            >
              <AiOutlineCamera size={14} />
            </button>
            <input
              ref={p.avatarInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              className="hidden"
              onChange={p.onAvatarChange}
            />
          </>
        )}
      </div>

      {/* Identity column */}
      <div className="profile-hero-id">
        <div className="kicker text-muted">
          Contributor · Member since {formatJoined(p.user.created_at)}
        </div>

        {p.editing ? (
          <div className="mt-3 space-y-3 max-w-[520px]">
            <input
              autoFocus
              value={p.editNickname}
              onChange={(e) => p.onEditNicknameChange(e.target.value)}
              maxLength={64}
              placeholder="Nickname"
              className="profile-hero-edit-name display"
            />
            <textarea
              value={p.editBio}
              onChange={(e) => p.onEditBioChange(e.target.value)}
              maxLength={500}
              rows={3}
              placeholder="Signature, motto, anything you want here"
              className="profile-hero-edit-bio"
            />
            <div className="flex gap-2 items-center flex-wrap">
              <button onClick={p.onSaveProfile} disabled={p.savingProfile || !p.editNickname.trim()}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50 hover:bg-ink-2 transition-colors">
                <AiOutlineCheck size={13} /> {p.savingProfile ? 'Saving…' : 'Save'}
              </button>
              <button onClick={p.onCancelEdit}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2 transition-colors">
                <AiOutlineClose size={13} /> Cancel
              </button>
              <span className="text-[11px] text-muted">
                Username @{p.user.username} can't be changed
              </span>
            </div>
          </div>
        ) : (
          <>
            <h1 className="display text-[clamp(38px,4.8vw,60px)] leading-[1.02] tracking-[-0.018em] mt-2 text-ink">
              {display}
            </h1>
            <div className="mono text-[12px] text-muted tracking-[0.06em] mt-2">
              @{p.user.username}
              {p.isOwner && p.user.email ? ` · ${p.user.email}` : ''}
            </div>
            {p.user.bio && (
              <p className="profile-hero-bio">
                {p.user.bio}
              </p>
            )}
          </>
        )}
      </div>

      {/* Right column — balance card + owner action pills. The
          balance card stays prominent (it's the user's primary
          state question on this page); actions are pill row
          below. */}
      <div className="profile-hero-right">
        {p.isOwner && !p.editing && (
          <Link
            to={`/user/${p.user.username}/ledger`}
            title="Coin ledger"
            className="profile-hero-balance no-underline"
          >
            <div className="profile-hero-balance-kicker">Balance</div>
            <div className="profile-hero-balance-row">
              <span className="profile-hero-balance-coin" aria-hidden />
              <span className="profile-hero-balance-num">{p.balance}</span>
              <span className="profile-hero-balance-unit">COINS</span>
            </div>
          </Link>
        )}
        {p.isOwner && !p.editing && (
          <div className="profile-hero-actions">
            <button
              onClick={p.onStartEdit}
              className="profile-hero-pill"
            >
              <AiOutlineEdit size={13} /> Edit profile
            </button>
            <button
              onClick={p.onChangePassword}
              className="profile-hero-pill"
            >
              Password
            </button>
            <Link
              to="/upload"
              className="profile-hero-pill is-primary no-underline"
            >
              <AiOutlinePlus size={13} /> Upload
            </Link>
          </div>
        )}
      </div>
    </header>
  );
}

interface ProfileTabsProps {
  tabs: { key: TabKey; label: string }[];
  active: TabKey;
  counts: Partial<Record<TabKey, number | undefined>>;
  onChange: (k: TabKey) => void;
}
function ProfileTabs({ tabs, active, counts, onChange }: ProfileTabsProps) {
  const icon: Record<TabKey, React.ElementType> = {
    uploads: AiOutlinePicture,
    collections: AiOutlineAppstore,
    favorites: AiOutlineStar,
    likes: AiOutlineHeart,
    downloads: AiOutlineDownload,
    ledger: AiOutlineThunderbolt,
  };
  return (
    <div className="ptabs mt-6 overflow-x-auto">
      {tabs.map((t) => {
        const Icon = icon[t.key];
        const c = counts[t.key];
        return (
          <button
            key={t.key}
            onClick={() => onChange(t.key)}
            className={t.key === active ? 'is-active' : ''}
          >
            <Icon size={13} />
            <span>{t.label}</span>
            {c !== undefined && <span className="ptab-count">{c}</span>}
          </button>
        );
      })}
    </div>
  );
}

interface UploadsPanelProps {
  isOwner: boolean;
  inProgress: ListState;
  pub: ListState;
  pageSize: number;
  onPubPage: (p: number) => void;
  onInProgressPage: (p: number) => void;
}
function UploadsPanel({ isOwner, inProgress, pub, pageSize, onPubPage, onInProgressPage }: UploadsPanelProps) {
  const showInProgress = isOwner && inProgress.loaded && inProgress.items.length > 0;
  const inTotal = inProgress.total;
  const pubTotal = pub.total;

  return (
    <div>
      {showInProgress && (
        <section className="mb-8">
          <div className="label-rule mb-3">Pending · {inTotal}</div>
          <p className="text-[12px] text-muted mb-4">
            Wallpapers still being processed or waiting on admin review. Each tile
            shows its exact stage; they enter the public archive once approved.
          </p>
          <Grid items={inProgress.items} showProcessing />
          <Pagination
            current={inProgress.page}
            total={Math.max(1, Math.ceil(inTotal / pageSize))}
            onChange={onInProgressPage}
          />
        </section>
      )}

      <section>
        <div className="label-rule mb-3">
          Published · {pub.items.length === 0 && !pub.loaded ? '…' : `${pub.items.length} of ${pubTotal}`}
        </div>
        {!pub.loaded ? (
          <ProfileWallpapersSkeleton />
        ) : pub.items.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">No published wallpapers yet.</div>
        ) : (
          <>
            <Grid items={pub.items} />
            <Pagination
              current={pub.page}
              total={Math.max(1, Math.ceil(pubTotal / pageSize))}
              onChange={onPubPage}
            />
          </>
        )}
      </section>
    </div>
  );
}

interface CollectionsPanelProps {
  isOwner: boolean;
  user: User;
  collections: Collection[];
  loaded: boolean;
  page: number;
  total: number;
  pageSize: number;
  onPage: (p: number) => void;
}
function CollectionsPanel({ isOwner, collections, loaded, page, total, pageSize, onPage }: CollectionsPanelProps) {
  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div className="label-rule flex-1">
          Created · {loaded ? total : '…'}
        </div>
        {isOwner && (
          <Link
            to="/collections"
            className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium no-underline hover:bg-ink-2"
          >
            <AiOutlinePlus size={13} /> New collection
          </Link>
        )}
      </div>
      {!loaded ? (
        <ProfileCollectionsSkeleton count={pageSize} />
      ) : collections.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">No collections yet.</div>
      ) : (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-7">
            {collections.map((c) => (
              <ProfileCollectionTile key={c.id} c={c} />
            ))}
          </div>
          <Pagination
            current={page}
            total={Math.max(1, Math.ceil(total / pageSize))}
            onChange={onPage}
          />
        </>
      )}
    </div>
  );
}

/* CollectionsPanel tile — same .c-tile chrome as the
   /collections library page (stacked-paper aesthetic with an
   accent-tinted shadow layer). Cover fallback chain: cover_url →
   recent_tiles[0].preview_url → recent_tiles[0].thumb_url →
   empty card. */
function ProfileCollectionTile({ c }: { c: Collection }) {
  const accent = c.accent_color || 'var(--color-accent)';
  const firstTile = c.recent_tiles?.[0];
  const preferred = firstTile?.preview_url || c.cover_url || firstTile?.thumb_url || '';
  const fallbackSrc = firstTile?.thumb_url || '';
  const [src, setSrc] = useState(preferred);
  return (
    <Link
      to={`/collections/${c.slug}`}
      className="c-tile no-underline"
      style={{ '--c-accent': accent } as React.CSSProperties}
    >
      <div className="c-tile-frame">
        {src ? (
          <img
            src={src}
            alt={c.title}
            loading="lazy"
            onError={() => {
              if (fallbackSrc && src !== fallbackSrc) setSrc(fallbackSrc);
              else setSrc('');
            }}
          />
        ) : (
          <div className="c-tile-empty">No cover yet</div>
        )}
      </div>
      <div className="c-tile-caption">
        <div className="c-tile-kicker">
          {c.kind === 1 ? 'Editor Theme' : 'Collection'}
          {!c.is_public && ' · Private'}
        </div>
        <div className="c-tile-title">{c.title}</div>
        <div className="c-tile-meta">
          {c.wallpaper_count} {c.wallpaper_count === 1 ? 'wallpaper' : 'wallpapers'}
        </div>
      </div>
    </Link>
  );
}

/* Skeletons matching the live grids — same chrome (dev-spec-card
   for wallpapers, c-tile for collections) so loading state and
   loaded state occupy identical footprints. Staggered animation
   delays via .skeleton-card's shimmer. */
function ProfileWallpapersSkeleton() {
  // Match the live grid: 5 cols at lg, 4 rows ≈ 20 tiles. Smaller
  // batches at narrower breakpoints — the responsive Tailwind grid
  // will wrap, so showing extras is harmless.
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
      {Array.from({ length: 20 }).map((_, i) => (
        <div key={i} className="dev-spec-card skeleton-card" style={{ aspectRatio: '3 / 2', animationDelay: `${Math.min(i, 16) * 30}ms` }} />
      ))}
    </div>
  );
}
function ProfileCollectionsSkeleton({ count }: { count: number }) {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-7">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="flex flex-col gap-3">
          <div className="c-tile-frame skeleton-card" style={{ aspectRatio: '1 / 1' }} />
          <div className="skeleton-card" style={{ width: '40%', height: 10, borderRadius: 4 }} />
          <div className="skeleton-card" style={{ width: '70%', height: 18, borderRadius: 4 }} />
          <div className="skeleton-card" style={{ width: '30%', height: 9, borderRadius: 4 }} />
        </div>
      ))}
    </div>
  );
}

interface ListPanelProps {
  pageSize: number;
  listKey: ListKey;
  state: ListState;
  isOwner: boolean;
  isPublic: boolean;
  onPage: (p: number) => void;
  onTogglePrivacy: () => void;
}
function ListPanel({ listKey, state, isOwner, isPublic, pageSize, onPage, onTogglePrivacy }: ListPanelProps) {
  const heading = useMemo(() => `${listKey.charAt(0).toUpperCase() + listKey.slice(1)} · ${state.total}`, [listKey, state.total]);

  if (state.hidden) {
    return (
      <div
        className="text-center py-16 px-6"
        style={{ background: 'var(--color-paper-2)', border: '1px dashed var(--color-hair)' }}
      >
        <AiOutlineLock size={28} className="mx-auto text-ink-2 mb-3" />
        <div className="display text-[24px] leading-tight">Hidden from view</div>
        <p className="text-[13px] text-muted mt-2 max-w-[420px] mx-auto">
          The owner has set their {listKey} list to private.
        </p>
      </div>
    );
  }

  return (
    <div>
      {isOwner && (
        <PrivacyNotice listName={`${listKey} list`} isPublic={isPublic} onToggle={onTogglePrivacy} />
      )}

      <div className="label-rule mt-5 mb-3">{heading}</div>

      {!state.loaded ? (
        <ProfileWallpapersSkeleton />
      ) : state.items.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">Nothing here yet.</div>
      ) : (
        <>
          <Grid items={state.items} />
          <Pagination
            current={state.page}
            total={Math.max(1, Math.ceil(state.total / pageSize))}
            onChange={onPage}
          />
        </>
      )}
    </div>
  );
}

function PrivacyNotice({ listName, isPublic, onToggle }: { listName: string; isPublic: boolean; onToggle: () => void }) {
  return (
    <div className="priv-notice">
      <div className="priv-icon"><AiOutlineLock size={16} /></div>
      <div>
        <div className="priv-title">Your {listName} is {isPublic ? 'public' : 'private'}</div>
        <div className="priv-sub">
          {isPublic
            ? 'Anyone visiting your profile can see this list.'
            : 'Only you can see this list. Make it public to share what you collect.'}
        </div>
      </div>
      <button
        onClick={onToggle}
        className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-full bg-paper border border-ink text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors whitespace-nowrap"
      >
        {isPublic ? 'Make private' : 'Make public'}
      </button>
    </div>
  );
}

interface LedgerPanelProps {
  txs: CoinTransaction[];
  page: number;
  total: number;
  loading: boolean;
  balance: number;
  onPage: (p: number) => void;
}
function LedgerSkeleton() {
  return (
    <div>
      {Array.from({ length: 6 }).map((_, i) => (
        <div
          key={i}
          className="grid grid-cols-[60px_1fr_auto] gap-3 items-center py-3 border-b border-hair"
        >
          <div className="h-4 w-10 bg-paper-3 skeleton-card" style={{ animationDelay: `${i * 80}ms` }} />
          <div className="h-3 bg-paper-3 skeleton-card" style={{ width: `${50 + (i % 3) * 15}%`, animationDelay: `${i * 80 + 40}ms` }} />
          <div className="h-3 w-16 bg-paper-3 skeleton-card" style={{ animationDelay: `${i * 80 + 80}ms` }} />
        </div>
      ))}
    </div>
  );
}

function LedgerPanel({ txs, page, total, loading, balance, onPage }: LedgerPanelProps) {
  // Aggregate stats over the visible transactions. Keeps the summary strip
  // honest for the current page; a full-history aggregate would need a
  // dedicated endpoint that we can add later.
  const earned = txs.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const spent = txs.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);

  // Group entries by day (mono caps month/day heading).
  const grouped = useMemo(() => {
    const out: Array<{ day: string; rows: CoinTransaction[] }> = [];
    let last = '';
    for (const tx of txs) {
      const d = dayLabel(tx.created_at);
      if (d !== last) {
        out.push({ day: d, rows: [] });
        last = d;
      }
      out[out.length - 1].rows.push(tx);
    }
    return out;
  }, [txs]);

  return (
    <div>
      {/* Summary strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 border-l border-t border-r border-hair">
        {[
          ['BALANCE',  String(balance),                  'text-ink',     ''],
          ['EARNED',   `+${earned}`,                     'text-accent',  'this page'],
          ['SPENT',    `−${spent}`,                      'text-ink-2',   'this page'],
          ['NEXT',     '+1',                             'text-ink',     'per upload'],
        ].map(([k, v, color, sub]) => (
          <div key={k} className="px-4 py-3.5 border-r border-b border-hair">
            <div className="kicker text-muted">{k}</div>
            <div className={`display text-[32px] sm:text-[36px] leading-none mt-1 ${color}`}>{v}</div>
            {sub && <div className="mono text-[10px] tracking-[0.06em] text-muted mt-1">{sub}</div>}
          </div>
        ))}
      </div>

      <div className="label-rule mt-7 mb-3">Recent entries</div>

      {loading && txs.length === 0 ? (
        <LedgerSkeleton />
      ) : txs.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">No transactions yet.</div>
      ) : (
        <>
          {grouped.map((g) => (
            <div key={g.day} className="mb-4">
              <div className="mono text-[10px] tracking-[0.14em] text-muted px-1 pb-2">{g.day}</div>
              {g.rows.map((tx) => {
                const label = LEDGER_LABELS[tx.tx_type] || tx.description || tx.tx_type;
                const isEarn = tx.amount > 0;
                return (
                  <div
                    key={tx.id}
                    className="grid grid-cols-[60px_1fr_auto] gap-3 items-center py-3 border-b border-hair last:border-b-0"
                  >
                    <span
                      className={`mono text-[15px] font-semibold tabular-nums ${isEarn ? 'text-accent' : 'text-ink-2'}`}
                    >
                      {isEarn ? '+' : ''}{tx.amount}
                    </span>
                    <div className="min-w-0">
                      <div className="text-[13px] text-ink truncate">
                        {label}
                        {tx.ref_id > 0 && (
                          <> · <Link to={`/wallpaper/${tx.ref_id}`} className="text-ink-2 underline">№{String(tx.ref_id).padStart(3, '0')}</Link></>
                        )}
                      </div>
                    </div>
                    <span className="mono text-[10px] tracking-[0.06em] text-muted">
                      {relativeTime(tx.created_at)}
                    </span>
                  </div>
                );
              })}
            </div>
          ))}
          <Pagination
            current={page}
            total={Math.max(1, Math.ceil(total / PAGE_SIZE))}
            onChange={onPage}
          />
        </>
      )}
    </div>
  );
}

// ─── Grid — Discover-style tiles at MD density (5 cols at lg) ───────
// Reuses the .dev-spec-card chrome + .tile-chip vocabulary so the
// profile lists read as part of the same family as Discover /
// device pages. Each tile carries res / video / mac-dynamic / AI
// chips and a hover action rail (favorite / like / download).
// Processing overlay still opt-in for the "in progress" panel.

function Grid({ items, showProcessing }: { items: Wallpaper[]; showProcessing?: boolean }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
      {items.map((w, i) => (
        <ProfileWallpaperTile
          key={w.id}
          w={w}
          index={i}
          showProcessing={!!showProcessing}
        />
      ))}
    </div>
  );
}

function ProfileWallpaperTile({
  w, index, showProcessing,
}: {
  w: Wallpaper;
  index: number;
  showProcessing: boolean;
}) {
  const location = useLocation();
  const acts = useWallpaperActions(w);
  const isVideo = (w.file_type || '').startsWith('video/');
  const px = Math.max(w.width || 0, w.height || 0);
  const resLabel = px >= 7680 ? '8K'
    : px >= 3840 ? '4K'
    : px >= 2560 ? '2K'
    : px >= 1920 ? '1080P'
    : px >= 1280 ? '720P'
    : '';
  const stop = (e: React.MouseEvent, fn: () => void) => {
    e.preventDefault();
    e.stopPropagation();
    fn();
  };
  const isPublished = w.status === 1;
  return (
    <Link
      to={`/wallpaper/${w.slug || w.id}`}
      state={{ background: location, initialWallpaper: w }}
      className="dev-spec-card"
      style={{ animationDelay: `${Math.min(index, 16) * 30}ms` }}
    >
      <div className="dev-spec-card-screen" style={{ aspectRatio: '3 / 2' }}>
        <img
          src={w.preview_url || w.thumb_url}
          alt={w.title || `Wallpaper ${w.id}`}
          loading="lazy"
          className="dev-spec-card-img"
          style={{ backgroundColor: w.dominant_color || undefined }}
        />
        {(resLabel || isVideo || w.is_dynamic || w.is_ai_generated) && (
          <div className="absolute top-2.5 left-2.5 z-[3] flex gap-1 flex-wrap max-w-[calc(100%-20px)]">
            {resLabel && <span className="tile-chip">{resLabel}</span>}
            {isVideo && (
              <span className="tile-chip">
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z" /></svg>
                Video
              </span>
            )}
            {w.is_dynamic && (
              <span className="tile-chip">
                <svg viewBox="0 0 384 512" fill="currentColor" aria-hidden><path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184 4 273.5c0 26.2 4.8 53.3 14.4 81.2 12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" /></svg>
                Mac
              </span>
            )}
            {w.is_ai_generated && (
              <span className="tile-chip is-ai">
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M12 2l1.6 4.6L18 8.2l-4.4 1.6L12 14.4l-1.6-4.6L6 8.2l4.4-1.6L12 2zm7 10l1 2.8 2.8 1-2.8 1L19 19.6l-1-2.8-2.8-1 2.8-1L19 12zM5 14l.9 2.6L8.4 17.6l-2.5 1L5 21.2 4.1 18.6 1.6 17.6 4.1 16.6 5 14z" /></svg>
                AI
              </span>
            )}
          </div>
        )}
        {/* Hover action rail — only when the wallpaper is actually
            interactable (published). Hidden for in-progress /
            rejected items because favorite / like would 404. */}
        {isPublished && (
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
        )}
        {/* Processing / pending-review / rejected status overlays —
            opt-in via showProcessing for the In Progress panel. */}
        {showProcessing && w.status === 0 && (
          <div className="proc-overlay pointer-events-none">
            <div className="proc-label">Processing</div>
            <div className="proc-sub">Generating device variants</div>
          </div>
        )}
        {showProcessing && w.status === 5 && (
          <div className="proc-overlay pointer-events-none">
            <div className="proc-label">Pending admin review</div>
            <div className="proc-sub">Usually within a few hours</div>
          </div>
        )}
        {showProcessing && w.status === 6 && (
          <div className="proc-overlay pointer-events-none" style={{ background: 'rgba(176,49,31,0.86)' }}>
            <div className="proc-label">Rejected</div>
            <div className="proc-sub">
              {w.rejection_reason ? w.rejection_reason : 'No reason provided.'}
            </div>
          </div>
        )}
      </div>
    </Link>
  );
}
