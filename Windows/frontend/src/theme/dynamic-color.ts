export type ThemeMode = 'light' | 'dark' | 'system';

/**
 * 谛听官方基准品牌主色：Material 3 睡莲蓝主题体系 (与安卓端完全对齐)
 * 浅色主色：#36618E (典雅深邃睡莲蓝)
 * 浅色容器色：#D1E4FF (浅冰蓝容器底色)
 * 深色主色：#A0CAFD (纯净浅天蓝)
 * 深色容器色：#1A4975 (深沉幽蓝容器底色)
 */
export const BRAND_PRIMARY_BLUE = '#36618E';
export const BRAND_CONTAINER_BLUE = '#D1E4FF';
export const BRAND_DARK_PRIMARY = '#A0CAFD';
export const BRAND_DARK_CONTAINER = '#1A4975';
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
      root.style.backgroundColor = '#111418';
      root.style.color = '#E1E2E8';
    } else {
      root.classList.remove('dark');
      root.setAttribute('data-theme', 'light');
      root.style.backgroundColor = '#F8F9FF';
      root.style.color = '#191C20';
    }

    this.listeners.forEach((fn) => fn());
  }

  public onChange(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}

export const themeManager = new ThemeManager();
