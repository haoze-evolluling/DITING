/// Appearance state: theme, palette, text scale, opacity, home text and bottom bar, under the 1.4.3
/// keys.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/app/theme/colors.dart';
import 'package:diting_shared/app/theme/layout.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

class ThemeModeNotifier extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() =>
      AppThemeMode.fromStorageValue(_settings(ref).themeModeRaw);

  void select(AppThemeMode mode) {
    state = mode;
    _settings(ref).setThemeModeRaw(mode.storageValue);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

class PaletteNotifier extends Notifier<AppPalette> {
  @override
  AppPalette build() => AppPalette.fromStorageValue(_settings(ref).paletteRaw);

  void select(AppPalette palette) {
    state = palette;
    _settings(ref).setPaletteRaw(palette.storageValue);
  }
}

final paletteProvider = NotifierProvider<PaletteNotifier, AppPalette>(
  PaletteNotifier.new,
);

class PureBlackNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).pureBlackEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setPureBlackEnabled(value);
  }
}

final pureBlackProvider = NotifierProvider<PureBlackNotifier, bool>(
  PureBlackNotifier.new,
);

/// Raw user text scale, before [clampTextScale].
class TextScaleNotifier extends Notifier<double> {
  @override
  double build() => clampTextScale(_settings(ref).textScale);

  void set(double value) {
    state = clampTextScale(value);
    _settings(ref).setTextScale(state);
  }
}

final textScaleProvider = NotifierProvider<TextScaleNotifier, double>(
  TextScaleNotifier.new,
);

/// Opacity of the home blocks that are not dashboard cards (`home_*_opacity`). The provider and
/// resolution blocks became cards, so their transparency is no longer configurable here.
enum HomeLayer {
  powerButton('home_power_button_opacity'),
  poem('home_poem_opacity');

  const HomeLayer(this.storageKey);

  String label(AppL10n l10n) => switch (this) {
    HomeLayer.powerButton => l10n.homeLayerPowerButton,
    HomeLayer.poem => l10n.homeLayerPoem,
  };

  /// Legacy `AppearanceSettingsStore` key names.
  final String storageKey;
}

class HomeOpacityNotifier extends Notifier<Map<HomeLayer, double>> {
  static const _defaults = {HomeLayer.powerButton: 1.0, HomeLayer.poem: 1.0};

  @override
  Map<HomeLayer, double> build() {
    final settings = _settings(ref);
    return {
      for (final layer in HomeLayer.values)
        layer: settings.homeOpacity(layer.storageKey),
    };
  }

  void set(HomeLayer layer, double value) {
    final clamped = value.clamp(0.1, 1.0);
    state = {...state, layer: clamped};
    _settings(ref).setHomeOpacity(layer.storageKey, clamped);
  }

  void resetAll() {
    state = _defaults;
    final settings = _settings(ref);
    for (final layer in HomeLayer.values) {
      settings.setHomeOpacity(layer.storageKey, 1);
    }
  }
}

final homeOpacityProvider =
    NotifierProvider<HomeOpacityNotifier, Map<HomeLayer, double>>(
      HomeOpacityNotifier.new,
    );

/// Home sentence per run state (running / stopped); empty hides it.
class HomeSentenceNotifier
    extends Notifier<({String running, String stopped})> {
  @override
  ({String running, String stopped}) build() => _settings(ref).homeSentences;

  void set({String? running, String? stopped}) {
    state = (
      running: running ?? state.running,
      stopped: stopped ?? state.stopped,
    );
    _settings(ref)
        .setHomeSentences(running: state.running, stopped: state.stopped);
  }

  void reset() {
    state = (
      running: LegacySettings.defaultRunningSentence(currentL10n),
      stopped: LegacySettings.defaultStoppedSentence(currentL10n),
    );
    _settings(ref)
        .setHomeSentences(running: state.running, stopped: state.stopped);
  }
}

final homeSentenceProvider =
    NotifierProvider<HomeSentenceNotifier, ({String running, String stopped})>(
      HomeSentenceNotifier.new,
    );

/// Selectable bottom bar tabs: 2 to [maxDockDestinations].
enum BottomBarDestination {
  home('home', AppGlyphs.dashboard),
  featureHub('feature_hub', AppGlyphs.puzzle),
  logDashboard('log_dashboard', AppGlyphs.logs),
  appTraffic('app_traffic_stats', AppGlyphs.dataUsage),
  networkTools('network_tools', AppGlyphs.tools),
  settings('settings', AppGlyphs.settings);

  const BottomBarDestination(this.storageValue, this.glyph);

  String label(AppL10n l10n) => switch (this) {
    BottomBarDestination.home => l10n.bottomBarHome,
    BottomBarDestination.featureHub => l10n.bottomBarFeatureHub,
    BottomBarDestination.logDashboard => l10n.bottomBarLogDashboard,
    BottomBarDestination.appTraffic => l10n.bottomBarAppTraffic,
    BottomBarDestination.networkTools => l10n.bottomBarNetworkTools,
    BottomBarDestination.settings => l10n.bottomBarSettings,
  };

  /// Ids as stored in the legacy `bottom_bar_destinations` array.
  final String storageValue;

  final Glyph glyph;

  static BottomBarDestination? fromStorageValue(String value) {
    for (final destination in values) {
      if (destination.storageValue == value) {
        return destination;
      }
    }
    return null;
  }
}

class BottomBarNotifier extends Notifier<List<BottomBarDestination>> {
  static const _defaults = [
    BottomBarDestination.home,
    BottomBarDestination.featureHub,
    BottomBarDestination.logDashboard,
  ];

  @override
  List<BottomBarDestination> build() {
    final restored = [
      for (final id in _settings(ref).bottomBarIds)
        ?BottomBarDestination.fromStorageValue(id),
    ];
    return restored.length < 2 ? _defaults : restored;
  }

  void _save(List<BottomBarDestination> destinations) {
    _settings(ref).setBottomBarIds([
      for (final destination in destinations) destination.storageValue,
    ]);
  }

  /// Keeps 2 to [maxDockDestinations] items; out-of-range edits are ignored.
  bool toggle(BottomBarDestination destination) {
    final current = state;
    if (current.contains(destination)) {
      if (current.length <= 2) {
        return false;
      }
      state = [...current]..remove(destination);
      _save(state);
      return true;
    }
    if (current.length >= maxDockDestinations) {
      return false;
    }
    state = [...current, destination];
    _save(state);
    return true;
  }

  /// Reorders the dock; [ReorderableListView.onReorderItem]'s `newIndex` is already adjusted.
  void move(int oldIndex, int newIndex) {
    final length = state.length;
    if (oldIndex < 0 ||
        oldIndex >= length ||
        newIndex < 0 ||
        newIndex >= length ||
        newIndex == oldIndex) {
      return;
    }
    final next = [...state];
    next.insert(newIndex, next.removeAt(oldIndex));
    state = next;
    _save(next);
  }

  void reset() {
    state = _defaults;
    _save(_defaults);
  }
}

final bottomBarProvider =
    NotifierProvider<BottomBarNotifier, List<BottomBarDestination>>(
      BottomBarNotifier.new,
    );

class HapticNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).hapticEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setHapticEnabled(value);
  }
}

final hapticProvider = NotifierProvider<HapticNotifier, bool>(
  HapticNotifier.new,
);

/// Resolution mode: single resolver or race (upstream `ResolutionSettingsStore`).
enum ResolutionMode {
  single('single'),
  smart('smart_prediction'),
  parallel('parallel_race'),
  primaryBackup('primary_backup');

  const ResolutionMode(this.storageValue);

  String label(AppL10n l10n) => switch (this) {
    ResolutionMode.single => l10n.resolutionModeSingle,
    ResolutionMode.smart => l10n.resolutionModeSmart,
    ResolutionMode.parallel => l10n.resolutionModeParallel,
    ResolutionMode.primaryBackup => l10n.resolutionModePrimaryBackup,
  };

  /// Legacy `dns_resolution_mode` values; enum names differ from stored values.
  final String storageValue;

  bool get isSingle => this == single;

  static ResolutionMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => single,
  );
}

class ResolutionModeNotifier extends Notifier<ResolutionMode> {
  @override
  ResolutionMode build() {
    // DNS keys are data-set scoped: following the settings view is what makes a mode switch show
    // that data set's mode instead of the previous one.
    ref.watch(legacySettingsProvider);
    return ResolutionMode.fromStorageValue(_settings(ref).resolutionModeRaw);
  }

  void select(ResolutionMode mode) {
    state = mode;
    _settings(ref).setResolutionModeRaw(mode.storageValue);
  }
}

final resolutionModeProvider =
    NotifierProvider<ResolutionModeNotifier, ResolutionMode>(
      ResolutionModeNotifier.new,
    );
