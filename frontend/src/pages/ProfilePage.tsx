import { useState, useEffect, useCallback, useRef } from 'react';
import { useParams, Link } from 'react-router-dom';
import usePageTitle from '../hooks/usePageTitle';
import { AiOutlineHeart, AiOutlineEye, AiOutlinePicture, AiOutlineEdit, AiOutlineCamera, AiOutlineLock, AiOutlineCheck, AiOutlineClose } from 'react-icons/ai';
import toast from 'react-hot-toast';
import type { User, Wallpaper, Collection, CoinTransaction } from '../types';
import { getUserProfile, getUserWallpapers, getUserCollections, getMyFavorites, getMyLikes, getMyDownloads, getMyCoins, getCoinTransactions, updateProfile, uploadAvatar, changePassword } from '../api';
import { useAuthStore } from '../store/auth';
import WallpaperGrid from '../components/WallpaperGrid';
import Spinner from '../components/Spinner';
import EmptyState from '../components/EmptyState';

type TabKey = 'coins' | 'wallpapers' | 'collections' | 'favorites' | 'likes' | 'downloads';

interface WallpaperTab {
  items: Wallpaper[];
  cursor?: number;
  hasMore: boolean;
  loaded: boolean;
}

const PAGE_SIZE = 20;

function Pagination({ page, totalPages, onChange }: { page: number; totalPages: number; onChange: (p: number) => void }) {
  if (totalPages <= 1) return null;
  return (
    <div className="flex items-center justify-center gap-2 mt-8">
      <button onClick={() => onChange(page - 1)} disabled={page <= 1} className="px-3 py-1.5 text-sm rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple disabled:opacity-30 disabled:cursor-not-allowed transition-colors">&larr; Prev</button>
      <span className="px-3 text-sm text-ws-muted dark:text-ws-dark-muted">{page} / {totalPages}</span>
      <button onClick={() => onChange(page + 1)} disabled={page >= totalPages} className="px-3 py-1.5 text-sm rounded-lg border border-ws-border dark:border-white/10 text-ws-muted dark:text-ws-dark-muted hover:text-ws-purple disabled:opacity-30 disabled:cursor-not-allowed transition-colors">Next &rarr;</button>
    </div>
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

export default function ProfilePage() {
  const { id } = useParams<{ id: string }>();
  const { user: currentUser, updateCoins } = useAuthStore();
  const [user, setUser] = useState<User | null>(null);
  usePageTitle(user ? `${user.nickname || user.username}'s Profile` : 'Profile');
  const [loading, setLoading] = useState(true);
  const [collections, setCollections] = useState<Collection[]>([]);

  const isOwnProfile = currentUser?.id === Number(id);
  const [activeTab, setActiveTab] = useState<TabKey>(isOwnProfile ? 'coins' : 'wallpapers');

  const [tabs, setTabs] = useState<Record<string, WallpaperTab>>({
    wallpapers: { items: [], hasMore: false, loaded: false },
    favorites: { items: [], hasMore: false, loaded: false },
    likes: { items: [], hasMore: false, loaded: false },
    downloads: { items: [], hasMore: false, loaded: false },
  });
  const [tabPage, setTabPage] = useState<Record<string, number>>({ wallpapers: 1, favorites: 1, likes: 1, downloads: 1, collections: 1, coins: 1 });

  const [tabLoading, setTabLoading] = useState(false);
  const [transactions, setTransactions] = useState<CoinTransaction[]>([]);
  const [txHasMore, setTxHasMore] = useState(false);
  const [txLoading, setTxLoading] = useState(false);
  const [txLoaded, setTxLoaded] = useState(false);

  const updateTab = (key: string, updates: Partial<WallpaperTab>) => {
    setTabs((prev) => ({ ...prev, [key]: { ...prev[key], ...updates } }));
  };

  const loadCoins = useCallback(async () => {
    try {
      const res = await getMyCoins();
      updateCoins(res.data.data.coins);
    } catch {
      // silent
    }
  }, [updateCoins]);

  const loadTransactions = useCallback(async (page: number) => {
    setTxLoading(true);
    try {
      const res = await getCoinTransactions({ limit: PAGE_SIZE * page });
      const allItems = res.data.data?.items ?? [];
      const start = (page - 1) * PAGE_SIZE;
      setTransactions(allItems.slice(start, start + PAGE_SIZE));
      setTxHasMore(allItems.length > start + PAGE_SIZE || res.data.data?.has_more);
      setTxLoaded(true);
    } catch {
      toast.error('Failed to load transactions');
    } finally {
      setTxLoading(false);
    }
  }, []);

  const loadWallpaperPage = useCallback(async (key: string, page: number) => {
    setTabLoading(true);
    const limit = PAGE_SIZE;
    const fetchLimit = limit * page;
    try {
      let res;
      if (key === 'wallpapers') {
        res = await getUserWallpapers(Number(id), { limit: fetchLimit });
      } else if (key === 'favorites') {
        res = await getMyFavorites({ limit: fetchLimit });
      } else if (key === 'downloads') {
        res = await getMyDownloads({ limit: fetchLimit });
      } else {
        res = await getMyLikes({ limit: fetchLimit });
      }
      const allItems = res.data.data?.items ?? [];
      const start = (page - 1) * limit;
      const hasMore = res.data.data?.has_more || allItems.length > start + limit;
      updateTab(key, {
        items: allItems.slice(start, start + limit),
        hasMore,
        loaded: true,
      });
    } catch {
      toast.error('Failed to load data');
      updateTab(key, { loaded: true });
    } finally {
      setTabLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setTabs({
      wallpapers: { items: [], hasMore: false, loaded: false },
      favorites: { items: [], hasMore: false, loaded: false },
      likes: { items: [], hasMore: false, loaded: false },
      downloads: { items: [], hasMore: false, loaded: false },
    });
    setTabPage({ wallpapers: 1, favorites: 1, likes: 1, downloads: 1, collections: 1, coins: 1 });
    setTransactions([]);
    setTxLoaded(false);

    const own = currentUser?.id === Number(id);
    setActiveTab(own ? 'coins' : 'wallpapers');

    Promise.all([
      getUserProfile(Number(id)),
      getUserWallpapers(Number(id), { limit: PAGE_SIZE }),
      getUserCollections(Number(id), { limit: 50 }),
    ])
      .then(([profileRes, wpRes, colRes]) => {
        setUser(profileRes.data.data);
        const { items, has_more } = wpRes.data.data;
        updateTab('wallpapers', { items, hasMore: has_more, loaded: true });
        setCollections(colRes.data.data?.items || []);
      })
      .catch(() => toast.error('Failed to load profile'))
      .finally(() => setLoading(false));

    if (own) {
      loadCoins();
      loadTransactions(1);
    }
  }, [id]);

  const handleTabChange = (tab: TabKey) => {
    setActiveTab(tab);
    if ((tab === 'favorites' || tab === 'likes' || tab === 'downloads') && !tabs[tab]?.loaded) {
      loadWallpaperPage(tab, 1);
    }
    if (tab === 'coins' && !txLoaded) {
      loadCoins();
      loadTransactions(1);
    }
  };

  const handlePageChange = (key: string, page: number) => {
    setTabPage((prev) => ({ ...prev, [key]: page }));
    if (key === 'coins') {
      loadTransactions(page);
    } else {
      loadWallpaperPage(key, page);
    }
  };

  if (loading) return <Spinner />;
  if (!user) return <EmptyState message="User not found." />;

  const currentTab = tabs[activeTab];
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

          {(txHasMore || tabPage.coins > 1) && (
            <Pagination page={tabPage.coins} totalPages={txHasMore ? tabPage.coins + 1 : tabPage.coins} onChange={(p) => handlePageChange('coins', p)} />
          )}
        </div>
      )}
    </div>
  );

  const avatarInputRef = useRef<HTMLInputElement>(null);
  const [editingProfile, setEditingProfile] = useState(false);
  const [editNickname, setEditNickname] = useState('');
  const [editBio, setEditBio] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);
  const [showPasswordModal, setShowPasswordModal] = useState(false);
  const [oldPw, setOldPw] = useState('');
  const [newPw, setNewPw] = useState('');
  const [savingPw, setSavingPw] = useState(false);

  const handleAvatarChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 5 * 1024 * 1024) { toast.error('Avatar must be under 5MB'); return; }
    const fd = new FormData();
    fd.append('avatar', file);
    try {
      const res = await uploadAvatar(fd);
      const url = res.data.data.avatar_url;
      setUser((prev) => prev ? { ...prev, avatar_url: url } : prev);
      useAuthStore.getState().updateUser({ avatar_url: url });
      toast.success('Avatar updated');
    } catch {
      toast.error('Failed to upload avatar');
    }
  };

  const startEditProfile = () => {
    setEditNickname(user?.nickname || '');
    setEditBio(user?.bio || '');
    setEditingProfile(true);
  };

  const saveProfile = async () => {
    setSavingProfile(true);
    try {
      const res = await updateProfile({ nickname: editNickname, bio: editBio });
      const updated = res.data.data;
      setUser((prev) => prev ? { ...prev, nickname: updated.nickname, bio: updated.bio } : prev);
      useAuthStore.getState().updateUser({ nickname: updated.nickname });
      setEditingProfile(false);
      toast.success('Profile updated');
    } catch {
      toast.error('Failed to update profile');
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
            <div className="space-y-3">
              <input value={editNickname} onChange={(e) => setEditNickname(e.target.value)} placeholder="Nickname" maxLength={64} className="w-full max-w-xs bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-xl py-2 px-3.5 text-sm font-semibold outline-none focus:ring-1 focus:ring-ws-purple dark:text-white" />
              <textarea value={editBio} onChange={(e) => setEditBio(e.target.value)} placeholder="Write something about yourself..." maxLength={500} rows={2} className="w-full max-w-md bg-ws-bg dark:bg-ws-dark-card border border-ws-border dark:border-white/10 rounded-xl py-2 px-3.5 text-sm outline-none focus:ring-1 focus:ring-ws-purple resize-none dark:text-white" />
              <div className="flex gap-2">
                <button onClick={saveProfile} disabled={savingProfile} className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold text-white bg-ws-purple hover:bg-ws-purple-hover rounded-lg transition-colors disabled:opacity-50">
                  <AiOutlineCheck size={14} />{savingProfile ? 'Saving...' : 'Save'}
                </button>
                <button onClick={() => setEditingProfile(false)} className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-medium text-ws-muted dark:text-ws-dark-muted border border-ws-border dark:border-white/10 rounded-lg hover:bg-ws-bg dark:hover:bg-white/5 transition-colors">
                  <AiOutlineClose size={14} />Cancel
                </button>
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
                  to={`/collections/${c.id}`}
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
              />
              {(currentTab.hasMore || tabPage[activeTab] > 1) && (
                <Pagination page={tabPage[activeTab]} totalPages={currentTab.hasMore ? tabPage[activeTab] + 1 : tabPage[activeTab]} onChange={(p) => handlePageChange(activeTab, p)} />
              )}
            </>
          ) : currentTab?.loaded ? (
            <EmptyState message={`No ${activeTab} yet.`} />
          ) : null}
        </>
      )}
    </div>
  );
}
