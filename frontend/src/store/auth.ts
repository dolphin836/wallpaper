import { create } from 'zustand';
import type { User } from '../types';

interface AuthState {
  token: string | null;
  user: User | null;
  isAuthenticated: boolean;
  setAuth: (token: string, user: User) => void;
  updateCoins: (coins: number) => void;
  updateUser: (partial: Partial<User>) => void;
  logout: () => void;
}

function getInitialAuth(): { token: string | null; user: User | null; isAuthenticated: boolean } {
  const token = localStorage.getItem('token');
  const userStr = localStorage.getItem('user');
  if (token && userStr) {
    try {
      return { token, user: JSON.parse(userStr), isAuthenticated: true };
    } catch {
      localStorage.removeItem('token');
      localStorage.removeItem('user');
    }
  }
  return { token: null, user: null, isAuthenticated: false };
}

export const useAuthStore = create<AuthState>((set) => ({
  ...getInitialAuth(),
  setAuth: (token, user) => {
    localStorage.setItem('token', token);
    localStorage.setItem('user', JSON.stringify(user));
    set({ token, user, isAuthenticated: true });
  },
  updateCoins: (coins) => {
    set((state) => {
      if (state.user) {
        const updated = { ...state.user, coins };
        localStorage.setItem('user', JSON.stringify(updated));
        return { user: updated };
      }
      return {};
    });
  },
  updateUser: (partial) => {
    set((state) => {
      if (state.user) {
        const updated = { ...state.user, ...partial };
        localStorage.setItem('user', JSON.stringify(updated));
        return { user: updated };
      }
      return {};
    });
  },
  logout: () => {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
    set({ token: null, user: null, isAuthenticated: false });
  },
}));
