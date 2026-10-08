export type ThemeMode = 'light' | 'dark' | 'system';

/**
 * 谛听官方基准品牌主色：冰川蔚蓝主题体系
 * 主色：#2b60ab (高对比度品牌主色)
 * 容器辅助色：#d4e3ff (浅蓝主题核心色)
 */
export const BRAND_PRIMARY_BLUE = '#2b60ab';
export const BRAND_CONTAINER_BLUE = '#d4e3ff';
export const CLASSIC_SKY_BLUE = BRAND_PRIMARY_BLUE; // 向后兼容别名

class ThemeManager {
  private readonly seedColor: string = BRAND_PRIMARY_BLUE;
  private mode: ThemeMode = 'system';
  private isDarkActive: boolean = false;
  private listeners: Set<() => void> = new Set();

  constructor() {
    this.init();
  }

  private init() {
    const savedMode = localStorage.getItem('diting_theme_mode') as ThemeMode;
    if (savedMode === 'light' || savedMode === 'dark' || savedMode === 'system') {
      this.mode = savedMode;
    }

    // 监听操作系统明暗主题变更
    if (typeof window !== 'undefined' && window.matchMedia) {
      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
        if (this.mode === 'system') {
          this.applyTheme();
        }
      });
    }
  }

  public getSeedColor(): string {
    return this.seedColor;
  }

  public getThemeMode(): ThemeMode {
    return this.mode;
  }

  public isDark(): boolean {
    return this.isDarkActive;
  }

  public setThemeMode(mode: ThemeMode) {
    this.mode = mode;
    localStorage.setItem('diting_theme_mode', mode);
    this.applyTheme();
  }

  public applyTheme() {
    if (typeof window === 'undefined') return;
    const prefersDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    this.isDarkActive = this.mode === 'dark' || (this.mode === 'system' && prefersDark);

    const root = document.documentElement;

    if (this.isDarkActive) {
      root.classList.add('dark');
      root.setAttribute('data-theme', 'dark');
      root.style.backgroundColor = '#090d16';
      root.style.color = '#f8fafc';
    } else {
      root.classList.remove('dark');
      root.setAttribute('data-theme', 'light');
      root.style.backgroundColor = '#f8fafc';
      root.style.color = '#0f172a';
    }

    this.listeners.forEach((fn) => fn());
  }

  public onChange(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}

export const themeManager = new ThemeManager();
