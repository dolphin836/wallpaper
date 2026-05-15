import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { useParams, Link } from 'react-router-dom';
import PageMeta from '../components/PageMeta';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture, AiOutlineEdit, AiOutlineCamera, AiOutlineLock, AiOutlineCheck, AiOutlineClose, AiOutlineApple } from 'react-icons/ai';
import { MdDevices } from 'react-icons/md';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection, CoinTransaction } from '../types';
import { getUserProfile, getUserWallpapers, getUserCollections, getMyFavorites, getMyLikes, getMyDownloads, getMyCoins, getCoinTransactions, updateProfile, uploadAvatar, changePassword } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';
import AvatarCropModal from '../components/AvatarCropModal';

type TabKey = 'coins' | 'wallpapers' | 'collections' | 'favorites' | 'likes' | 'downloads';
type WallpaperTabKey = 'wallpapers' | 'favorites' | 'likes' | 'downloads';

interface WallpaperTab {
  items: Wallpaper[];
  page: number;
  // cursors[i] = the `cursor` value to send when fetching page i+1.
  // cursors[0] is always 0. cursors[N] is set after page N is fetched, ready for page N+1.
  cursors: number[];
  total: number;
  loaded: boolean;
}

// Page size matches the grid layout used in WallpaperGrid (sizeMode="md"):
//   grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6
// Target ~4 rows per page based on the current viewport.
function gridColsForWidth(width: number): number {
  if (width >= 1024) return 6;
  if (width >= 768) return 5;
  if (width >= 640) return 4;
  return 3;
}

function computePageSize(width: number): number {
  return gridColsForWidth(width) * 4;
}

function useViewportPageSize(): number {
  const [size, setSize] = useState(() =>
    typeof window === 'undefined' ? 20 : computePageSize(window.innerWidth),
  );
  useEffect(() => {
    let raf = 0;
    const onResize = () => {
      cancelAnimationFrame(raf);
      raf = requestAnimationFrame(() => setSize(computePageSize(window.innerWidth)));
    };
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      cancelAnimationFrame(raf);
    };
  }, []);
  return size;
}

// Returns the page-number sequence with ellipses, e.g. for page=5, total=10: [1, '...', 4, 5, 6, '...', 10].
// Always shows first + last + a small window around the current page.
function paginationItems(page: number, total: number): (number | 'ellipsis')[] {
  const set = new Set<number>([1, total]);
  for (let i = page - 1; i <= page + 1; i++) {
    if (i > 1 && i < total) set.add(i);
  }
  const sorted = Array.from(set).sort((a, b) => a - b);
  const out: (number | 'ellipsis')[] = [];
  let prev = 0;
  for (const p of sorted) {
    if (prev > 0 && p - prev > 1) out.push('ellipsis');
    out.push(p);
    prev = p;
  }
  return out;
}

function Pagination({ page, totalPages, onChange }: { page: number; totalPages: number; onChange: (p: number) => void }) {
  if (totalPages <= 1) return null;
  const items = paginationItems(page, totalPages);
  return (
    <nav className="flex items-center justify-center gap-1.5 mt-8" aria-label="Pagination">
      <button
        onClick={() => onChange(page - 1)}
        disabled={page <= 1}
        className="px-3 py-1.5 text-sm rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple hover:border-ws-purple/30 disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:text-ws-muted disabled:hover:border-ws-border transition-colors"
        aria-label="Previous page"
      >
        &larr;
      </button>
      {items.map((it, i) =>
        it === 'ellipsis' ? (
          <span key={`e${i}`} className="px-1 text-sm text-ws-muted dark:text-ws-dark-muted select-none">…</span>
        ) : (
          <button
            key={it}
            onClick={() => onChange(it)}
            aria-current={it === page ? 'page' : undefined}
            className={`min-w-9 px-3 py-1.5 text-sm rounded-lg border transition-colors ${
              it === page
                ? 'border-ws-purple bg-ws-purple text-white'
                : 'border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple hover:border-ws-purple/30'
            }`}
          >
            {it}
          </button>
        ),
      )}
      <button
        onClick={() => onChange(page + 1)}
        disabled={page >= totalPages}
        className="px-3 py-1.5 text-sm rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple hover:border-ws-purple/30 disabled:opacity-30 disabled:cursor-not-allowed disabled:hover:text-ws-muted disabled:hover:border-ws-border transition-colors"
        aria-label="Next page"
      >
        &rarr;
      </button>
    </nav>
  );
}

const TX_LABELS: Record<string, { label: string; color: string }> = {
  register_bonus: { label: 'Registration Bonus', color: 'text-green-600' },
  upload_reward: { label: 'Upload Reward', color: 'text-green-600' },
  download_cost: { label: 'Download Cost', color: 'text-red-500' },
  download_earned: { label: 'Download Earned', color: 'text-green-600' },
};

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleString();
}

// Physical pixel resolution of the user's primary screen. Same logic the home
// feed uses for its My-Device filter; centralised here so the Downloads tab
// filter pipes the exact same values to the API.
function getScreenResolution() {
  const dpr = window.devicePixelRatio || 1;
  return {
    width: Math.round(window.screen.width * dpr),
    height: Math.round(window.screen.height * dpr),
  };
}

const isMac = /Macintosh|Mac OS X/i.test(navigator.userAgent);

export default function ProfilePage() {
  const { username } = useParams<{ username: string }>();
  const { user: currentUser, updateCoins } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [collections, setCollections] = useState<Collection[]>([]);

  const isOwnProfile = currentUser?.username === username;
  const [activeTab, setActiveTab] = useState<TabKey>(isOwnProfile ? 'coins' : 'wallpapers');

  const pageSize = useViewportPageSize();

  const emptyTab = (): WallpaperTab => ({ items: [], page: 1, cursors: [0], total: 0, loaded: false });
  const [tabs, setTabs] = useState<Record<WallpaperTabKey, WallpaperTab>>({
    wallpapers: emptyTab(),
    favorites: emptyTab(),
    likes: emptyTab(),
    downloads: emptyTab(),
  });
  // Loader callbacks read from tabs via this ref to avoid recreating on every state change.
  const tabsRef = useRef(tabs);
  tabsRef.current = tabs;

  const [tabLoading, setTabLoading] = useState(false);

  // Filters for the Downloads tab (parity with the home-feed My-Device / macOS
  // toggles). Mutually exclusive: turning one on turns the other off, same as
  // HomePage. Kept as refs too so fetchWallpaperPage doesn't need to re-create
  // on every toggle.
  const [dlDeviceFilter, setDlDeviceFilter] = useState(false);
  const [dlMacFilter, setDlMacFilter] = useState(false);
  const dlFiltersRef = useRef({ device: false, mac: false });
  dlFiltersRef.current = { device: dlDeviceFilter, mac: dlMacFilter };
  const screen = useMemo(() => getScreenResolution(), []);

  const [transactions, setTransactions] = useState<CoinTransaction[]>([]);
  const [txPage, setTxPage] = useState(1);
  const [txCursors, setTxCursors] = useState<number[]>([0]);
  const txCursorsRef = useRef(txCursors);
  txCursorsRef.current = txCursors;
  const [txTotal, setTxTotal] = useState(0);
  const [txLoading, setTxLoading] = useState(false);
  const [txLoaded, setTxLoaded] = useState(false);

  const loadCoins = useCallback(async () => {
    try {
      const res = await getMyCoins();
      updateCoins(res.data.data.coins);
    } catch {
      // silent
    }
  }, [updateCoins]);

  const fetchTransactionsPage = useCallback(async (targetPage: number) => {
    setTxLoading(true);
    try {
      const cursors = txCursorsRef.current;
      const cursor = cursors[targetPage - 1] ?? 0;
      const res = await getCoinTransactions({ cursor: cursor > 0 ? cursor : undefined, limit: pageSize });
      const data = res.data.data;
      const items = data?.items ?? [];
      const hasMore = data?.has_more ?? false;
      const nextCursor = data?.next_cursor ?? 0;
      setTransactions(items);
      setTxPage(targetPage);
      setTxTotal(data?.total ?? 0);
      setTxCursors((prev) => {
        const next = prev.slice(0, targetPage);
        if (hasMore && nextCursor > 0) next[targetPage] = nextCursor;
        return next;
      });
      setTxLoaded(true);
    } catch {
      toast.error('Failed to load transactions');
    } finally {
      setTxLoading(false);
    }
  }, [pageSize]);

  const fetchWallpaperPage = useCallback(async (key: WallpaperTabKey, targetPage: number) => {
    if (!username) return;
    setTabLoading(true);
    try {
      const current = tabsRef.current[key];
      const cursor = current.cursors[targetPage - 1] ?? 0;
      const params: { cursor?: number; limit: number } = { limit: pageSize };
      if (cursor > 0) params.cursor = cursor;

      let res;
      if (key === 'wallpapers') {
        res = await getUserWallpapers(username, params);
      } else if (key === 'favorites') {
        res = await getMyFavorites(params);
      } else if (key === 'downloads') {
        // Layer the resolution / macOS filters on top of cursor + limit.
        // Mac wallpapers and resolution filters are mutually exclusive in the
        // home UI, mirror the same constraint here.
        const dlParams: Parameters<typeof getMyDownloads>[0] = { ...params };
        const f = dlFiltersRef.current;
        if (f.mac) {
          dlParams.dynamic_only = true;
        } else if (f.device) {
          dlParams.device_width = screen.width;
          dlParams.device_height = screen.height;
          if (isMac) dlParams.include_dynamic = true;
        }
        res = await getMyDownloads(dlParams);
      } else {
        res = await getMyLikes(params);
      }
      const data = res.data.data;
      const items = data?.items ?? [];
      const hasMore = data?.has_more ?? false;
      const nextCursor = data?.next_cursor ?? 0;
      const total = data?.total ?? 0;
      setTabs((prev) => {
        const prevTab = prev[key];
        const cursors = prevTab.cursors.slice(0, targetPage);
        if (hasMore && nextCursor > 0) cursors[targetPage] = nextCursor;
        return {
          ...prev,
          [key]: {
            items,
            page: targetPage,
            cursors,
            total,
            loaded: true,
          },
        };
      });
    } catch {
      toast.error('Failed to load data');
      setTabs((prev) => ({ ...prev, [key]: { ...prev[key], loaded: true } }));
    } finally {
      setTabLoading(false);
    }
  }, [username, pageSize]);

  useEffect(() => {
    if (!username) return;
    setLoading(true);
    setTabs({
      wallpapers: emptyTab(),
      favorites: emptyTab(),
      likes: emptyTab(),
      downloads: emptyTab(),
    });
    setTransactions([]);
    setTxPage(1);
    setTxCursors([0]);
    setTxTotal(0);
    setTxLoaded(false);

    const own = currentUser?.username === username;
    setActiveTab(own ? 'coins' : 'wallpapers');

    Promise.all([
      getUserProfile(username),
      getUserWallpapers(username, { limit: pageSize }),
      getUserCollections(username, { limit: 50 }),
    ])
      .then(([profileRes, wpRes, colRes]) => {
        setUser(profileRes.data.data);
        const data = wpRes.data.data;
        const items = data?.items ?? [];
        const hasMore = data?.has_more ?? false;
        const nextCursor = data?.next_cursor ?? 0;
        const total = data?.total ?? 0;
        setTabs((prev) => {
          const cursors: number[] = [0];
          if (hasMore && nextCursor > 0) cursors[1] = nextCursor;
          return {
            ...prev,
            wallpapers: { items, page: 1, cursors, total, loaded: true },
          };
        });
        setCollections(colRes.data.data?.items || []);
      })
      .catch(() => toast.error('Failed to load profile'))
      .finally(() => setLoading(false));

    if (own) {
      loadCoins();
      fetchTransactionsPage(1);
    }
    // Intentionally only re-run when username changes. pageSize changes are handled by the dedicated effect below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [username]);

  // When the viewport changes the page size, drop cached pages on loaded tabs and refetch page 1
  // (cached cursors were sized for the old page size and are no longer valid offsets).
  const prevPageSizeRef = useRef(pageSize);
  useEffect(() => {
    if (prevPageSizeRef.current === pageSize) return;
    prevPageSizeRef.current = pageSize;
    if (!username) return;

    (Object.keys(tabsRef.current) as WallpaperTabKey[]).forEach((key) => {
      if (tabsRef.current[key].loaded) {
        fetchWallpaperPage(key, 1);
      }
    });
    if (txLoaded) {
      fetchTransactionsPage(1);
    }
    // We intentionally don't include tabs/transactions in deps — we read fresh state via refs.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pageSize, username, fetchWallpaperPage, fetchTransactionsPage]);

  // Toggling either downloads filter resets that tab to page 1 with the new
  // server-side filter applied. Only fires after the tab has been loaded once
  // (no point hitting the API for a tab the user hasn't visited).
  useEffect(() => {
    if (!username || !tabsRef.current.downloads.loaded) return;
    fetchWallpaperPage('downloads', 1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dlDeviceFilter, dlMacFilter]);

  const toggleDlDeviceFilter = () => {
    setDlDeviceFilter((p) => {
      if (!p) setDlMacFilter(false);
      return !p;
    });
  };

  const toggleDlMacFilter = () => {
    setDlMacFilter((p) => {
      if (!p) setDlDeviceFilter(false);
      return !p;
    });
  };

  const handleTabChange = (tab: TabKey) => {
    setActiveTab(tab);
    if ((tab === 'favorites' || tab === 'likes' || tab === 'downloads') && !tabs[tab].loaded) {
      fetchWallpaperPage(tab, 1);
    }
    if (tab === 'coins' && !txLoaded) {
      loadCoins();
      fetchTransactionsPage(1);
    }
  };

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

  if (loading) return <Spinner />;
  if (!user) return <EmptyState message="User not found." />;

  const currentTab = (activeTab === 'coins' || activeTab === 'collections')
    ? undefined
    : tabs[activeTab];
  const tabDefs: { key: TabKey; label: string; ownerOnly: boolean }[] = [
    { key: 'coins', label: 'Coins', ownerOnly: true },
    { key: 'wallpapers', label: 'Wallpapers', ownerOnly: false },
    { key: 'collections', label: 'Collections', ownerOnly: false },
    { key: 'downloads', label: 'Downloads', ownerOnly: true },
    { key: 'favorites', label: 'Favorites', ownerOnly: true },
    { key: 'likes', label: 'Likes', ownerOnly: true },
  ];

  const renderCoinsTab = () => (
    <div className="max-w-2xl">
      <div className="bg-gradient-to-r from-amber-400 via-yellow-400 to-orange-400 rounded-2xl p-6 mb-8 text-white shadow-lg relative overflow-hidden">
        <div className="absolute -right-4 -top-4 text-[120px] opacity-10 rotate-12 select-none">💰</div>
        <p className="text-sm font-medium opacity-90 mb-1">My Coins</p>
        <p className="text-4xl font-bold">{currentUser?.coins ?? 0}</p>
        <p className="text-xs opacity-75 mt-2">
          Upload wallpapers to earn coins. Each download costs 1 coin (your own wallpapers are free).
        </p>
      </div>

      <h3 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">Transaction History</h3>

      {txLoading && transactions.length === 0 ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-16 bg-gray-100 dark:bg-gray-800 rounded-lg animate-pulse" />
          ))}
        </div>
      ) : transactions.length === 0 ? (
        <EmptyState message="No transactions yet." />
      ) : (
        <div className="space-y-2">
          {transactions.map((tx) => {
            const info = TX_LABELS[tx.tx_type] ?? { label: tx.tx_type, color: tx.amount > 0 ? 'text-green-600' : 'text-red-500' };
            return (
              <div
                key={tx.id}
                className="flex items-center justify-between px-4 py-3 bg-white dark:bg-gray-800 rounded-lg border border-gray-100 dark:border-gray-700"
              >
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-800 dark:text-gray-200">{info.label}</p>
                  <p className="text-xs text-gray-400 mt-0.5">
                    {formatTime(tx.created_at)}
                    {tx.ref_id > 0 && (
                      <> · <Link to={`/wallpaper/${tx.ref_id}`} className="text-indigo-500 hover:underline">Wallpaper #{tx.ref_id}</Link></>
                    )}
                  </p>
                </div>
                <div className="text-right ml-4">
                  <p className={`text-sm font-bold ${info.color}`}>
                    {tx.amount > 0 ? '+' : ''}{tx.amount}
                  </p>
                  <p className="text-xs text-gray-400">Balance: {tx.balance}</p>
                </div>
              </div>
            );
          })}

          <Pagination
            page={txPage}
            totalPages={Math.max(1, Math.ceil(txTotal / pageSize))}
            onChange={(p) => fetchTransactionsPage(p)}
          />
        </div>
      )}
    </div>
  );

  // Two-step avatar flow: pick a file → open crop modal → user adjusts →
  // upload the cropped JPEG. Keeps the upload step independent of file size
  // since we always emit a 512² JPEG @ q=0.9 (~50-80 KB).
  const handleAvatarChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = ''; // allow re-selecting the same file later
    if (!file) return;
    // 10 MB ceiling on the *source* image. The cropper would happily decode
    // a 50 MB image but we save bandwidth and avoid Safari memory issues.
    if (file.size > 10 * 1024 * 1024) {
      toast.error('图片需小于 10MB');
      return;
    }
    setCropFile(file);
  };

  const uploadCroppedAvatar = async (blob: Blob) => {
    const fd = new FormData();
    fd.append('avatar', blob, 'avatar.jpg');
    try {
      const res = await uploadAvatar(fd);
      const url = res.data.data.avatar_url;
      setUser((prev) => prev ? { ...prev, avatar_url: url } : prev);
      useAuthStore.getState().updateUser({ avatar_url: url });
      setCropFile(null);
      toast.success('头像已更新');
    } catch {
      toast.error('上传失败');
    }
  };

  const startEditProfile = () => {
    setEditNickname(user?.nickname || '');
    setEditBio(user?.bio || '');
    setEditingProfile(true);
  };

  const saveProfile = async () => {
    const nickname = editNickname.trim();
    if (!nickname) { toast.error('昵称不能为空'); return; }
    if (nickname.length > 64) { toast.error('昵称最多 64 个字符'); return; }
    const bio = editBio.trim();
    if (bio.length > 500) { toast.error('简介最多 500 个字符'); return; }
    // No-op if nothing actually changed — avoids a needless request.
    if (nickname === (user?.nickname || '') && bio === (user?.bio || '')) {
      setEditingProfile(false);
      return;
    }
    setSavingProfile(true);
    try {
      const res = await updateProfile({ nickname, bio });
      const updated = res.data.data;
      setUser((prev) => prev ? { ...prev, nickname: updated.nickname, bio: updated.bio } : prev);
      useAuthStore.getState().updateUser({ nickname: updated.nickname });
      setEditingProfile(false);
      toast.success('已保存');
    } catch {
      toast.error('保存失败');
    } finally {
      setSavingProfile(false);
    }
  };

  const handleChangePassword = async () => {
    if (newPw.length < 8) { toast.error('New password must be at least 8 characters'); return; }
    setSavingPw(true);
    try {
      await changePassword({ old_password: oldPw, new_password: newPw });
      toast.success('Password changed');
      setShowPasswordModal(false);
      setOldPw('');
      setNewPw('');
    } catch (err: any) {
      const msg = err.response?.data?.message;
      toast.error(msg === 'wrong password' ? 'Current password is incorrect' : 'Failed to change password');
    } finally {
      setSavingPw(false);
    }
  };

  return (
    <div className="px-6 py-6">
      <PageMeta
        title={user ? `${user.nickname || user.username}'s Profile` : 'Profile'}
        description={user ? `Wallpapers, collections, and uploads from ${user.nickname || user.username} on Wallpaper Exchange.` : undefined}
        image={user?.avatar_url}
        type="profile"
      />
      {/* Avatar crop modal — opened after user picks a file. */}
      {cropFile && (
        <AvatarCropModal
          file={cropFile}
          onCancel={() => setCropFile(null)}
          onSave={uploadCroppedAvatar}
        />
      )}

      {/* Password Modal */}
      {showPasswordModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setShowPasswordModal(false)}>
          <div className="bg-white dark:bg-ws-dark-card rounded-2xl shadow-xl border border-ws-border dark:border-white/5 p-6 w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-lg font-semibold text-slate-900 dark:text-white mb-4">Change Password</h3>
            <div className="space-y-3">
              <input type="password" placeholder="Current password" value={oldPw} onChange={(e) => setOldPw(e.target.value)} className="w-full bg-ws-bg dark:bg-ws-dark-bg border border-ws-border dark:border-white/10 rounded-xl py-2.5 px-4 text-sm outline-none focus:ring-1 focus:ring-ws-purple dark:text-white" />
              <input type="password" placeholder="New password (min 8 chars)" value={newPw} onChange={(e) => setNewPw(e.target.value)} className="w-full bg-ws-bg dark:bg-ws-dark-bg border border-ws-border dark:border-white/10 rounded-xl py-2.5 px-4 text-sm outline-none focus:ring-1 focus:ring-ws-purple dark:text-white" />
            </div>
            <div className="flex gap-2 mt-5">
              <button onClick={() => setShowPasswordModal(false)} className="flex-1 py-2.5 text-sm font-medium rounded-xl border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:bg-ws-bg dark:hover:bg-white/5 transition-colors">Cancel</button>
              <button onClick={handleChangePassword} disabled={savingPw} className="flex-1 py-2.5 text-sm font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-xl transition-colors disabled:opacity-50">{savingPw ? 'Saving...' : 'Confirm'}</button>
            </div>
          </div>
        </div>
      )}

      {/* Profile header */}
      <div className="flex items-start gap-6 mb-10">
        <div className="relative group flex-shrink-0">
          <div className="w-24 h-24 rounded-2xl overflow-hidden ring-4 ring-ws-purple/20 dark:ring-purple-900/40 shadow-lg">
            {user.avatar_url ? (
              <img src={user.avatar_url} alt="" className="w-full h-full object-cover" />
            ) : (
              <div className="w-full h-full bg-gradient-to-br from-ws-purple-light via-purple-200 to-purple-300 dark:from-ws-dark-active dark:via-purple-900/50 dark:to-purple-800/30 flex items-center justify-center text-3xl font-bold text-ws-purple dark:text-purple-400">
                {(user.nickname || user.username).charAt(0).toUpperCase()}
              </div>
            )}
          </div>
          {isOwnProfile && (
            <>
              <button
                onClick={() => avatarInputRef.current?.click()}
                className="absolute inset-0 rounded-2xl bg-black/0 group-hover:bg-black/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all cursor-pointer"
              >
                <AiOutlineCamera size={22} className="text-white" />
              </button>
              <input ref={avatarInputRef} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={handleAvatarChange} />
            </>
          )}
        </div>
        <div className="flex-1 min-w-0">
          {editingProfile ? (
            <div className="space-y-3 max-w-md">
              <div>
                <div className="flex items-baseline justify-between mb-1">
                  <label className="text-xs text-ws-muted dark:text-ws-dark-muted">昵称</label>
                  <span className={`text-[11px] tabular-nums ${editNickname.length > 64 ? 'text-rose-500' : 'text-slate-400'}`}>{editNickname.length}/64</span>
                </div>
                <input
                  autoFocus
                  value={editNickname}
                  onChange={(e) => setEditNickname(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') { e.preventDefault(); saveProfile(); }
                    if (e.key === 'Escape') { setEditingProfile(false); }
                  }}
                  placeholder="给自己起个名字"
                  maxLength={64}
                  className="w-full bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-xl py-2 px-3.5 text-sm font-semibold outline-none focus:ring-1 focus:ring-ws-purple dark:text-white"
                />
                <p className="text-[11px] text-slate-400 mt-1">用户名 <span className="font-mono">@{user.username}</span> 不可修改</p>
              </div>
              <div>
                <div className="flex items-baseline justify-between mb-1">
                  <label className="text-xs text-ws-muted dark:text-ws-dark-muted">个人简介</label>
                  <span className={`text-[11px] tabular-nums ${editBio.length > 500 ? 'text-rose-500' : 'text-slate-400'}`}>{editBio.length}/500</span>
                </div>
                <textarea
                  value={editBio}
                  onChange={(e) => setEditBio(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') { setEditingProfile(false); }
                    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); saveProfile(); }
                  }}
                  placeholder="介绍一下你自己…"
                  maxLength={500}
                  rows={3}
                  className="w-full bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-xl py-2 px-3.5 text-sm outline-none focus:ring-1 focus:ring-ws-purple resize-none dark:text-white"
                />
              </div>
              <div className="flex gap-2">
                <button onClick={saveProfile} disabled={savingProfile || !editNickname.trim()} className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                  <AiOutlineCheck size={14} />{savingProfile ? '保存中…' : '保存'}
                </button>
                <button onClick={() => setEditingProfile(false)} className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-medium text-ws-muted dark:text-ws-dark-muted border border-ws-border dark:border-white/10 rounded-lg hover:bg-ws-bg dark:hover:bg-white/5 transition-colors">
                  <AiOutlineClose size={14} />取消
                </button>
                <span className="text-[11px] text-slate-400 self-center ml-1 hidden sm:inline">Enter 保存 · Esc 取消</span>
              </div>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-3 flex-wrap">
                <h1 className="text-2xl font-bold text-slate-900 dark:text-white">
                  {user.nickname || user.username}
                </h1>
                <span className="inline-flex items-center gap-1.5 px-3.5 py-1 rounded-full bg-gradient-to-r from-amber-50 to-yellow-50 dark:from-amber-900/20 dark:to-yellow-900/20 border border-amber-200/60 dark:border-amber-700/40 shadow-sm">
                  <span className="text-base">💰</span>
                  <span className="text-sm font-bold bg-gradient-to-r from-amber-600 to-yellow-500 bg-clip-text text-transparent">{isOwnProfile ? (currentUser?.coins ?? 0) : (user.coins ?? 0)}</span>
                </span>
              </div>
              {user.bio && <p className="mt-1.5 text-sm text-slate-600 dark:text-slate-400">{user.bio}</p>}
              {isOwnProfile && (
                <div className="flex items-center gap-2 mt-3">
                  <button onClick={startEditProfile} className="flex items-center gap-1.5 px-3.5 py-1.5 text-xs font-medium text-ws-muted dark:text-ws-dark-muted border border-ws-border dark:border-white/10 rounded-lg hover:text-ws-purple hover:border-ws-purple/30 transition-colors">
                    <AiOutlineEdit size={14} />Edit Profile
                  </button>
                  <button onClick={() => setShowPasswordModal(true)} className="flex items-center gap-1.5 px-3.5 py-1.5 text-xs font-medium text-ws-muted dark:text-ws-dark-muted border border-ws-border dark:border-white/10 rounded-lg hover:text-ws-purple hover:border-ws-purple/30 transition-colors">
                    <AiOutlineLock size={14} />Password
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </div>

      <div className="flex gap-1 mb-6 border-b border-gray-200 dark:border-gray-700 overflow-x-auto">
        {tabDefs
          .filter((t) => !t.ownerOnly || isOwnProfile)
          .map((t) => (
            <button
              key={t.key}
              onClick={() => handleTabChange(t.key)}
              className={`px-4 py-2.5 text-sm font-medium border-b-2 transition-colors whitespace-nowrap ${
                activeTab === t.key
                  ? 'border-indigo-600 text-indigo-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {t.key === 'coins' ? (
                <span className="flex items-center gap-1.5">💰 {t.label}</span>
              ) : (
                t.label
              )}
            </button>
          ))}
      </div>

      {activeTab === 'coins' ? (
        renderCoinsTab()
      ) : activeTab === 'collections' ? (
        <>
          {collections.length > 0 ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
              {collections.map((c) => (
                <Link
                  key={c.id}
                  to={`/collections/${c.slug}`}
                  className="group block rounded-2xl overflow-hidden bg-white dark:bg-gray-800 shadow-sm hover:shadow-lg transition-all duration-300 border border-gray-100 dark:border-gray-700"
                >
                  <div className="aspect-video bg-gradient-to-br from-indigo-100 to-purple-100 dark:from-indigo-900/30 dark:to-purple-900/30 relative overflow-hidden">
                    {c.cover_url ? (
                      <img src={c.cover_url} alt="" className="w-full h-full object-cover group-hover:scale-105 transition-transform duration-500" />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center">
                        <AiOutlinePicture size={48} className="text-indigo-200 dark:text-indigo-700" />
                      </div>
                    )}
                    <div className="absolute bottom-3 right-3 px-2.5 py-1 bg-black/50 backdrop-blur-sm text-white text-xs font-medium rounded-full">
                      {c.wallpaper_count} wallpapers
                    </div>
                  </div>
                  <div className="p-4">
                    <h3 className="text-lg font-semibold text-gray-900 dark:text-white mb-2 group-hover:text-indigo-600 transition-colors">
                      {c.title}
                    </h3>
                    {c.description && (
                      <p className="text-sm text-gray-500 dark:text-gray-400 line-clamp-2 mb-3">{c.description}</p>
                    )}
                    <div className="flex items-center gap-4 text-xs text-gray-400">
                      <span className="flex items-center gap-1"><AiOutlineHeart size={14} />{c.like_count}</span>
                      <span className="flex items-center gap-1"><AiOutlineEye size={14} />{c.view_count}</span>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          ) : (
            <EmptyState message="No collections yet." />
          )}
        </>
      ) : (
        <>
          {activeTab === 'downloads' && (
            <div className="flex items-center gap-2 mb-5">
              <button
                onClick={toggleDlDeviceFilter}
                title={dlDeviceFilter ? `${screen.width}×${screen.height}` : 'Filter for your device'}
                className={`flex items-center gap-2 px-4 py-2 text-sm font-semibold rounded-full border transition-colors ${
                  dlDeviceFilter
                    ? 'bg-ws-purple text-white border-ws-purple shadow-sm'
                    : 'text-slate-600 dark:text-ws-dark-muted border-ws-border dark:border-white/10 dark:bg-ws-dark-card hover:bg-ws-bg dark:hover:bg-white/5'
                }`}
              >
                <MdDevices size={16} />
                <span>{dlDeviceFilter ? `${screen.width}×${screen.height}` : 'My Device'}</span>
              </button>
              <button
                onClick={toggleDlMacFilter}
                className={`flex items-center gap-2 px-4 py-2 text-sm font-semibold rounded-full border transition-colors ${
                  dlMacFilter
                    ? 'bg-ws-purple text-white border-ws-purple shadow-sm'
                    : 'text-slate-600 dark:text-ws-dark-muted border-ws-border dark:border-white/10 dark:bg-ws-dark-card hover:bg-ws-bg dark:hover:bg-white/5'
                }`}
              >
                <AiOutlineApple size={14} />
                <span>macOS</span>
              </button>
            </div>
          )}
          {tabLoading && !currentTab?.loaded ? (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 border-2 border-ws-purple/20 border-t-ws-purple rounded-full animate-spin" />
            </div>
          ) : currentTab && currentTab.items.length > 0 ? (
            <>
              <WallpaperGrid
                wallpapers={currentTab.items}
                showStatus={activeTab === 'wallpapers' && isOwnProfile}
                viewMode="grid"
                sizeMode="md"
                disableModal
              />
              <Pagination
                page={currentTab.page}
                totalPages={Math.max(1, Math.ceil(currentTab.total / pageSize))}
                onChange={(p) => fetchWallpaperPage(activeTab as WallpaperTabKey, p)}
              />
            </>
          ) : currentTab?.loaded ? (
            <EmptyState message={`No ${activeTab} yet.`} />
          ) : null}
        </>
      )}
    </div>
  );
}
