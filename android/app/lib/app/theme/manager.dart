import 'package:diting_android/ui/ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';

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

  final String? fontFamily;

  final bool useSystemFonts;

  final bool transparentPage;

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
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const Icon(TablerIcons.chevron_left),
      closeButtonIconBuilder: (_) => const Icon(TablerIcons.x),
    ),
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

class AppThemeCache {
  static const maxEntries = 16;

  final Map<AppThemeSpec, ThemeData> _themes = {};

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
    if (_themes.length >= maxEntries) {
      _themes.remove(_themes.keys.first);
    }
    return _themes[spec] = buildAppTheme(
      spec,
      platform: platform,
      locales: locales,
    );
  }

  void clear() => _themes.clear();
}

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

  final bool transparentPage;

  final String? fontFamily;

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
