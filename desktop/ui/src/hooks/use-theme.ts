import { useEffect, useRef, useState } from "react";

import { useUIStore } from "../stores/ui";
import { useMotion } from "./use-motion";

function readSystemDark(): boolean {
  if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
    return false;
  }
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

/** 供 React 树外的组件（如 Toaster）读取解析后的深浅色。 */
export function useIsDark(): boolean {
  const theme = useUIStore((state) => state.theme);
  const [systemDark, setSystemDark] = useState<boolean>(readSystemDark);

  useEffect(() => {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") {
      return;
    }
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystemDark(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  return theme === "dark" || (theme === "system" && systemDark);
}

export function useApplyTheme(): void {
  const theme = useUIStore((state) => state.theme);
  const accent = useUIStore((state) => state.accent);
  const { effective: motion, allowThemeTransition } = useMotion();
  const initializedRef = useRef(false);
  const allowThemeTransitionRef = useRef(allowThemeTransition);
  allowThemeTransitionRef.current = allowThemeTransition;

  useEffect(() => {
    document.documentElement.dataset.motion = motion;
  }, [motion]);

  useEffect(() => {
    const root = document.documentElement;
    let timer: number | undefined;

    if (initializedRef.current && allowThemeTransitionRef.current) {
      root.dataset.themeTransition = "true";
      timer = window.setTimeout(() => {
        delete root.dataset.themeTransition;
      }, 240);
    }
    initializedRef.current = true;

    root.dataset.accent = accent;

    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark = theme === "dark" || (theme === "system" && media.matches);
      root.classList.toggle("dark", dark);
      root.style.colorScheme = dark ? "dark" : "light";
    };

    apply();
    media.addEventListener("change", apply);
    return () => {
      media.removeEventListener("change", apply);
      if (timer !== undefined) {
        window.clearTimeout(timer);
        delete root.dataset.themeTransition;
      }
    };
  }, [theme, accent]);
}
