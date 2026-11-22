import { useEffect } from "react";

import { useUIStore } from "../stores/ui";

export function useApplyTheme(): void {
  const theme = useUIStore((state) => state.theme);
  const accent = useUIStore((state) => state.accent);

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.accent = accent;

    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const apply = () => {
      const dark = theme === "dark" || (theme === "system" && media.matches);
      root.classList.toggle("dark", dark);
      root.style.colorScheme = dark ? "dark" : "light";
    };

    apply();
    media.addEventListener("change", apply);
    return () => media.removeEventListener("change", apply);
  }, [theme, accent]);
}
