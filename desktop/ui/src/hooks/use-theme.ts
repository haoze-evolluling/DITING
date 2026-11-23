import { useEffect, useRef } from "react";

import { useUIStore } from "../stores/ui";
import { useMotion } from "./use-motion";

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
