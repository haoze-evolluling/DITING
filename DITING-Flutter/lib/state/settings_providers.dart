/// Settings-domain state; writes go back to the same `LegacySettings` keys.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/native/background_bridge.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

void _bump(Ref ref) => ref.read(legacySettingsRevisionProvider.notifier).bump();

/// Log recording mode, the three 1.4.3 `DnsLogModeScreen` values; swaps the dashboard body.
enum LegacyLogMode {
  all('all'),
  blockedAndErrors('blocked_and_errors'),
  off('off');

  const LegacyLogMode(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    LegacyLogMode.all => l10n.logModeAllLabel,
    LegacyLogMode.blockedAndErrors => l10n.logModeBlockedLabel,
    LegacyLogMode.off => l10n.logModeOffLabel,
  };

  String description(AppL10n l10n) => switch (this) {
    LegacyLogMode.all => l10n.logModeAllDescription,
    LegacyLogMode.blockedAndErrors => l10n.logModeBlockedDescription,
    LegacyLogMode.off => l10n.logModeOffDescription,
  };

  static LegacyLogMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => LegacyLogMode.all,
  );
}

class LogModeNotifier extends Notifier<LegacyLogMode> {
  @override
  LegacyLogMode build() {
    // `dns_log_mode` lives in the active data set's container.
    ref.watch(legacySettingsProvider);
    return LegacyLogMode.fromStorageValue(_settings(ref).dnsLogModeRaw);
  }

  void select(LegacyLogMode mode) {
    state = mode;
    _settings(ref).setDnsLogModeRaw(mode.storageValue);
    _bump(ref);
  }
}

final logModeProvider = NotifierProvider<LogModeNotifier, LegacyLogMode>(
  LogModeNotifier.new,
);

/// Log retention in days (1-30, default 7).
class LogRetentionNotifier extends Notifier<int> {
  @override
  int build() {
    // `log_retention_days` is stored per data set, like `dns_log_mode`.
    ref.watch(legacySettingsProvider);
    return _settings(ref).logRetentionDays;
  }

  void set(int days) {
    state = days.clamp(1, 30);
    _settings(ref).setLogRetentionDays(state);
    _bump(ref);
  }
}

final logRetentionProvider = NotifierProvider<LogRetentionNotifier, int>(
  LogRetentionNotifier.new,
);

class FloatingLogNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).floatingLogEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setFloatingLogEnabled(value);
    _bump(ref);
  }
}

final floatingLogProvider = NotifierProvider<FloatingLogNotifier, bool>(
  FloatingLogNotifier.new,
);

class FloatingLogPanelSizeNotifier extends Notifier<int> {
  @override
  int build() => _settings(ref).floatingLogPanelSize;

  void set(int value) {
    state = value.clamp(0, 2);
    _settings(ref).setFloatingLogPanelSize(state);
    _bump(ref);
  }
}

final floatingLogPanelSizeProvider =
    NotifierProvider<FloatingLogPanelSizeNotifier, int>(
      FloatingLogPanelSizeNotifier.new,
    );

class FloatingLogOpacityNotifier extends Notifier<double> {
  @override
  double build() => _settings(ref).floatingLogOpacity;

  void set(double value) {
    state = value.clamp(0.3, 1).toDouble();
    _settings(ref).setFloatingLogOpacity(state);
    _bump(ref);
  }
}

final floatingLogOpacityProvider =
    NotifierProvider<FloatingLogOpacityNotifier, double>(
      FloatingLogOpacityNotifier.new,
    );

/// IPv6 mode; `VpnRouteConfig` only distinguishes `auto` from the rest.
enum LegacyIpv6Mode {
  auto('auto'),
  disable('disable'),
  prefer('prefer');

  const LegacyIpv6Mode(this.storageValue);

  final String storageValue;

  String label(AppL10n l10n) => switch (this) {
    LegacyIpv6Mode.auto => l10n.ipv6AutoLabel,
    LegacyIpv6Mode.disable => l10n.ipv6DisableLabel,
    LegacyIpv6Mode.prefer => l10n.ipv6PreferLabel,
  };

  String description(AppL10n l10n) => switch (this) {
    LegacyIpv6Mode.auto => l10n.ipv6AutoDescription,
    LegacyIpv6Mode.disable => l10n.ipv6DisableDescription,
    LegacyIpv6Mode.prefer => l10n.ipv6PreferDescription,
  };

  static LegacyIpv6Mode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => LegacyIpv6Mode.auto,
  );
}

class ForegroundBackgroundNotifier extends Notifier<ForegroundBackgroundState> {
  @override
  ForegroundBackgroundState build() {
    // Bypass-LAN and IPv6 are DNS-domain keys; hide-from-recents stays global but shares the state.
    ref.watch(legacySettingsProvider);
    final settings = _settings(ref);
    return ForegroundBackgroundState(
      hideFromRecents: settings.hideFromRecentsEnabled,
      bypassLan: settings.bypassLanEnabled,
      ipv6Mode: LegacyIpv6Mode.fromStorageValue(settings.ipv6ModeRaw),
    );
  }

  void setHideFromRecents(bool value) {
    state = state.copyWith(hideFromRecents: value);
    _settings(ref).setHideFromRecentsEnabled(value);
    _bump(ref);
  }

  void setBypassLan(bool value) {
    state = state.copyWith(bypassLan: value);
    _settings(ref).setBypassLanEnabled(value);
    _bump(ref);
  }

  void setIpv6Mode(LegacyIpv6Mode mode) {
    state = state.copyWith(ipv6Mode: mode);
    _settings(ref).setIpv6ModeRaw(mode.storageValue);
    _bump(ref);
  }
}

class ForegroundBackgroundState {
  const ForegroundBackgroundState({
    required this.hideFromRecents,
    required this.bypassLan,
    required this.ipv6Mode,
  });

  final bool hideFromRecents;
  final bool bypassLan;
  final LegacyIpv6Mode ipv6Mode;

  ForegroundBackgroundState copyWith({
    bool? hideFromRecents,
    bool? bypassLan,
    LegacyIpv6Mode? ipv6Mode,
  }) => ForegroundBackgroundState(
    hideFromRecents: hideFromRecents ?? this.hideFromRecents,
    bypassLan: bypassLan ?? this.bypassLan,
    ipv6Mode: ipv6Mode ?? this.ipv6Mode,
  );
}

final foregroundBackgroundProvider =
    NotifierProvider<ForegroundBackgroundNotifier, ForegroundBackgroundState>(
      ForegroundBackgroundNotifier.new,
    );

/// Interface language. The storage values are the legacy `app_language_mode` ones, so a
/// configuration written by an older build keeps working. Adding a language is one entry here
/// plus its `lib/l10n/app_<code>.arb` file.
enum AppLanguageMode {
  system('system'),
  chinese('chinese'),
  english('english');

  const AppLanguageMode(this.storageValue);

  final String storageValue;

  /// `null` lets the platform decide (`MaterialApp.locale`), which resolves to the first of
  /// [AppL10n.supportedLocales] for languages the app has no resources for (Chinese).
  Locale? get locale => switch (this) {
    AppLanguageMode.system => null,
    AppLanguageMode.chinese => const Locale('zh'),
    AppLanguageMode.english => const Locale('en'),
  };

  String label(AppL10n l10n) => switch (this) {
    AppLanguageMode.system => l10n.commonFollowSystem,
    AppLanguageMode.chinese => l10n.languageChinese,
    AppLanguageMode.english => l10n.languageEnglish,
  };

  static AppLanguageMode fromStorageValue(String? value) => values.firstWhere(
    (mode) => mode.storageValue == value,
    orElse: () => AppLanguageMode.system,
  );
}

class LanguageNotifier extends Notifier<AppLanguageMode> {
  @override
  AppLanguageMode build() =>
      AppLanguageMode.fromStorageValue(_settings(ref).appLanguageModeRaw);

  void select(AppLanguageMode mode) {
    state = mode;
    _settings(ref).setAppLanguageModeRaw(mode.storageValue);
    _bump(ref);
  }
}

final languageModeProvider =
    NotifierProvider<LanguageNotifier, AppLanguageMode>(LanguageNotifier.new);

/// The locale handed to `MaterialApp.locale`; `null` follows the device language.
final appLocaleProvider = Provider<Locale?>(
  (ref) => ref.watch(languageModeProvider).locale,
);

class NotificationSettingsNotifier extends Notifier<NotificationSettingsState> {
  @override
  NotificationSettingsState build() {
    final settings = _settings(ref);
    final texts = settings.notificationTexts;
    return NotificationSettingsState(
      persistent: settings.notificationPersistent,
      runningText: texts.running,
      stoppedText: texts.stopped,
    );
  }

  void setPersistent(bool value) {
    state = state.copyWith(persistent: value);
    _settings(ref).setNotificationPersistent(value);
    _bump(ref);
  }

  void setRunningText(String value) {
    state = state.copyWith(runningText: value);
    _settings(ref)
        .setNotificationTexts(running: value, stopped: state.stoppedText);
    _bump(ref);
  }

  void setStoppedText(String value) {
    state = state.copyWith(stoppedText: value);
    _settings(ref)
        .setNotificationTexts(running: state.runningText, stopped: value);
    _bump(ref);
  }
}

/// Notification switch and texts; an empty string means the default text. The detail items live
/// in `notificationStatsProvider`.
class NotificationSettingsState {
  const NotificationSettingsState({
    required this.persistent,
    required this.runningText,
    required this.stoppedText,
  });

  final bool persistent;
  final String runningText;
  final String stoppedText;

  NotificationSettingsState copyWith({
    bool? persistent,
    String? runningText,
    String? stoppedText,
  }) => NotificationSettingsState(
    persistent: persistent ?? this.persistent,
    runningText: runningText ?? this.runningText,
    stoppedText: stoppedText ?? this.stoppedText,
  );
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsState>(
      NotificationSettingsNotifier.new,
    );

class CustomBackgroundNotifier extends Notifier<CustomBackgroundState> {
  @override
  CustomBackgroundState build() {
    final settings = _settings(ref);
    return CustomBackgroundState(
      enabled: settings.customBackgroundEnabled,
      currentUri: settings.customBackgroundUri,
      uris: settings.customBackgroundUris,
    );
  }

  void setEnabled(bool value) {
    state = state.copyWith(enabled: value);
    _settings(ref).setCustomBackgroundEnabled(value);
    _bump(ref);
  }

  /// Adds a wallpaper, writing the history list before the current entry (legacy order).
  void add(String uri) {
    if (uri.trim().isEmpty) return;
    final uris = [...state.uris, uri];
    state = state.copyWith(uris: uris, currentUri: uri, enabled: true);
    final settings = _settings(ref);
    settings.setCustomBackgroundUris(uris);
    settings.setCustomBackgroundUri(uri);
    settings.setCustomBackgroundEnabled(true);
    _bump(ref);
  }

  /// Selects an existing wallpaper as the current one.
  void select(String uri) {
    if (!state.uris.contains(uri)) return;
    state = state.copyWith(currentUri: uri);
    _settings(ref).setCustomBackgroundUri(uri);
    _bump(ref);
  }

  /// Removes one wallpaper; removing the current one falls back to the last remaining.
  void remove(String uri) {
    final uris = [
      for (final item in state.uris)
        if (item != uri) item,
    ];
    final nextCurrent = state.currentUri == uri
        ? (uris.isEmpty ? null : uris.last)
        : state.currentUri;
    state = state.copyWith(uris: uris, currentUri: nextCurrent);
    final settings = _settings(ref);
    settings.setCustomBackgroundUris(uris);
    if (nextCurrent == null) {
      _storeRemoveCurrent(settings);
    } else {
      settings.setCustomBackgroundUri(nextCurrent);
    }
    // Drop this image's decode cache so the private directory does not grow.
    ref.read(backgroundBridgeProvider).release(uri);
    _bump(ref);
  }

  void _storeRemoveCurrent(LegacySettings settings) {
    // No delete-key API: an empty string means "unset", as in the legacy store.
    settings.setCustomBackgroundUri('');
  }

  /// Opens the system image picker; null on success or cancel, else the reason.
  Future<String?> pickAndAdd() async {
    final result = await ref.read(backgroundBridgeProvider).pick();
    if (result.ok) {
      add(result.uri!);
      return null;
    }
    if (result.cancelled) return null;
    return currentL10n.imagePickerUnavailable;
  }
}

class CustomBackgroundState {
  const CustomBackgroundState({
    required this.enabled,
    required this.currentUri,
    required this.uris,
  });

  final bool enabled;
  final String? currentUri;
  final List<String> uris;

  CustomBackgroundState copyWith({
    bool? enabled,
    String? currentUri,
    List<String>? uris,
  }) => CustomBackgroundState(
    enabled: enabled ?? this.enabled,
    currentUri: currentUri ?? this.currentUri,
    uris: uris ?? this.uris,
  );
}

final customBackgroundProvider =
    NotifierProvider<CustomBackgroundNotifier, CustomBackgroundState>(
      CustomBackgroundNotifier.new,
    );

/// Background picker channel, replaceable in tests.
final backgroundBridgeProvider = Provider<BackgroundBridge>(
  (ref) => BackgroundBridge(),
);

class StartupUpdateCheckNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).disableStartupUpdateCheck;

  /// Takes the "disable startup check" value; key and switch agree to avoid inversion.
  void toggle(bool value) {
    state = value;
    _settings(ref).setDisableStartupUpdateCheck(value);
    _bump(ref);
  }
}

final startupUpdateCheckProvider =
    NotifierProvider<StartupUpdateCheckNotifier, bool>(
      StartupUpdateCheckNotifier.new,
    );

/// Settings page switch: the VPN services follow a slot taken by another app and reconnect once
/// it is free. Read natively, so it only needs persisting.
class VpnWatchdogNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).vpnWatchdogEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setVpnWatchdogEnabled(value);
    _bump(ref);
  }
}

final vpnWatchdogProvider = NotifierProvider<VpnWatchdogNotifier, bool>(
  VpnWatchdogNotifier.new,
);

/// Settings page switch: the next launch restarts a tunnel that was still meant to run.
class AutoStartOnLaunchNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).autoStartOnLaunchEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setAutoStartOnLaunchEnabled(value);
    _bump(ref);
  }
}

final autoStartOnLaunchProvider =
    NotifierProvider<AutoStartOnLaunchNotifier, bool>(
      AutoStartOnLaunchNotifier.new,
    );

class InitialAgreementNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).initialAgreementAccepted;

  void accept() {
    state = true;
    _settings(ref).setInitialAgreementAccepted(true);
    _bump(ref);
  }
}

final initialAgreementProvider =
    NotifierProvider<InitialAgreementNotifier, bool>(
      InitialAgreementNotifier.new,
    );
