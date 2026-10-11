/** 谛听 (DITING) 主题管理：浅色 / 深色 / 跟随系统 */
import { ref, readonly } from 'vue';

export type ThemeMode = 'light' | 'dark' | 'system';

const STORAGE_KEY = 'diting_theme_mode';
const DARK_BG = '#16171A';
const DARK_FG = '#E9E8E4';
const LIGHT_BG = '#FAF9F5';
const LIGHT_FG = '#1A1A1C';

class ThemeManager {
  private currentMode = ref<ThemeMode>('system');
  private isDarkActive = ref<boolean>(false);
  private mediaListenerAttached = false;

  constructor() {
    this.init();
  }

  private init() {
    if (typeof window === 'undefined') return;

    try {
      const saved = localStorage.getItem(STORAGE_KEY) as ThemeMode;
      if (saved === 'light' || saved === 'dark' || saved === 'system') {
        this.currentMode.value = saved;
      }
    } catch {}

    this.attachSystemThemeListener();
    this.applyTheme();
  }

  private attachSystemThemeListener() {
    if (this.mediaListenerAttached || typeof window === 'undefined' || !window.matchMedia) return;
    try {
      const mql = window.matchMedia('(prefers-color-scheme: dark)');
      mql.addEventListener('change', () => {
        if (this.currentMode.value === 'system') {
          this.applyTheme();
        }
      });
      this.mediaListenerAttached = true;
    } catch {}
  }

  public getThemeMode(): ThemeMode {
    return this.currentMode.value;
  }

  public get themeModeRef() {
    return readonly(this.currentMode);
  }

  public get isDarkRef() {
    return readonly(this.isDarkActive);
  }

  public setThemeMode(mode: ThemeMode) {
    this.currentMode.value = mode;
    try {
      localStorage.setItem(STORAGE_KEY, mode);
    } catch {}
    this.applyTheme();
  }

  public applyTheme() {
    if (typeof window === 'undefined') return;

    const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false;
    const isDark = this.currentMode.value === 'dark' || (this.currentMode.value === 'system' && prefersDark);
    this.isDarkActive.value = isDark;

    const root = document.documentElement;
    root.classList.toggle('dark', isDark);
    root.setAttribute('data-theme', isDark ? 'dark' : 'light');
    root.style.backgroundColor = isDark ? DARK_BG : LIGHT_BG;
    root.style.color = isDark ? DARK_FG : LIGHT_FG;
  }
}

export const themeManager = new ThemeManager();
