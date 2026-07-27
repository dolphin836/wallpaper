import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import type { CSSProperties } from 'react';
import { useParams, useNavigate, Link, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import type { TFunction } from 'i18next';
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
import MacDynamicChip from '../components/MacDynamicChip';
import { isMacDynamicWallpaper } from '../lib/wallpaperType';
import {
  createWallpaperDetailNavigation,
  wallpaperDetailPath,
  type WallpaperDetailNavigation,
} from '../lib/wallpaperDetailNavigation';
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
import Pagination from '../components/Pagination';
import AvatarCropModal from '../components/AvatarCropModal';
import {
  CollectionListCard,
  CollectionListCardSkeleton,
} from '../components/CollectionListCard';

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

// Match the public .c5-list breakpoints exactly and keep four complete rows.
function calcCollectionPageSize(w: number): number {
  const columns = w > 1180 ? 3 : w > 720 ? 2 : 1;
  return columns * 4;
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

function relativeTime(iso: string, t: TFunction): string {
  const ms = Date.now() - new Date(iso).getTime();
  if (ms < 60_000) return t('time.justNow');
  if (ms < 3_600_000) return t('time.minAgo', { num: Math.floor(ms / 60_000) });
  if (ms < 86_400_000) return t('time.todayAt', { time: new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', hour12: false }) });
  const days = Math.floor(ms / 86_400_000);
  if (days < 30) return days === 1 ? t('time.dayAgo') : t('time.daysAgo', { num: days });
  const months = Math.floor(days / 30);
  return months === 1 ? t('time.monthAgo') : t('time.monthsAgo', { num: months });
}

function dayLabel(iso: string): string {
  // Mono uppercase "MAY 15" for ledger day groupings.
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }).toUpperCase();
}

// Friendly ledger label per transaction type — i18n key lookup. Falls back
// to the raw type when it's not in the table so new types still render
// without code change.
const LEDGER_LABEL_KEYS: Record<string, string> = {
  register_bonus:   'ledger.types.registerBonus',
  upload_reward:    'ledger.types.uploadReward',
  download_cost:    'ledger.types.downloadCost',
  download_earned:  'ledger.types.downloadEarned',
  admin_grant:      'ledger.types.adminGrant',
};

export default function ProfilePage() {
  const { t } = useTranslation('profile');
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
  const [collectionsPageSize, setCollectionsPageSize] = useState<number>(
    () => (typeof window !== 'undefined' ? calcCollectionPageSize(window.innerWidth) : 12),
  );
  useEffect(() => {
    let raf = 0;
    const onResize = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => {
        setGridPageSize(calcGridPageSize(window.innerWidth));
        setCollectionsPageSize(calcCollectionPageSize(window.innerWidth));
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
  // Track how many pages we've earned the cursor for. Pagination
  // disables any page beyond this — the cursor for page N+1 is
  // only known after we've fetched page N.
  const [collectionsMaxReached, setCollectionsMaxReached] = useState(1);

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

  // Generic page-fetch helper that talks to whichever endpoint the
  // tab maps to. Cursor pagination — cursors[N-1] is the cursor for
  // page N. The Pagination control only enables pages we already
  // have a cursor for (or the immediate next page), so a click here
  // can rely on the cursor being present.
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
        res = await getUserWallpapers(user.username, { ...params, status: '0,5' });
      } else if (isMe) {
        if (target === 'favorites') res = await getMyFavorites(params);
        else if (target === 'likes') res = await getMyLikes(params);
        else res = await getMyDownloads(params);
      } else {
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
      toast.error(t('errors.loadFailed'));
      setListFor(target, (p) => ({ ...p, loading: false, loaded: true }));
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, currentUser?.id, gridPageSize, t]);

  // Collections use their own cursor table because their responsive
  // list has a different column count from wallpaper grids.
  const collectionsCursorsRef = useRef<number[]>([0]);
  const previousCollectionsPageSizeRef = useRef(collectionsPageSize);
  const fetchCollections = useCallback(async (page = 1) => {
    if (!user) return;
    const cursor = collectionsCursorsRef.current[page - 1] ?? 0;
    try {
      const params = cursor > 0
        ? { cursor, limit: collectionsPageSize }
        : { limit: collectionsPageSize };
      const res = await getUserCollections(user.username, params);
      const data = res.data.data as { items: Collection[]; next_cursor: number; has_more: boolean; total?: number };
      const items = data.items || [];
      setCollections(items);
      setCollectionsPage(page);
      if (typeof data.total === 'number' && data.total > 0) {
        setCollectionsTotal(data.total);
      } else if (data.has_more) {
        setCollectionsTotal((page * collectionsPageSize) + 1);
      } else {
        setCollectionsTotal((page - 1) * collectionsPageSize + items.length);
      }
      collectionsCursorsRef.current = collectionsCursorsRef.current.slice(0, page);
      if (data.has_more && data.next_cursor > 0) {
        collectionsCursorsRef.current[page] = data.next_cursor;
      }
      setCollectionsMaxReached((prev) => Math.max(prev, collectionsCursorsRef.current.length));
    } catch {
      toast.error(t('errors.loadCollectionsFailed'));
    } finally {
      setCollectionsLoaded(true);
    }
  }, [user, collectionsPageSize, t]);

  // A collection breakpoint change invalidates the cursor chain because
  // every cursor was produced for the previous limit. Restart at page one
  // and request exactly four rows for the new column count.
  useEffect(() => {
    if (previousCollectionsPageSizeRef.current === collectionsPageSize) return;
    previousCollectionsPageSizeRef.current = collectionsPageSize;
    collectionsCursorsRef.current = [0];
    setCollections([]);
    setCollectionsPage(1);
    setCollectionsTotal(0);
    setCollectionsMaxReached(1);
    setCollectionsLoaded(false);
    if (activeTab === 'collections' && user) {
      void fetchCollections(1);
    }
  }, [activeTab, collectionsPageSize, fetchCollections, user]);

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
      toast.error(t('errors.loadLedgerFailed'));
    } finally {
      setTxLoading(false);
    }
  }, [txCursors, t]);

  // ─── Initial load ───
  useEffect(() => {
    if (!username) return;
    setLoading(true);
    setPubList(emptyList()); setInProgress(emptyList());
    setFavList(emptyList()); setLikeList(emptyList()); setDlList(emptyList());
    setCollections([]); setCollectionsLoaded(false); setCollectionsPage(1); setCollectionsTotal(0); setCollectionsMaxReached(1); collectionsCursorsRef.current = [0];
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
    if (file.size > 10 * 1024 * 1024) { toast.error(t('avatar.tooLarge')); return; }
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
      toast.success(t('avatar.updated'));
    } catch { toast.error(t('avatar.uploadFailed')); }
  };
  const startEdit = () => {
    setEditNickname(user?.nickname || '');
    setEditBio(user?.bio || '');
    setEditingProfile(true);
  };
  const saveProfile = async () => {
    const nickname = editNickname.trim();
    if (!nickname) { toast.error(t('edit.nicknameRequired')); return; }
    if (nickname.length > 64) { toast.error(t('edit.nicknameTooLong')); return; }
    const bio = editBio.trim();
    if (bio.length > 500) { toast.error(t('edit.bioTooLong')); return; }
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
      toast.success(t('edit.updated'));
    } catch { toast.error(t('edit.saveFailed')); } finally { setSavingProfile(false); }
  };
  const handleChangePassword = async () => {
    if (newPw.length < 8) { toast.error(t('password.tooShort')); return; }
    setSavingPw(true);
    try {
      await changePassword({ old_password: oldPw, new_password: newPw });
      toast.success(t('password.changed'));
      setShowPasswordModal(false); setOldPw(''); setNewPw('');
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } } };
      const msg = e?.response?.data?.message;
      toast.error(msg === 'wrong password' ? t('password.wrongCurrent') : t('password.changeFailed'));
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
      toast.success(next
        ? t('privacy.nowPublic', { list: t(`listsLower.${list}`) })
        : t('privacy.nowPrivate', { list: t(`listsLower.${list}`) }));
    } catch { toast.error(t('errors.privacyFailed')); }
  };

  if (loading) {
    return (
      <div className="profile-page min-h-full">
        <div className="profile-mesh" aria-hidden />
        <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 pt-10 pb-16">
          {/* Hero placeholder — matches profile-hero's 3-col layout */}
          <div className="profile-hero">
            <div className="profile-hero-avatar">
              <div className="profile-hero-avatar-frame skeleton-card" />
            </div>
            <div className="profile-hero-id">
              <div className="skeleton-card" style={{ width: 220, height: 10, borderRadius: 4 }} />
              <div className="skeleton-card mt-3" style={{ width: '45%', height: 42, borderRadius: 6 }} />
              <div className="skeleton-card mt-3" style={{ width: 180, height: 10, borderRadius: 4 }} />
              <div className="skeleton-card mt-4" style={{ width: '60%', height: 16, borderRadius: 4 }} />
            </div>
            <div className="hidden lg:block">
              <div className="skeleton-card" style={{ width: 240, height: 110, borderRadius: 18 }} />
            </div>
          </div>
          {/* Tab row placeholder */}
          <div className="flex gap-6 mt-6 pb-3 border-b border-hair">
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="skeleton-card" style={{ width: 90, height: 14, borderRadius: 4, animationDelay: `${i * 60}ms` }} />
            ))}
          </div>
          {/* Grid placeholder — same chrome as live wallpaper grid */}
          <div className="mt-7">
            <div className="skeleton-card mb-4" style={{ width: 200, height: 10, borderRadius: 4 }} />
            <ProfileWallpapersSkeleton />
          </div>
        </main>
      </div>
    );
  }
  if (!user && error) return <ErrorState />;
  if (!user) return <EmptyState message={t('notFound')} />;

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
    { key: 'uploads',     label: t('tabs.uploads') },
    { key: 'collections', label: t('tabs.collections') },
    { key: 'favorites',   label: t('tabs.favorites') },
    { key: 'likes',       label: t('tabs.likes') },
    { key: 'downloads',   label: t('tabs.downloads'), ownerOnly: true },
    { key: 'ledger',      label: t('tabs.ledger'),    ownerOnly: true },
  ];
  const tabs = isOwner ? allTabs : allTabs.filter((t) => !t.ownerOnly);

  return (
    <div className="profile-page min-h-full">
      <div className="profile-mesh" aria-hidden />
      <PageMeta
        title={t('meta.pageTitle', { name: display })}
        description={t('meta.pageDesc', { name: display })}
        image={user.avatar_url}
        type="profile"
      />

      <main className="relative z-10 max-w-[1600px] mx-auto px-6 sm:px-10 lg:px-14 pt-10 pb-16">

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
            maxReachable={collectionsMaxReached}
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
            maxReachable={txCursors.length}
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
            <div className="kicker text-muted mb-3">{t('password.kicker')}</div>
            <input
              type="password" placeholder={t('password.currentPlaceholder')}
              value={oldPw} onChange={(e) => setOldPw(e.target.value)}
              className="w-full px-3.5 py-3 bg-paper text-[14px] mb-2"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <input
              type="password" placeholder={t('password.newPlaceholder')}
              value={newPw} onChange={(e) => setNewPw(e.target.value)}
              className="w-full px-3.5 py-3 bg-paper text-[14px]"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <div className="flex justify-end gap-2 mt-3">
              <button
                onClick={() => setShowPasswordModal(false)}
                className="px-3.5 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2"
              >{t('password.cancel')}</button>
              <button
                onClick={handleChangePassword}
                disabled={savingPw}
                className="px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50"
              >{savingPw ? t('password.saving') : t('password.confirm')}</button>
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
  const { t } = useTranslation('profile');
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
              title={t('avatar.change')}
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
          {t('hero.kicker', { date: formatJoined(p.user.created_at) })}
        </div>

        {p.editing ? (
          <div className="mt-3 space-y-3 max-w-[520px]">
            <input
              autoFocus
              value={p.editNickname}
              onChange={(e) => p.onEditNicknameChange(e.target.value)}
              maxLength={64}
              placeholder={t('edit.nicknamePlaceholder')}
              className="profile-hero-edit-name display"
            />
            <textarea
              value={p.editBio}
              onChange={(e) => p.onEditBioChange(e.target.value)}
              maxLength={500}
              rows={3}
              placeholder={t('edit.bioPlaceholder')}
              className="profile-hero-edit-bio"
            />
            <div className="flex gap-2 items-center flex-wrap">
              <button onClick={p.onSaveProfile} disabled={p.savingProfile || !p.editNickname.trim()}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50 hover:bg-ink-2 transition-colors">
                <AiOutlineCheck size={13} /> {p.savingProfile ? t('edit.saving') : t('edit.save')}
              </button>
              <button onClick={p.onCancelEdit}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2 transition-colors">
                <AiOutlineClose size={13} /> {t('edit.cancel')}
              </button>
              <span className="text-[11px] text-muted">
                {t('edit.usernameImmutable', { username: p.user.username })}
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
            title={t('hero.coinLedger')}
            className="profile-hero-balance no-underline"
          >
            <div className="profile-hero-balance-kicker">{t('hero.balance')}</div>
            <div className="profile-hero-balance-row">
              <span className="profile-hero-balance-coin" aria-hidden />
              <span className="profile-hero-balance-num">{p.balance}</span>
              <span className="profile-hero-balance-unit">{t('hero.coins')}</span>
            </div>
          </Link>
        )}
        {p.isOwner && !p.editing && (
          <div className="profile-hero-actions">
            <button
              onClick={p.onStartEdit}
              className="profile-hero-pill"
            >
              <AiOutlineEdit size={13} /> {t('hero.editProfile')}
            </button>
            <button
              onClick={p.onChangePassword}
              className="profile-hero-pill"
            >
              {t('hero.password')}
            </button>
            <Link
              to="/upload"
              className="profile-hero-pill is-primary no-underline"
            >
              <AiOutlinePlus size={13} /> {t('hero.upload')}
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
    <div className="ptabs mt-6 flex-wrap">
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
  const { t } = useTranslation('profile');
  const showInProgress = isOwner && inProgress.loaded && inProgress.items.length > 0;
  const inTotal = inProgress.total;
  const pubTotal = pub.total;

  return (
    <div>
      {showInProgress && (
        <section className="mb-8">
          <div className="label-rule mb-3">{t('uploads.pending', { num: inTotal })}</div>
          <p className="text-[12px] text-muted mb-4">
            {t('uploads.pendingDesc')}
          </p>
          <Grid items={inProgress.items} showProcessing />
          <Pagination
            current={inProgress.page}
            total={Math.max(1, Math.ceil(inTotal / pageSize))}
            maxReachable={inProgress.cursors.length}
            onChange={onInProgressPage}
          />
        </section>
      )}

      <section>
        <div className="label-rule mb-3">
          {t('uploads.published')} · {pub.items.length === 0 && !pub.loaded ? '…' : t('uploads.countOf', { shown: pub.items.length, total: pubTotal })}
        </div>
      {!pub.loaded ? (
        <ProfileWallpapersSkeleton />
      ) : pub.items.length === 0 ? (
        <EmptyState
          title={t('uploads.emptyTitle')}
          message={t('uploads.emptyMessage')}
        />
      ) : (
          <>
            <Grid items={pub.items} />
            <Pagination
              current={pub.page}
              total={Math.max(1, Math.ceil(pubTotal / pageSize))}
              maxReachable={pub.cursors.length}
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
  maxReachable: number;
  onPage: (p: number) => void;
}
function CollectionsPanel({ isOwner, collections, loaded, page, total, pageSize, maxReachable, onPage }: CollectionsPanelProps) {
  const { t } = useTranslation('profile');
  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div className="label-rule flex-1">
          {t('collections.created')} · {loaded ? total : '…'}
        </div>
        {isOwner && (
          <Link
            to="/collections"
            className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium no-underline hover:bg-ink-2"
          >
            <AiOutlinePlus size={13} /> {t('collections.new')}
          </Link>
        )}
      </div>
      {!loaded ? (
        <ProfileCollectionsSkeleton count={pageSize} />
      ) : collections.length === 0 ? (
        <EmptyState
          title={t('collections.emptyTitle')}
          message={t('collections.emptyMessage')}
          actionLabel={isOwner ? t('collections.new') : undefined}
          actionHref={isOwner ? '/collections' : undefined}
        />
      ) : (
        <>
          <div className="c5-list">
            {collections.map((c, index) => (
              <CollectionListCard
                key={c.id}
                collection={c}
                eager={page === 1 && index === 0}
              />
            ))}
          </div>
          <Pagination
            current={page}
            total={Math.max(1, Math.ceil(total / pageSize))}
            maxReachable={maxReachable}
            onChange={onPage}
          />
        </>
      )}
    </div>
  );
}

/* Skeletons matching the live grids — same chrome (dev-spec-card
   for wallpapers, c5-card for collections) so loading state and
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
    <div className="c5-list" aria-hidden>
      {Array.from({ length: count }).map((_, i) => (
        <CollectionListCardSkeleton key={i} />
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
  const { t } = useTranslation('profile');
  const heading = useMemo(() => `${t(`lists.${listKey}`)} · ${state.total}`, [listKey, state.total, t]);

  if (state.hidden) {
    return (
      <div
        className="text-center py-16 px-6"
        style={{ background: 'var(--color-paper-2)', border: '1px dashed var(--color-hair)' }}
      >
        <AiOutlineLock size={28} className="mx-auto text-ink-2 mb-3" />
        <div className="display text-[24px] leading-tight">{t('lists.hiddenTitle')}</div>
        <p className="text-[13px] text-muted mt-2 max-w-[420px] mx-auto">
          {t('lists.hiddenMessage', { list: t(`listsLower.${listKey}`) })}
        </p>
      </div>
    );
  }

  return (
    <div>
      {isOwner && (
        <PrivacyNotice listKey={listKey} isPublic={isPublic} onToggle={onTogglePrivacy} />
      )}

      <div className="label-rule mt-5 mb-3">{heading}</div>

      {!state.loaded ? (
        <ProfileWallpapersSkeleton />
      ) : state.items.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">{t('lists.empty')}</div>
      ) : (
        <>
          <Grid items={state.items} />
          <Pagination
            current={state.page}
            total={Math.max(1, Math.ceil(state.total / pageSize))}
            maxReachable={state.cursors.length}
            onChange={onPage}
          />
        </>
      )}
    </div>
  );
}

function PrivacyNotice({ listKey, isPublic, onToggle }: { listKey: ListKey; isPublic: boolean; onToggle: () => void }) {
  const { t } = useTranslation('profile');
  const list = t(`listsLower.${listKey}`);
  return (
    <div className="priv-notice">
      <div className="priv-icon"><AiOutlineLock size={16} /></div>
      <div>
        <div className="priv-title">{isPublic ? t('privacy.titlePublic', { list }) : t('privacy.titlePrivate', { list })}</div>
        <div className="priv-sub">
          {isPublic
            ? t('privacy.subPublic')
            : t('privacy.subPrivate')}
        </div>
      </div>
      <button
        onClick={onToggle}
        className="inline-flex items-center gap-1.5 px-3.5 py-2 rounded-full bg-paper border border-ink text-ink text-[12px] font-medium hover:bg-paper-2 transition-colors whitespace-nowrap"
      >
        {isPublic ? t('privacy.makePrivate') : t('privacy.makePublic')}
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
  maxReachable: number;
  onPage: (p: number) => void;
}
function LedgerSkeleton() {
  return (
    <div className="space-y-2">
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} className="ledger-row skeleton-card" style={{ height: 62, animationDelay: `${i * 60}ms` }} />
      ))}
    </div>
  );
}

const LEDGER_GLYPH: Record<string, string> = {
  register_bonus:  '✨',
  upload_reward:   '↑',
  download_cost:   '↓',
  download_earned: '★',
  admin_grant:     '+',
};

function LedgerPanel({ txs, page, total, loading, balance, maxReachable, onPage }: LedgerPanelProps) {
  const { t } = useTranslation('profile');
  // Aggregate stats over the visible transactions.
  const earned = txs.filter((t) => t.amount > 0).reduce((s, t) => s + t.amount, 0);
  const spent = txs.filter((t) => t.amount < 0).reduce((s, t) => s + Math.abs(t.amount), 0);

  // Group entries by day for the timeline read.
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
      {/* Summary cards — Balance leads with the warm-gold pill
          recipe (matches the hero balance + navbar pill), the
          rest are paper-faced stats. */}
      <div className="ledger-summary">
        <div className="ledger-stat is-balance">
          <div className="ledger-stat-kicker">{t('ledger.balance')}</div>
          <div className="ledger-stat-row">
            <span className="ledger-stat-coin" aria-hidden />
            <span className="ledger-stat-num">{balance}</span>
          </div>
          <div className="ledger-stat-sub">{t('ledger.lifetime')}</div>
        </div>
        <div className="ledger-stat">
          <div className="ledger-stat-kicker">{t('ledger.earned')}</div>
          <div className="ledger-stat-num is-earn">+{earned}</div>
          <div className="ledger-stat-sub">{t('ledger.thisPage')}</div>
        </div>
        <div className="ledger-stat">
          <div className="ledger-stat-kicker">{t('ledger.spent')}</div>
          <div className="ledger-stat-num is-spend">−{spent}</div>
          <div className="ledger-stat-sub">{t('ledger.thisPage')}</div>
        </div>
        <div className="ledger-stat">
          <div className="ledger-stat-kicker">{t('ledger.nextEarn')}</div>
          <div className="ledger-stat-num">+1</div>
          <div className="ledger-stat-sub">{t('ledger.perUpload')}</div>
        </div>
      </div>

      <div className="label-rule mt-9 mb-4">{t('ledger.recent')}</div>

      {loading && txs.length === 0 ? (
        <LedgerSkeleton />
      ) : txs.length === 0 ? (
        <EmptyState
          title={t('ledger.emptyTitle')}
          message={t('ledger.emptyMessage')}
        />
      ) : (
        <>
          <div className="ledger-list">
            {grouped.map((g) => (
              <div key={g.day} className="ledger-day">
                <div className="ledger-day-label">{g.day}</div>
                <div className="ledger-day-rows">
                  {g.rows.map((tx) => {
                    const labelKey = LEDGER_LABEL_KEYS[tx.tx_type];
                    const label = labelKey ? t(labelKey) : (tx.description || tx.tx_type);
                    const glyph = LEDGER_GLYPH[tx.tx_type] || '·';
                    const isEarn = tx.amount > 0;
                    return (
                      <div key={tx.id} className={`ledger-row ${isEarn ? 'is-earn' : 'is-spend'}`}>
                        <span className="ledger-row-glyph" aria-hidden>{glyph}</span>
                        <div className="ledger-row-id">
                          <div className="ledger-row-label">{label}</div>
                          {tx.ref_id > 0 && (
                            <Link
                              to={`/wallpaper/${tx.ref_id}`}
                              className="ledger-row-ref"
                              onClick={(e) => e.stopPropagation()}
                            >
                              № {String(tx.ref_id).padStart(3, '0')} →
                            </Link>
                          )}
                        </div>
                        <span className="ledger-row-amount">
                          {isEarn ? '+' : ''}{tx.amount}
                        </span>
                        <span className="ledger-row-time">
                          {relativeTime(tx.created_at, t)}
                        </span>
                      </div>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
          <Pagination
            current={page}
            total={Math.max(1, Math.ceil(total / PAGE_SIZE))}
            maxReachable={maxReachable}
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
  const detailNavigation = useMemo(
    () => createWallpaperDetailNavigation(items),
    [items],
  );
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
      {items.map((w, i) => (
        <ProfileWallpaperTile
          key={w.id}
          w={w}
          index={i}
          showProcessing={!!showProcessing}
          detailNavigation={detailNavigation}
        />
      ))}
    </div>
  );
}

function ProfileWallpaperTile({
  w, index, showProcessing, detailNavigation,
}: {
  w: Wallpaper;
  index: number;
  showProcessing: boolean;
  detailNavigation?: WallpaperDetailNavigation;
}) {
  const { t } = useTranslation('profile');
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
  const isPublished = w.status === 1;
  const detailLabel = w.title || t('tile.altFallback', { id: w.id });
  return (
    <article
      className="dev-spec-card"
      style={{ animationDelay: `${Math.min(index, 8) * 24}ms` }}
    >
      <div className="dev-spec-card-screen" style={{ aspectRatio: '3 / 2' }}>
        <img
          src={w.preview_url || w.thumb_url}
          alt=""
          aria-hidden
          loading="lazy"
          className="dev-spec-card-img"
          style={{ backgroundColor: w.dominant_color || undefined }}
        />
        <Link
          to={wallpaperDetailPath(w)}
          state={{ background: location, initialWallpaper: w, detailNavigation }}
          className="tile-detail-link"
          aria-label={detailLabel}
        />
        {(resLabel || isVideo || w.is_dynamic || w.is_ai_generated) && (
          <div className="absolute top-2.5 left-2.5 z-[3] flex gap-1 flex-wrap max-w-[calc(100%-20px)] pointer-events-none">
            {resLabel && <span className="tile-chip is-resolution">{resLabel}</span>}
            {(isVideo || w.is_dynamic) && (
              <span className="tile-chip is-live">
                <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden><path d="M8 5v14l11-7z" /></svg>
                {t('tile.live')}
              </span>
            )}
            {isMacDynamicWallpaper(w) && <MacDynamicChip />}
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
              onClick={acts.handleFavorite}
              disabled={acts.favLoading}
              className={`t-act ${acts.favorited ? 'is-favorited' : ''}`}
              title={acts.favorited ? t('tile.unfavorite') : t('tile.favorite')}
            >
              {acts.favLoading
                ? <AiOutlineLoading3Quarters size={15} className="animate-spin" />
                : acts.favorited
                  ? <AiFillStar size={15} />
                  : <AiOutlineStar size={15} />}
            </button>
            <button
              type="button"
              onClick={acts.handleLike}
              disabled={acts.likeLoading}
              className={`t-act ${acts.liked ? 'is-liked' : ''}`}
              title={acts.liked ? t('tile.unlike') : t('tile.like')}
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
                onClick={acts.handleDownload}
                disabled={acts.downloading}
                className={`t-act ${acts.downloaded ? 'is-downloaded' : ''} ${acts.downloading ? 'is-downloading' : ''}`}
                title={acts.downloadTitle}
                style={{ ['--download-progress' as string]: acts.downloadProgress ?? 0.08 } as CSSProperties}
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
            <div className="proc-label">{t('tile.processing')}</div>
            <div className="proc-sub">{t('tile.processingSub')}</div>
          </div>
        )}
        {showProcessing && w.status === 5 && (
          <div className="proc-overlay pointer-events-none">
            <div className="proc-label">{t('tile.pendingReview')}</div>
            <div className="proc-sub">{t('tile.pendingReviewSub')}</div>
          </div>
        )}
        {showProcessing && w.status === 6 && (
          <div className="proc-overlay pointer-events-none" style={{ background: 'rgba(176,49,31,0.86)' }}>
            <div className="proc-label">{t('tile.rejected')}</div>
            <div className="proc-sub">
              {w.rejection_reason ? w.rejection_reason : t('tile.noReason')}
            </div>
          </div>
        )}
      </div>
    </article>
  );
}
