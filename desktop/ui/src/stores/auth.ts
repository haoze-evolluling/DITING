import { create } from "zustand";
import { persist } from "zustand/middleware";

import type { LoginResult } from "../lib/types";

interface AuthState {
  token: string | null;
  username: string | null;
  expiresAt: number | null;
  setSession: (session: LoginResult) => void;
  clear: () => void;
  isExpired: () => boolean;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      token: null,
      username: null,
      expiresAt: null,
      setSession: (session) =>
        set({
          token: session.token,
          username: session.username,
          expiresAt: session.expiresAt,
        }),
      clear: () => set({ token: null, username: null, expiresAt: null }),
      isExpired: () => {
        const { expiresAt } = get();
        return Boolean(expiresAt && expiresAt * 1000 <= Date.now());
      },
    }),
    {
      name: "diting.desktop.auth",
      partialize: (state) => ({
        token: state.token,
        username: state.username,
        expiresAt: state.expiresAt,
      }),
    },
  ),
);
