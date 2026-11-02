import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';

/// The inputs a theme is assembled from. Equal [AppThemeSpec]s must produce the same
/// [ThemeData], which lets [AppThemeCache] skip a rebuild.
@immutable
class AppThemeSpec {
  const AppThemeSpec({
    required this.seedColor,
    required this.brightness,
    this.pureBlack = false,
    this.style = ColorStyle.vivid,
    this.transparentPage = false,
    this.fontFamily,
    this.useSystemFonts = false,
  });

  final Color seedColor;
  final Brightness brightness;
  final bool pureBlack;
  final ColorStyle style;

  /// Overrides `ThemeData.fontFamily` (`.withAppTypography` rewrites sizes but keeps the family);
  /// null keeps the platform default from `appFontFamilyFallback`.
  final String? fontFamily;

  /// Ignores [fontFamily] and `appFontFamilyFallback`, leaving the font to the engine's system
  /// default. The desktop window opts in so it draws exactly like a native Windows app; Android
  /// keeps the fallback chain its Han glyphs depend on.
  final bool useSystemFonts;

  /// Makes the page background transparent so the wallpaper shows through; same as upstream
  /// `DITINGTheme(transparentBackground)`.
  final bool transparentPage;

  /// Only used by the settings previews; the app always builds both specs from an [AppThemePair].
  AppThemeSpec copyWith({
    Color? seedColor,
    Brightness? brightness,
    bool? pureBlack,
    ColorStyle? style,
    bool? transparentPage,
    String? fontFamily,
    bool? useSystemFonts,
  }) => AppThemeSpec(
    seedColor: seedColor ?? this.seedColor,
    brightness: brightness ?? this.brightness,
    pureBlack: pureBlack ?? this.pureBlack,
    style: style ?? this.style,
    transparentPage: transparentPage ?? this.transparentPage,
    fontFamily: fontFamily ?? this.fontFamily,
    useSystemFonts: useSystemFonts ?? this.useSystemFonts,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppThemeSpec &&
          other.seedColor == seedColor &&
          other.brightness == brightness &&
          other.pureBlack == pureBlack &&
          other.style == style &&
          other.transparentPage == transparentPage &&
          other.fontFamily == fontFamily &&
          other.useSystemFonts == useSystemFonts;

  @override
  int get hashCode => Object.hash(
    seedColor,
    brightness,
    pureBlack,
    style,
    transparentPage,
    fontFamily,
    useSystemFonts,
  );
}

/// Builds the theme as upstream `theme_manager.dart`: seeded scheme, `.toPureBlack` (dark only),
/// `.withAppShapes`, `.withAppSurfaces`, `.withAppTypography`. Order is load-bearing:
/// `withAppSurfaces` reads the resolved `colorScheme`, so it must follow `toPureBlack`.
ThemeData buildAppTheme(
  AppThemeSpec spec, {
  TargetPlatform? platform,
  List<Locale> locales = const [Locale('zh', 'CN')],
}) {
  final dark = spec.brightness == Brightness.dark;
  final scheme = seededColorScheme(
    seedColor: spec.seedColor,
    brightness: spec.brightness,
    style: spec.style,
  ).toPureBlack(spec.pureBlack);
  final target = platform ?? defaultTargetPlatform;
  final transparent = spec.transparentPage;
  return ThemeData(
    useMaterial3: true,
    // Android uses the system Activity transition (Android 14+ FadeForwards) for every page and no
    // predictive back; a missing entry would fall back to `ZoomPageTransitionsBuilder`. Other
    // platforms use SharedAxis, `fuchsia` excepted.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: commonSharedXPageTransitions,
        TargetPlatform.windows: commonSharedXPageTransitions,
        TargetPlatform.macOS: commonSharedXPageTransitions,
        TargetPlatform.linux: commonSharedXPageTransitions,
      },
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const GlyphIcon(AppGlyphs.chevronBack),
      closeButtonIconBuilder: (_) => const GlyphIcon(AppGlyphs.close),
    ),
    // Transparent page background only; cards and sheets stay opaque.
    colorScheme: scheme,
    fontFamily: spec.useSystemFonts ? null : spec.fontFamily,
    fontFamilyFallback: spec.useSystemFonts
        ? null
        : appFontFamilyFallback(platform: target, locales: locales),
    extensions: [if (dark) ElevatedColorScheme(scheme.elevated)],
  ).withAppShapes.withAppSurfaces.withAppTypography.copyWith(
    scaffoldBackgroundColor: transparent ? Colors.transparent : null,
  );
}

/// Caches the last theme per brightness. [ThemeData] never compares equal to a fresh one and
/// [ThemeCrossFade] keys its cross-fade off that, so an uncached rebuild on every unrelated state
/// change would flash the screen.
class AppThemeCache {
  /// Bounded so a long drag across the palette picker cannot grow the map; 16 covers 9 palettes
  /// times 2 brightness.
  static const maxEntries = 16;

  final Map<AppThemeSpec, ThemeData> _themes = {};

  /// Number of cached themes; tests assert the bound.
  int get length => _themes.length;

  ThemeData of(
    AppThemeSpec spec, {
    TargetPlatform? platform,
    List<Locale> locales = const [Locale('zh', 'CN')],
  }) {
    final cached = _themes[spec];
    if (cached != null) {
      return cached;
    }
    // Insertion order is eviction order and the set is tiny, so plain FIFO is enough.
    if (_themes.length >= maxEntries) {
      _themes.remove(_themes.keys.first);
    }
    return _themes[spec] = buildAppTheme(
      spec,
      platform: platform,
      locales: locales,
    );
  }

  /// Drops everything; only tests and a locale switch need this.
  void clear() => _themes.clear();
}

/// A convenience wrapper: the light and dark themes a `MaterialApp` wants.
class AppThemePair {
  AppThemePair({
    required this.seedColor,
    required this.pureBlack,
    this.style = ColorStyle.vivid,
    this.transparentPage = false,
    this.fontFamily,
    this.useSystemFonts = false,
  });

  final Color seedColor;
  final bool pureBlack;
  final ColorStyle style;

  /// True when a custom background is on: page background is transparent.
  final bool transparentPage;

  /// Font family chosen on `/font-family`; null keeps the platform default.
  final String? fontFamily;

  /// Drops [fontFamily] and the platform fallback chain; see [AppThemeSpec.useSystemFonts].
  final bool useSystemFonts;

  AppThemeSpec get lightSpec => AppThemeSpec(
    seedColor: seedColor,
    brightness: Brightness.light,
    style: style,
    transparentPage: transparentPage,
    fontFamily: fontFamily,
    useSystemFonts: useSystemFonts,
  );

  AppThemeSpec get darkSpec => AppThemeSpec(
    seedColor: seedColor,
    brightness: Brightness.dark,
    pureBlack: pureBlack,
    style: style,
    transparentPage: transparentPage,
    fontFamily: fontFamily,
    useSystemFonts: useSystemFonts,
  );
}
