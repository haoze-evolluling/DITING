/// Bottom bar style, tab transition and liquid glass: in memory only, so they reset on restart.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

/// Bottom bar look; [BottomBarDestination] decides which tabs exist, not how they are drawn.
enum BottomBarStyle {
  floating,
  docked;

  String label(AppL10n l10n) => switch (this) {
    BottomBarStyle.floating => l10n.bottomBarStyleFloating,
    BottomBarStyle.docked => l10n.bottomBarStyleDocked,
  };

  bool get isFloating => this == floating;

  static BottomBarStyle fromStorageValue(String? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => floating);
}

class BottomBarStyleNotifier extends Notifier<BottomBarStyle> {
  @override
  BottomBarStyle build() =>
      BottomBarStyle.fromStorageValue(_settings(ref).bottomBarStyleRaw);

  void select(BottomBarStyle style) {
    state = style;
    _settings(ref).setBottomBarStyleRaw(style.name);
  }
}

final bottomBarStyleProvider =
    NotifierProvider<BottomBarStyleNotifier, BottomBarStyle>(
      BottomBarStyleNotifier.new,
    );

/// Tab switch animation; `none` and `scale` extend the upstream slide/fade so all four can be
/// previewed.
enum TabTransition {
  none,
  fade,
  slide,
  scale;

  String label(AppL10n l10n) => switch (this) {
    TabTransition.none => l10n.tabTransitionNone,
    TabTransition.fade => l10n.tabTransitionFade,
    TabTransition.slide => l10n.tabTransitionSlide,
    TabTransition.scale => l10n.tabTransitionScale,
  };

  static TabTransition fromStorageValue(String? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => slide);
}

class TabTransitionNotifier extends Notifier<TabTransition> {
  @override
  TabTransition build() =>
      TabTransition.fromStorageValue(_settings(ref).tabTransitionRaw);

  void select(TabTransition transition) {
    state = transition;
    _settings(ref).setTabTransitionRaw(transition.name);
  }
}

final tabTransitionProvider =
    NotifierProvider<TabTransitionNotifier, TabTransition>(
      TabTransitionNotifier.new,
    );

/// Liquid glass: off / standard / ultra (quality tiers live in `lib/ui/liquid_glass.dart`).
enum LiquidGlassMode {
  none,
  standard,
  ultra;

  String label(AppL10n l10n) => switch (this) {
    LiquidGlassMode.none => l10n.commonOff,
    LiquidGlassMode.standard => l10n.glassModeStandard,
    LiquidGlassMode.ultra => l10n.glassModeUltra,
  };

  bool get enabled => this != none;

  LiquidGlassQuality get quality =>
      this == ultra ? LiquidGlassQuality.ultra : LiquidGlassQuality.standard;

  static LiquidGlassMode fromStorageValue(String? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => none);
}

class LiquidGlassModeNotifier extends Notifier<LiquidGlassMode> {
  @override
  LiquidGlassMode build() =>
      LiquidGlassMode.fromStorageValue(_settings(ref).liquidGlassModeRaw);

  void select(LiquidGlassMode mode) {
    state = mode;
    _settings(ref).setLiquidGlassModeRaw(mode.name);
  }
}

final liquidGlassModeProvider =
    NotifierProvider<LiquidGlassModeNotifier, LiquidGlassMode>(
      LiquidGlassModeNotifier.new,
    );

/// Selected font family; null means the system default. Persisted, and applied app-wide in
/// `lib/app/theme/manager.dart`.
class FontFamilyNotifier extends Notifier<String?> {
  @override
  String? build() => _settings(ref).fontFamily;

  void select(String? family) {
    state = family;
    _settings(ref).setFontFamily(family);
  }
}

final selectedFontFamilyProvider =
    NotifierProvider<FontFamilyNotifier, String?>(FontFamilyNotifier.new);

/// Brightness the theme preview page compares: light / dark.
enum PreviewBrightness {
  light(Brightness.light),
  dark(Brightness.dark);

  const PreviewBrightness(this.brightness);

  String label(AppL10n l10n) => switch (this) {
    PreviewBrightness.light => l10n.previewBrightnessLight,
    PreviewBrightness.dark => l10n.previewBrightnessDark,
  };

  final Brightness brightness;
}
