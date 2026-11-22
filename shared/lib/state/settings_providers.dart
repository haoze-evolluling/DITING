library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/native/background_bridge.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

LegacySettings _settings(Ref ref) => ref.read(legacySettingsProvider);

void _bump(Ref ref) => ref.read(legacySettingsRevisionProvider.notifier).bump();

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

class LogRetentionNotifier extends Notifier<int> {
  @override
  int build() {
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

class ForegroundBackgroundNotifier extends Notifier<ForegroundBackgroundState> {
  @override
  ForegroundBackgroundState build() {
    ref.watch(legacySettingsProvider);
    final settings = _settings(ref);
    return ForegroundBackgroundState(
      hideFromRecents: settings.hideFromRecentsEnabled,
      bypassLan: settings.bypassLanEnabled,
      tunnelIpv6: settings.tunnelIpv6Enabled,
      dnsAaaa: settings.dnsAaaaEnabled,
      routeAddress: settings.vpnRouteAddress,
      routeExcludeAddress: settings.vpnRouteExcludeAddress,
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

  void setTunnelIpv6(bool value) {
    state = state.copyWith(tunnelIpv6: value);
    _settings(ref).setTunnelIpv6Enabled(value);
    _bump(ref);
  }

  void setDnsAaaa(bool value) {
    state = state.copyWith(dnsAaaa: value);
    _settings(ref).setDnsAaaaEnabled(value);
    _bump(ref);
  }

  void setRouteAddress(Iterable<String> values) {
    final routes = _routeList(values);
    state = state.copyWith(routeAddress: routes);
    _settings(ref).setVpnRouteAddress(routes);
    _bump(ref);
  }

  void setRouteExclude(Iterable<String> values) {
    final routes = _routeList(values);
    state = state.copyWith(routeExcludeAddress: routes);
    _settings(ref).setVpnRouteExcludeAddress(routes);
    _bump(ref);
  }

  static List<String> _routeList(Iterable<String> values) {
    final routes = {
      for (final item in values)
        if (item.trim().isNotEmpty) item.trim(),
    };
    return routes.toList()..sort();
  }
}

class ForegroundBackgroundState {
  const ForegroundBackgroundState({
    required this.hideFromRecents,
    required this.bypassLan,
    required this.tunnelIpv6,
    required this.dnsAaaa,
    required this.routeAddress,
    required this.routeExcludeAddress,
  });

  final bool hideFromRecents;
  final bool bypassLan;
  final bool tunnelIpv6;
  final bool dnsAaaa;
  final List<String> routeAddress;
  final List<String> routeExcludeAddress;

  ForegroundBackgroundState copyWith({
    bool? hideFromRecents,
    bool? bypassLan,
    bool? tunnelIpv6,
    bool? dnsAaaa,
    List<String>? routeAddress,
    List<String>? routeExcludeAddress,
  }) => ForegroundBackgroundState(
    hideFromRecents: hideFromRecents ?? this.hideFromRecents,
    bypassLan: bypassLan ?? this.bypassLan,
    tunnelIpv6: tunnelIpv6 ?? this.tunnelIpv6,
    dnsAaaa: dnsAaaa ?? this.dnsAaaa,
    routeAddress: routeAddress ?? this.routeAddress,
    routeExcludeAddress: routeExcludeAddress ?? this.routeExcludeAddress,
  );
}

final foregroundBackgroundProvider =
    NotifierProvider<ForegroundBackgroundNotifier, ForegroundBackgroundState>(
      ForegroundBackgroundNotifier.new,
    );

enum AppLanguageMode {
  system('system'),
  chinese('chinese'),
  english('english');

  const AppLanguageMode(this.storageValue);

  final String storageValue;

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

  void select(String uri) {
    if (!state.uris.contains(uri)) return;
    state = state.copyWith(currentUri: uri);
    _settings(ref).setCustomBackgroundUri(uri);
    _bump(ref);
  }

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
    ref.read(backgroundBridgeProvider).release(uri);
    _bump(ref);
  }

  void _storeRemoveCurrent(LegacySettings settings) {
    settings.setCustomBackgroundUri('');
  }

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

final backgroundBridgeProvider = Provider<BackgroundBridge>(
  (ref) => BackgroundBridge(),
);

class StartupUpdateCheckNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).disableStartupUpdateCheck;

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

class AutoStartOnBootNotifier extends Notifier<bool> {
  @override
  bool build() => _settings(ref).autoStartOnBootEnabled;

  void toggle(bool value) {
    state = value;
    _settings(ref).setAutoStartOnBootEnabled(value);
    _bump(ref);
  }
}

final autoStartOnBootProvider = NotifierProvider<AutoStartOnBootNotifier, bool>(
  AutoStartOnBootNotifier.new,
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
