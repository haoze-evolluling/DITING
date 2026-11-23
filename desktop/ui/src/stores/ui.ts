import { create } from "zustand";
import { persist } from "zustand/middleware";

export type ThemeMode = "system" | "light" | "dark";
export type Accent = "blue" | "jade" | "violet" | "amber";
export type MotionLevel = "off" | "minimal" | "standard" | "rich";

interface UIState {
  theme: ThemeMode;
  accent: Accent;
  /** null 表示尚未手动选择，首次默认跟随系统减弱动态设置 */
  motion: MotionLevel | null;
  setTheme: (theme: ThemeMode) => void;
  setAccent: (accent: Accent) => void;
  setMotion: (motion: MotionLevel) => void;
}

export const useUIStore = create<UIState>()(
  persist(
    (set) => ({
      theme: "system",
      accent: "blue",
      motion: null,
      setTheme: (theme) => set({ theme }),
      setAccent: (accent) => set({ accent }),
      setMotion: (motion) => set({ motion }),
    }),
    { name: "diting.desktop.ui" },
  ),
);
