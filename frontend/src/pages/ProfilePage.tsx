import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useParams, Link } from 'react-router-dom';
import {
  AiOutlineHeart,
  AiOutlineStar,
  AiOutlineDownload,
  AiOutlineLock,
  AiOutlineEdit,
  AiOutlineCamera,
  AiOutlineCheck,
  AiOutlineClose,
  AiOutlinePicture,
  AiOutlineAppstore,
  AiOutlineThunderbolt,
  AiOutlineLoading3Quarters,
  AiOutlinePlus,
} from 'react-icons/ai';
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
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';
import WallpaperCard from '../components/WallpaperCard';
import CollectionCard from '../components/CollectionCard';
import Pagination from '../components/Pagination';
import AvatarCropModal from '../components/AvatarCropModal';

const PAGE_SIZE = 12;

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
  const { username } = useParams<{ username: string }>();
  const { user: currentUser, updateCoins, updateUser } = useAuthStore();

  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  // ─── Tab state ───
  const [activeTab, setActiveTab] = useState<TabKey>('uploads');
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

  // Generic page-fetch helper that talks to whichever endpoint the tab maps to.
  const fetchList = useCallback(async (
    target: 'pub' | 'inprogress' | ListKey,
    page: number,
  ) => {
    if (!user) return;
    const isMe = currentUser?.id === user.id;
    const stateGetter = (): ListState => {
      if (target === 'pub')        return pubList;
      if (target === 'inprogress') return inProgress;
      if (target === 'favorites')  return favList;
      if (target === 'likes')      return likeList;
      return dlList;
    };
    const current = stateGetter();
    const cursor = current.cursors[page - 1] ?? 0;
    setListFor(target, (p) => ({ ...p, loading: true }));
    try {
      let res;
      const params = cursor > 0 ? { cursor, limit: PAGE_SIZE } : { limit: PAGE_SIZE };
      if (target === 'pub') {
        res = await getUserWallpapers(user.username, { ...params, status: 1 });
      } else if (target === 'inprogress') {
        res = await getUserWallpapers(user.username, { ...params, status: 0 });
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
  }, [user, currentUser?.id]);

  const fetchCollections = useCallback(async () => {
    if (!user) return;
    try {
      const res = await getUserCollections(user.username, { limit: 50 });
      setCollections(res.data.data.items || []);
    } catch {
      toast.error('Failed to load collections');
    } finally {
      setCollectionsLoaded(true);
    }
  }, [user]);

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
    setCollections([]); setCollectionsLoaded(false);
    setTxs([]); setTxPage(1); setTxCursors([0]); setTxTotal(0); setTxLoaded(false);
    setActiveTab('uploads');

    getUserProfile(username)
      .then((res) => setUser(res.data.data))
      .catch(() => toast.error('Failed to load profile'))
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

  // Lazy-load each tab on first activation.
  const onTabChange = (tab: TabKey) => {
    setActiveTab(tab);
    if (tab === 'collections' && !collectionsLoaded) fetchCollections();
    if (tab === 'favorites'  && !favList.loaded)  fetchList('favorites', 1);
    if (tab === 'likes'      && !likeList.loaded) fetchList('likes', 1);
    if (tab === 'downloads'  && !dlList.loaded)   fetchList('downloads', 1);
    if (tab === 'ledger'     && !txLoaded)        fetchLedger(1);
  };

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

  if (loading) return <Spinner />;
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
    <div className="bg-paper text-ink min-h-full px-6 sm:px-10 pt-7 pb-10">
      <PageMeta
        title={`${display}'s profile`}
        description={`Wallpapers, collections, and uploads from ${display} on Wallpaper Exchange.`}
        image={user.avatar_url}
        type="profile"
      />

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
          />
        )}
        {activeTab === 'favorites' && (
          <ListPanel
            listKey="favorites"
            state={favList}
            isOwner={isOwner}
            isPublic={!!user.favorites_public}
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
    <div className="grid grid-cols-1 lg:grid-cols-[120px_1fr_auto] gap-6 pb-6 border-b border-hair">
      {/* Avatar */}
      <div className="relative w-[120px] h-[120px]">
        <div className="w-full h-full rounded-full overflow-hidden bg-paper-2 border border-hair flex items-center justify-center display text-[48px] text-ink">
          {p.user.avatar_url
            ? <img src={p.user.avatar_url} alt="" className="w-full h-full object-cover" />
            : initial}
        </div>
        {p.isOwner && (
          <>
            <button
              onClick={p.onAvatarPick}
              title="Change avatar"
              className="absolute bottom-0 right-0 w-8 h-8 rounded-full bg-ink text-paper flex items-center justify-center border-2 border-paper hover:bg-ink-2 transition-colors"
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

      {/* Identity */}
      <div className="min-w-0">
        <div className="kicker text-muted">
          Contributor · Member since {formatJoined(p.user.created_at)}
        </div>

        {p.editing ? (
          <div className="mt-3 space-y-3 max-w-[480px]">
            <input
              autoFocus
              value={p.editNickname}
              onChange={(e) => p.onEditNicknameChange(e.target.value)}
              maxLength={64}
              placeholder="Nickname"
              className="w-full px-4 py-3 display text-[36px] leading-tight bg-paper text-ink focus:outline-none focus:border-ink"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <textarea
              value={p.editBio}
              onChange={(e) => p.onEditBioChange(e.target.value)}
              maxLength={500}
              rows={3}
              placeholder="Signature, motto, anything you want here"
              className="w-full px-4 py-3 italic-d text-[16px] bg-paper text-ink-2 focus:outline-none focus:border-ink resize-none"
              style={{ border: '1px solid var(--color-hair)' }}
            />
            <div className="flex gap-2">
              <button onClick={p.onSaveProfile} disabled={p.savingProfile || !p.editNickname.trim()}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium disabled:opacity-50">
                <AiOutlineCheck size={13} /> {p.savingProfile ? 'Saving…' : 'Save'}
              </button>
              <button onClick={p.onCancelEdit}
                className="inline-flex items-center gap-1.5 px-4 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2">
                <AiOutlineClose size={13} /> Cancel
              </button>
              <span className="text-[11px] text-muted self-center ml-1">Username @{p.user.username} can't be changed</span>
            </div>
          </div>
        ) : (
          <>
            <h1 className="display text-[40px] sm:text-[48px] leading-tight tracking-[-0.02em] mt-1 text-ink">
              {display}
            </h1>
            <div className="mono text-[12px] text-muted tracking-[0.04em] mt-1.5">
              @{p.user.username}{p.isOwner && p.user.email ? ` · ${p.user.email}` : ''}
            </div>
            {p.user.bio && (
              <p className="display italic-d text-[18px] text-ink-2 mt-3 leading-[1.4]">
                “{p.user.bio}”
              </p>
            )}
          </>
        )}
      </div>

      {/* Right column — balance + actions (owner only) */}
      <div className="flex flex-col items-stretch lg:items-end gap-3 min-w-[200px]">
        {p.isOwner && !p.editing && (
          <div className="bg-ink text-paper p-4 min-w-[200px]">
            <div className="kicker" style={{ color: 'rgba(255,255,255,0.55)' }}>Your balance</div>
            <div className="flex items-baseline gap-2 mt-1.5">
              <span className="w-2.5 h-2.5 rounded-full bg-accent inline-block" />
              <span className="display text-[44px] sm:text-[56px] text-accent leading-none">{p.balance}</span>
              <span className="mono text-[10px] tracking-[0.14em]" style={{ color: 'rgba(255,255,255,0.55)' }}>COINS</span>
            </div>
          </div>
        )}
        {p.isOwner && !p.editing && (
          <div className="flex gap-2 flex-wrap lg:justify-end">
            <button
              onClick={p.onStartEdit}
              className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-hair text-ink text-[12px] font-medium hover:bg-paper-2"
            >
              <AiOutlineEdit size={13} /> Edit profile
            </button>
            <button
              onClick={p.onChangePassword}
              className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-hair text-ink-2 text-[12px] font-medium hover:bg-paper-2"
            >
              Password
            </button>
            <Link
              to="/upload"
              className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full bg-ink text-paper text-[12px] font-medium no-underline hover:bg-ink-2"
            >
              <AiOutlinePlus size={13} /> Upload
            </Link>
          </div>
        )}
      </div>
    </div>
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
  onPubPage: (p: number) => void;
  onInProgressPage: (p: number) => void;
}
function UploadsPanel({ isOwner, inProgress, pub, onPubPage, onInProgressPage }: UploadsPanelProps) {
  const showInProgress = isOwner && inProgress.loaded && inProgress.items.length > 0;
  const inTotal = inProgress.total;
  const pubTotal = pub.total;

  return (
    <div>
      {showInProgress && (
        <section className="mb-8">
          <div className="label-rule mb-3">In progress · {inTotal}</div>
          <p className="text-[12px] text-muted mb-4">
            Generating device variants. Wallpapers appear in the public archive when processing finishes.
          </p>
          <Grid items={inProgress.items} showProcessing />
          <Pagination
            current={inProgress.page}
            total={Math.max(1, Math.ceil(inTotal / PAGE_SIZE))}
            onChange={onInProgressPage}
          />
        </section>
      )}

      <section>
        <div className="label-rule mb-3">
          Published · {pub.items.length === 0 && !pub.loaded ? '…' : `${pub.items.length} of ${pubTotal}`}
        </div>
        {!pub.loaded ? (
          <div className="py-12 flex justify-center"><Spinner /></div>
        ) : pub.items.length === 0 ? (
          <div className="text-center py-20 text-muted text-sm">No published wallpapers yet.</div>
        ) : (
          <>
            <Grid items={pub.items} />
            <Pagination
              current={pub.page}
              total={Math.max(1, Math.ceil(pubTotal / PAGE_SIZE))}
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
}
function CollectionsPanel({ isOwner, user, collections, loaded }: CollectionsPanelProps) {
  return (
    <div>
      <div className="flex items-center justify-between mb-4 flex-wrap gap-3">
        <div className="label-rule flex-1">Created · {collections.length}</div>
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
        <div className="py-12 flex justify-center"><Spinner /></div>
      ) : collections.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">No collections yet.</div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-6">
          {collections.map((c) => (
            <CollectionCard key={c.id} collection={c} curatorHandle={user.username} />
          ))}
        </div>
      )}
    </div>
  );
}

interface ListPanelProps {
  listKey: ListKey;
  state: ListState;
  isOwner: boolean;
  isPublic: boolean;
  onPage: (p: number) => void;
  onTogglePrivacy: () => void;
}
function ListPanel({ listKey, state, isOwner, isPublic, onPage, onTogglePrivacy }: ListPanelProps) {
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
        <div className="py-12 flex justify-center"><Spinner /></div>
      ) : state.items.length === 0 ? (
        <div className="text-center py-20 text-muted text-sm">Nothing here yet.</div>
      ) : (
        <>
          <Grid items={state.items} />
          <Pagination
            current={state.page}
            total={Math.max(1, Math.ceil(state.total / PAGE_SIZE))}
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
        <div className="py-12 flex justify-center"><Spinner /></div>
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

// ─── Grid (4-col, no hover actions; processing overlay opt-in) ───────

function Grid({ items, showProcessing }: { items: Wallpaper[]; showProcessing?: boolean }) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
      {items.map((w) => (
        <div key={w.id} className="relative">
          <WallpaperCard wallpaper={w} fixedAspect hideActions disableModal />
          {showProcessing && w.status === 0 && (
            <div className="proc-overlay pointer-events-none">
              <AiOutlineLoading3Quarters size={18} className="animate-spin" />
              <div className="proc-label">Processing</div>
              <div className="proc-sub">Generating device variants</div>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
