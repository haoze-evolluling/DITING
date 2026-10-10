/** 谛听 (DITING) 主题管理：浅色 / 深色 / 跟随系统 */

export type ThemeMode = 'light' | 'dark' | 'system';

const STORAGE_KEY = 'diting_theme_mode';
const DARK_BG = '#111418';
const DARK_FG = '#E1E2E8';
const LIGHT_BG = '#F8F9FF';
const LIGHT_FG = '#191C20';

/**
 * 主题切换只做两件事：在 <html> 上切换 dark 类 / data-theme 属性，
 * 并更新根元素底色（避免页面切换瞬间闪白）。
 */
class ThemeManager {
  private mode: ThemeMode = 'system';

  constructor() {
    this.init();
  }

  private init() {
    const saved = localStorage.getItem(STORAGE_KEY) as ThemeMode;
    if (saved === 'light' || saved === 'dark' || saved === 'system') {
      this.mode = saved;
    }

    // 跟随系统时响应操作系统明暗主题变更
    if (typeof window !== 'undefined' && window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        if (this.mode === 'system') {
          this.applyTheme();
        }
      });
    }
  }

  public getThemeMode(): ThemeMode {
    return this.mode;
  }

  public setThemeMode(mode: ThemeMode) {
    this.mode = mode;
    localStorage.setItem(STORAGE_KEY, mode);
    this.applyTheme();
  }

  public applyTheme() {
    if (typeof window === 'undefined') return;

    const prefersDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches;
    const isDark = this.mode === 'dark' || (this.mode === 'system' && prefersDark);

    const root = document.documentElement;
    root.classList.toggle('dark', isDark);
    root.setAttribute('data-theme', isDark ? 'dark' : 'light');
    root.style.backgroundColor = isDark ? DARK_BG : LIGHT_BG;
    root.style.color = isDark ? DARK_FG : LIGHT_FG;
  }
}

export const themeManager = new ThemeManager();
