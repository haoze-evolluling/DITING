import { create } from "zustand";
import { persist } from "zustand/middleware";

export type ThemeMode = "system" | "light" | "dark";
export type Accent = "blue" | "jade" | "violet" | "amber";

interface UIState {
  theme: ThemeMode;
  accent: Accent;
  setTheme: (theme: ThemeMode) => void;
  setAccent: (accent: Accent) => void;
}

export const useUIStore = create<UIState>()(
  persist(
    (set) => ({
      theme: "system",
      accent: "blue",
      setTheme: (theme) => set({ theme }),
      setAccent: (accent) => set({ accent }),
    }),
    { name: "diting.desktop.ui" },
  ),
);
