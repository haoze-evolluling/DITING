library;

import 'package:diting_shared/app/l10n/l10n.dart';

import 'dart:convert';

import 'package:diting_shared/data/prefs/ipv6_mode.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';

part 'legacy_settings_dns.dart';
part 'legacy_settings_hub.dart';
part 'legacy_settings_parity.dart';
part 'legacy_settings_sites.dart';
part 'legacy_settings_appearance.dart';

class LegacySettings {
  LegacySettings(this._store, {String? dnsContainer})
    : dnsContainer = dnsContainer ?? uiContainer;

  final LegacyPrefsStore _store;

  final String dnsContainer;

  static const uiContainer = 'dns_vpn_prefs';

  static const workModeContainer = 'diting_settings';

  static const expressContainer = 'diting_express_prefs';

  static const expressRunningContainer = 'express_vpn_prefs';

  static const notificationContainer = 'notification_settings_prefs';

  static String defaultRunningSentence(AppL10n l10n) => l10n.taglineRunning;
  static String defaultStoppedSentence(AppL10n l10n) => l10n.taglineStopped;

  static const defaultBottomBarIds = ['home', 'feature_hub', 'log_dashboard'];

  static const bottomBarIdValues = {
    'home',
    'feature_hub',
    'log_dashboard',
    'app_traffic_stats',
    'network_tools',
    'settings',
  };

  static const bottomBarMinCount = 2;
  static const bottomBarMaxCount = 4;

  static const subscriptionAutoUpdateEnabledKey =
      'subscription_auto_update_enabled';

  static const subscriptionAutoUpdateIntervalKey =
      'subscription_auto_update_interval_hours';

  static const defaultSubscriptionAutoUpdateIntervalHours = 24;

  static const minSubscriptionAutoUpdateIntervalHours = 1;
  static const maxSubscriptionAutoUpdateIntervalHours = 168;

  static const subscriptionAutoUpdatePresetHours = [6, 12, 24, 48];

  static const subscriptionAutoUpdateScheduleKey =
      'subscription_auto_update_schedule';

  static const subscriptionAutoUpdateTimeKey =
      'subscription_auto_update_time_minutes';

  static const defaultSubscriptionAutoUpdateTimeMinutes = 4 * 60;

  static const subscriptionAutoUpdateSinceKey =
      'subscription_auto_update_schedule_since';

  bool get defaultWhitelistInitialized =>
      _bool(dnsContainer, 'default_whitelist_initialized', false);

  int get defaultWhitelistSeededVersion =>
      _int(dnsContainer, 'default_whitelist_seeded_version', 0);

  void markDefaultWhitelistSeeded(int versionCode) {
    _store.putBool(dnsContainer, 'default_whitelist_initialized', true);
    _store.putLong(
      dnsContainer,
      'default_whitelist_seeded_version',
      versionCode * 1000 + 2,
    );
  }

  List<String> get bottomBarIds {
    final raw = _string(uiContainer, 'bottom_bar_destinations');
    if (raw == null || raw.trim().isEmpty) {
      return List.of(defaultBottomBarIds);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return List.of(defaultBottomBarIds);
      }
      final ids = <String>[];
      for (final item in decoded) {
        if (item is String &&
            bottomBarIdValues.contains(item) &&
            !ids.contains(item)) {
          ids.add(item);
        }
      }
      if (ids.length < bottomBarMinCount) {
        return List.of(defaultBottomBarIds);
      }
      return ids.take(bottomBarMaxCount).toList();
    } on FormatException {
      return List.of(defaultBottomBarIds);
    }
  }

  void setBottomBarIds(List<String> ids) {
    final unique = <String>[];
    for (final id in ids) {
      if (!unique.contains(id)) {
        unique.add(id);
      }
    }
    final finalIds = unique.length < bottomBarMinCount
        ? defaultBottomBarIds
        : unique.take(bottomBarMaxCount).toList();
    _store.putString(
      uiContainer,
      'bottom_bar_destinations',
      jsonEncode(finalIds),
    );
  }

  String get workModeRaw =>
      _string(workModeContainer, 'app_work_mode') ?? 'normal';

  void setWorkModeRaw(String storageValue) =>
      _store.putString(workModeContainer, 'app_work_mode', storageValue);

  bool get workModeSelected =>
      _bool(workModeContainer, 'work_mode_initial_selected', false);

  bool get modeOnboardingCompleted =>
      _bool(workModeContainer, 'mode_onboarding_completed', false);

  void setModeOnboardingCompleted(bool value) =>
      _store.putBool(workModeContainer, 'mode_onboarding_completed', value);

  void setWorkModeSelected(bool value) =>
      _store.putBool(workModeContainer, 'work_mode_initial_selected', value);

  void clearWorkModeSelection() {
    _store.remove(workModeContainer, 'app_work_mode');
    _store.remove(workModeContainer, 'work_mode_initial_selected');
  }

  String get resolutionModeRaw =>
      _string(dnsContainer, 'dns_resolution_mode') ?? 'single';

  void setResolutionModeRaw(String storageValue) =>
      _store.putString(dnsContainer, 'dns_resolution_mode', storageValue);

  Object? rawValue(String key) => _store.read(dnsContainer, key);

  bool get bypassLanEnabled => _bool(uiContainer, 'bypass_lan_enabled', true);

  static const ipv6ModeKey = 'vpn_ipv6_mode';

  Ipv6Mode get ipv6Mode =>
      Ipv6Mode.fromStorage(_string(dnsContainer, ipv6ModeKey)) ?? Ipv6Mode.ipv4;

  List<String> get vpnRouteAddress => _routeAddress('vpn_route_address');

  List<String> get vpnRouteExcludeAddress =>
      _routeAddress('vpn_route_exclude_address');

  List<String> _routeAddress(String key) {
    final values = _stringSet(key, container: uiContainer) ?? const <String>{};
    return values.toList()..sort();
  }

  Set<String> get excludedPackages {
    final value = _store.read(uiContainer, 'excluded_app_packages');
    if (value is List) {
      return {
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      };
    }
    return const {};
  }

  void setExcludedPackages(Set<String> packages) =>
      _store.putStringSet(uiContainer, 'excluded_app_packages', {
        for (final item in packages)
          if (item.trim().isNotEmpty) item,
      });

  Map<String, Set<String>> get appAllowlistRules {
    final raw = _string(uiContainer, 'app_allowlist_rules_json');
    if (raw == null || raw.trim().isEmpty) return const {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map) return const {};
    final result = <String, Set<String>>{};
    decoded.forEach((key, value) {
      if (key is! String || key.trim().isEmpty) return;
      if (value is! List) return;
      final domains = {
        for (final item in value)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      };
      if (domains.isNotEmpty) result[key] = domains;
    });
    return result;
  }

  void setAppAllowlistRules(Map<String, Set<String>> rules) {
    final cleaned = <String, List<String>>{};
    rules.forEach((packageName, domains) {
      if (packageName.trim().isEmpty) return;
      final values = [
        for (final domain in domains)
          if (domain.trim().isNotEmpty) domain.trim(),
      ];
      if (values.isNotEmpty) cleaned[packageName] = values;
    });
    _store.putString(
      uiContainer,
      'app_allowlist_rules_json',
      jsonEncode(cleaned),
    );
  }

  bool get appAllowlistEnabled =>
      _bool(uiContainer, 'app_allowlist_enabled', false);

  void setAppAllowlistEnabled(bool value) =>
      _store.putBool(uiContainer, 'app_allowlist_enabled', value);

  Set<String> get blockedAppPackages =>
      _stringSet('blocked_app_packages', container: uiContainer) ?? const {};
  bool get blockedAppsEnabled =>
      _bool(uiContainer, 'blocked_apps_enabled', false);

  void setBlockedApps({required Set<String> packages, required bool enabled}) {
    _store.putStringSet(uiContainer, 'blocked_app_packages', {
      for (final item in packages)
        if (item.trim().isNotEmpty) item,
    });
    _store.putBool(uiContainer, 'blocked_apps_enabled', enabled);
  }

  Set<String> get httpInspectionPackages =>
      _stringSet('http_inspection_app_packages', container: uiContainer) ??
      const {};

  bool get httpInspectionEnabled =>
      _bool(uiContainer, 'http_inspection_enabled', false);

  bool get httpsInspectionReady =>
      _bool(uiContainer, 'https_inspection_ready', false) &&
      _string(uiContainer, 'https_inspection_ca_backend') == 'go-v1';

  void setHttpsInspectionReady(bool ready) {
    _store.putBool(uiContainer, 'https_inspection_ready', ready);
    _store.putString(
      uiContainer,
      'https_inspection_ca_backend',
      ready ? 'go-v1' : '',
    );
  }

  bool get httpsInspectionOperational =>
      httpsInspectionReady &&
      httpInspectionEnabled &&
      httpInspectionPackages.isNotEmpty;

  void setHttpInspectionApps({
    required Set<String> packages,
    required bool enabled,
  }) {
    _store.putStringSet(uiContainer, 'http_inspection_app_packages', {
      for (final item in packages)
        if (item.trim().isNotEmpty) item,
    });
    _store.putBool(uiContainer, 'http_inspection_enabled', enabled);
  }

  String? _string(String container, String key) {
    final value = _store.read(container, key);
    return value is String ? value : null;
  }

  bool _bool(String container, String key, bool fallback) {
    final value = _store.read(container, key);
    return value is bool ? value : fallback;
  }

  int _int(String container, String key, int fallback) {
    final value = _store.read(container, key);
    return value is int ? value : fallback;
  }

  List<String> _idList(
    String key, {
    List<String> fallback = const ['preset_alidns_dns', 'preset_dnspod_dns'],
  }) {
    final raw = _string(dnsContainer, key);
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return fallback;
      return [
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      ];
    } on FormatException {
      return fallback;
    }
  }

  double _double(String container, String key, double fallback) {
    final value = _store.read(container, key);
    return value is num ? value.toDouble() : fallback;
  }

  Set<String>? _stringSet(String key, {String? container}) {
    final value = _store.read(container ?? dnsContainer, key);
    if (value is List) {
      return {
        for (final item in value)
          if (item is String && item.isNotEmpty) item,
      };
    }
    if (value is! String) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return null;
      return {
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } on FormatException {
      return null;
    }
  }

  static String _encodeSet(Set<String> values) =>
      jsonEncode(values.toList()..sort());

  static double _clampedOpacity(double value) => value.clamp(0.1, 1.0);
}
