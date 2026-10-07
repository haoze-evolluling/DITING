import {
  argbFromHex,
  hexFromArgb,
  Hct,
  SchemeContent,
  MaterialDynamicColors,
} from '@material/material-color-utilities';

export type ThemeMode = 'light' | 'dark' | 'system';

export interface PresetColor {
  name: string;
  hex: string;
}

export const PRESET_SEED_COLORS: PresetColor[] = [
  { name: '谛听碧蓝 (Default)', hex: '#00668B' },
  { name: '深海幽蓝', hex: '#0061A4' },
  { name: '青翠松柏', hex: '#006A60' },
  { name: '自然青翠', hex: '#2E6A38' },
  { name: '紫晶贵胄', hex: '#6750A4' },
  { name: '赤霞晚照', hex: '#9C4146' },
  { name: '琥珀流金', hex: '#7A5900' },
  { name: '暗金玄黑', hex: '#586249' },
];

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
  private seedColor: string = '#00668B';
  private mode: ThemeMode = 'system';
  private useSystemAccent: boolean = false;
  private isDarkActive: boolean = false;
  private listeners: Set<() => void> = new Set();

  constructor() {
    this.init();
  }

  private init() {
    const savedSeed = localStorage.getItem('diting_seed_color');
    if (savedSeed && /^#[0-9A-Fa-f]{6}$/.test(savedSeed)) {
      this.seedColor = savedSeed;
    }
    const savedMode = localStorage.getItem('diting_theme_mode') as ThemeMode;
    if (savedMode === 'light' || savedMode === 'dark' || savedMode === 'system') {
      this.mode = savedMode;
    }
    this.useSystemAccent = localStorage.getItem('diting_use_accent') === 'true';

    // 监听操作系统明暗主题变更
    if (window.matchMedia) {
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

  public isUsingSystemAccent(): boolean {
    return this.useSystemAccent;
  }

  public isDark(): boolean {
    return this.isDarkActive;
  }

  public setSeedColor(hex: string) {
    if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return;
    this.seedColor = hex;
    localStorage.setItem('diting_seed_color', hex);
    this.applyTheme();
  }

  public setThemeMode(mode: ThemeMode) {
    this.mode = mode;
    localStorage.setItem('diting_theme_mode', mode);
    this.applyTheme();
  }

  public setUseSystemAccent(enable: boolean, accentColor?: string) {
    this.useSystemAccent = enable;
    localStorage.setItem('diting_use_accent', String(enable));
    if (enable && accentColor && /^#[0-9A-Fa-f]{6}$/.test(accentColor)) {
      this.seedColor = accentColor;
      localStorage.setItem('diting_seed_color', accentColor);
    }
    this.applyTheme();
  }

  public applyTheme() {
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
