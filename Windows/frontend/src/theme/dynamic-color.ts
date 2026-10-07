import {
  argbFromHex,
  hexFromArgb,
  Hct,
  SchemeContent,
  MaterialDynamicColors,
} from '@material/material-color-utilities';

export type ThemeMode = 'light' | 'dark' | 'system';

/**
 * Material Design 经典天蓝色作为谛听官方基准主色
 */
export const CLASSIC_SKY_BLUE = '#0288D1';

const materialColorTokens: Record<string, any> = {
  background: MaterialDynamicColors.background,
  'on-background': MaterialDynamicColors.onBackground,
  surface: MaterialDynamicColors.surface,
  'surface-dim': MaterialDynamicColors.surfaceDim,
  'surface-bright': MaterialDynamicColors.surfaceBright,
  'surface-container-lowest': MaterialDynamicColors.surfaceContainerLowest,
  'surface-container-low': MaterialDynamicColors.surfaceContainerLow,
  'surface-container': MaterialDynamicColors.surfaceContainer,
  'surface-container-high': MaterialDynamicColors.surfaceContainerHigh,
  'surface-container-highest': MaterialDynamicColors.surfaceContainerHighest,
  'on-surface': MaterialDynamicColors.onSurface,
  'surface-variant': MaterialDynamicColors.surfaceVariant,
  'on-surface-variant': MaterialDynamicColors.onSurfaceVariant,
  'inverse-surface': MaterialDynamicColors.inverseSurface,
  'inverse-on-surface': MaterialDynamicColors.inverseOnSurface,
  outline: MaterialDynamicColors.outline,
  'outline-variant': MaterialDynamicColors.outlineVariant,
  shadow: MaterialDynamicColors.shadow,
  scrim: MaterialDynamicColors.scrim,
  'surface-tint': MaterialDynamicColors.surfaceTint,
  primary: MaterialDynamicColors.primary,
  'on-primary': MaterialDynamicColors.onPrimary,
  'primary-container': MaterialDynamicColors.primaryContainer,
  'on-primary-container': MaterialDynamicColors.onPrimaryContainer,
  'inverse-primary': MaterialDynamicColors.inversePrimary,
  secondary: MaterialDynamicColors.secondary,
  'on-secondary': MaterialDynamicColors.onSecondary,
  'secondary-container': MaterialDynamicColors.secondaryContainer,
  'on-secondary-container': MaterialDynamicColors.onSecondaryContainer,
  tertiary: MaterialDynamicColors.tertiary,
  'on-tertiary': MaterialDynamicColors.onTertiary,
  'tertiary-container': MaterialDynamicColors.tertiaryContainer,
  'on-tertiary-container': MaterialDynamicColors.onTertiaryContainer,
  error: MaterialDynamicColors.error,
  'on-error': MaterialDynamicColors.onError,
  'error-container': MaterialDynamicColors.errorContainer,
  'on-error-container': MaterialDynamicColors.onErrorContainer,
};

class ThemeManager {
  private readonly seedColor: string = CLASSIC_SKY_BLUE;
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

    const scheme = new SchemeContent(
      Hct.fromInt(argbFromHex(this.seedColor)),
      this.isDarkActive,
      0,
    );

    const root = document.documentElement;
    for (const [key, dynColor] of Object.entries(materialColorTokens)) {
      const hex = hexFromArgb(dynColor.getArgb(scheme));
      root.style.setProperty(`--md-sys-color-${key}`, hex);
    }

    if (this.isDarkActive) {
      root.classList.add('dark');
      root.setAttribute('data-theme', 'dark');
    } else {
      root.classList.remove('dark');
      root.setAttribute('data-theme', 'light');
    }

    // 同步给页面背景和文字颜色
    const bgColor = hexFromArgb(materialColorTokens['background'].getArgb(scheme));
    const textColor = hexFromArgb(materialColorTokens['on-background'].getArgb(scheme));
    root.style.backgroundColor = bgColor;
    root.style.color = textColor;

    this.listeners.forEach((fn) => fn());
  }

  public onChange(fn: () => void) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }
}

export const themeManager = new ThemeManager();
