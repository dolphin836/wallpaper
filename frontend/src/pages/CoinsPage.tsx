import { useState, useEffect } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useAuthStore } from '../store/auth';
import { getMyCoins, getCoinTransactions } from '../api';
import type { CoinTransaction } from '../types';

const TX_LABELS: Record<string, { label: string; color: string }> = {
  register_bonus: { label: 'Registration Bonus', color: 'text-green-600' },
  upload_reward: { label: 'Upload Reward', color: 'text-green-600' },
  download_cost: { label: 'Download Cost', color: 'text-red-500' },
  download_earned: { label: 'Download Earned', color: 'text-green-600' },
};

function formatTime(dateStr: string): string {
  return new Date(dateStr).toLocaleString();
}

export default function CoinsPage() {
  const { isAuthenticated, user, updateCoins } = useAuthStore();
  const navigate = useNavigate();
  const [transactions, setTransactions] = useState<CoinTransaction[]>([]);
  const [cursor, setCursor] = useState<number | undefined>();
  const [hasMore, setHasMore] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!isAuthenticated) {
      navigate('/login');
      return;
    }
    loadCoins();
    loadTransactions(true);
  }, [isAuthenticated]);

  const loadCoins = async () => {
    try {
      const res = await getMyCoins();
      updateCoins(res.data.data.coins);
    } catch {
      // silent
    }
  };

  const loadTransactions = async (reset: boolean) => {
    setLoading(true);
    try {
      const res = await getCoinTransactions({
        cursor: reset ? undefined : cursor,
        limit: 20,
      });
      const { items, next_cursor, has_more } = res.data.data;
      setTransactions((prev) => (reset ? items : [...prev, ...items]));
      setCursor(next_cursor);
      setHasMore(has_more);
    } catch {
      toast.error('Failed to load transactions');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <div className="bg-gradient-to-r from-amber-400 to-orange-500 rounded-2xl p-6 mb-8 text-white shadow-lg">
        <p className="text-sm font-medium opacity-90 mb-1">My Coins</p>
        <p className="text-4xl font-bold">{user?.coins ?? 0}</p>
        <p className="text-xs opacity-75 mt-2">
          Upload wallpapers to earn coins. Each download costs 1 coin (your own wallpapers are free).
        </p>
      </div>

      <h2 className="text-lg font-semibold text-gray-800 dark:text-gray-200 mb-4">Transaction History</h2>

      {loading && transactions.length === 0 ? (
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-16 bg-gray-100 dark:bg-gray-800 rounded-lg animate-pulse" />
          ))}
        </div>
      ) : transactions.length === 0 ? (
        <p className="text-center text-gray-400 py-12">No transactions yet</p>
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

          {hasMore && (
            <div className="flex justify-center pt-4">
              <button
                onClick={() => loadTransactions(false)}
                disabled={loading}
                className="px-6 py-2 text-sm font-medium text-indigo-600 border border-indigo-600 rounded-lg hover:bg-indigo-50 transition-colors disabled:opacity-50"
              >
                {loading ? 'Loading...' : 'Load More'}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
