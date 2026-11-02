part of 'legacy_settings.dart';

// Appearance and home-screen settings, all in the global `dns_vpn_prefs` container.

/// Key of one log mode's stored card order; also removed by the upgrade reset registry.
String logDashboardWidgetOrderKey(String mode) =>
    'log_dashboard_widget_order_$mode';

extension LegacyAppearanceSettings on LegacySettings {
  String? get themeModeRaw =>
      _string(LegacySettings.uiContainer, 'app_theme_mode');

  void setThemeModeRaw(String storageValue) => _store.putString(
    LegacySettings.uiContainer,
    'app_theme_mode',
    storageValue,
  );

  String? get paletteRaw =>
      _string(LegacySettings.uiContainer, 'theme_color_style');

  void setPaletteRaw(String storageValue) => _store.putString(
    LegacySettings.uiContainer,
    'theme_color_style',
    storageValue,
  );

  /// `none` / `standard` / `ultra`; persisted, since it decides whether the app renders offscreen.
  String get liquidGlassModeRaw =>
      _string(LegacySettings.uiContainer, 'liquid_glass_mode') ?? 'none';

  void setLiquidGlassModeRaw(String storageValue) => _store.putString(
    LegacySettings.uiContainer,
    'liquid_glass_mode',
    storageValue,
  );

  /// `floating` / `docked`; persisted for the same reason.
  String get bottomBarStyleRaw =>
      _string(LegacySettings.uiContainer, 'bottom_bar_style') ?? 'floating';

  void setBottomBarStyleRaw(String storageValue) => _store.putString(
    LegacySettings.uiContainer,
    'bottom_bar_style',
    storageValue,
  );

  /// `none` / `fade` / `slide` / `scale`; same persistence requirement.
  String get tabTransitionRaw =>
      _string(LegacySettings.uiContainer, 'tab_transition') ?? 'slide';

  void setTabTransitionRaw(String storageValue) => _store.putString(
    LegacySettings.uiContainer,
    'tab_transition',
    storageValue,
  );

  /// Pure black theme, only visible in dark mode; off by default as in 1.4.3.
  bool get pureBlackEnabled =>
      _bool(LegacySettings.uiContainer, 'pure_black_theme', false);

  void setPureBlackEnabled(bool value) =>
      _store.putBool(LegacySettings.uiContainer, 'pure_black_theme', value);

  /// Raw linear text scale; `clampTextScale` applies the layout bounds when read.
  double get textScale =>
      _double(LegacySettings.uiContainer, 'app_text_scale', 1);

  void setTextScale(double value) =>
      _store.putFloat(LegacySettings.uiContainer, 'app_text_scale', value);

  /// `ThemeData.fontFamily` override; a missing or empty value means the platform default.
  String? get fontFamily {
    final raw = _string(LegacySettings.uiContainer, 'app_font_family');
    return raw == null || raw.isEmpty ? null : raw;
  }

  void setFontFamily(String? family) => _store.putString(
    LegacySettings.uiContainer,
    'app_font_family',
    family ?? '',
  );

  /// JSON list of the fonts the user imported; the shape lives in
  /// `lib/data/fonts/font_repository.dart`, which owns the parsing.
  String? get importedFontsRaw =>
      _string(LegacySettings.uiContainer, 'app_imported_fonts');

  void setImportedFontsRaw(String raw) =>
      _store.putString(LegacySettings.uiContainer, 'app_imported_fonts', raw);

  /// Dashboard card order by `DashboardWidget.name`; null when the board was never edited, so the
  /// built-in defaults apply while an emptied board still restores as empty.
  List<String>? get dashboardWidgetOrder => _decodeWidgetNames(
    _string(LegacySettings.uiContainer, 'dashboard_widget_order'),
  );

  /// Log dashboard card order for one log mode (`LegacyLogMode.storageValue`); each mode keeps
  /// its own layout because each mode shows a different card set. Null means never edited.
  List<String>? logDashboardWidgetOrder(String mode) => _decodeWidgetNames(
    _string(LegacySettings.uiContainer, logDashboardWidgetOrderKey(mode)),
  );

  void setLogDashboardWidgetOrder(String mode, List<String> names) =>
      _store.putString(
        LegacySettings.uiContainer,
        logDashboardWidgetOrderKey(mode),
        jsonEncode(names),
      );

  List<String>? _decodeWidgetNames(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return null;
      }
      final names = <String>[];
      for (final item in decoded) {
        if (item is String && item.isNotEmpty && !names.contains(item)) {
          names.add(item);
        }
      }
      return names;
    } on FormatException {
      return null;
    }
  }

  void setDashboardWidgetOrder(List<String> names) => _store.putString(
    LegacySettings.uiContainer,
    'dashboard_widget_order',
    jsonEncode(names),
  );

  /// Which card set [dashboardWidgetOrder] was written with. A missing value means the order
  /// predates a card that has since moved from a fixed block onto the board, so the notifier
  /// inserts that card once and stamps the current version.
  int get dashboardWidgetLayoutVersion =>
      _int(LegacySettings.uiContainer, 'dashboard_widget_layout_version', 0);

  void setDashboardWidgetLayoutVersion(int version) => _store.putInt(
    LegacySettings.uiContainer,
    'dashboard_widget_layout_version',
    version,
  );

  double get componentOpacity => LegacySettings._clampedOpacity(
    _double(LegacySettings.uiContainer, 'home_component_opacity', 1),
  );

  /// Per-element opacity falls back to the shared component opacity.
  double homeOpacity(String storageKey) => LegacySettings._clampedOpacity(
    _double(LegacySettings.uiContainer, storageKey, componentOpacity),
  );

  void setHomeOpacity(String storageKey, double value) => _store.putFloat(
    LegacySettings.uiContainer,
    storageKey,
    LegacySettings._clampedOpacity(value),
  );

  void setHomeComponentOpacity(double value) => _store.putFloat(
    LegacySettings.uiContainer,
    'home_component_opacity',
    LegacySettings._clampedOpacity(value),
  );
  ({String running, String stopped}) get homeSentences => (
    running:
        _string(LegacySettings.uiContainer, 'home_sentence_running') ??
        LegacySettings.defaultRunningSentence(currentL10n),
    stopped:
        _string(LegacySettings.uiContainer, 'home_sentence_stopped') ??
        LegacySettings.defaultStoppedSentence(currentL10n),
  );

  void setHomeSentences({required String running, required String stopped}) {
    _store.putString(
      LegacySettings.uiContainer,
      'home_sentence_running',
      running,
    );
    _store.putString(
      LegacySettings.uiContainer,
      'home_sentence_stopped',
      stopped,
    );
  }

  bool get hapticEnabled =>
      _bool(LegacySettings.uiContainer, 'bottom_bar_haptic_enabled', true);

  void setHapticEnabled(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'bottom_bar_haptic_enabled',
    value,
  );
}
