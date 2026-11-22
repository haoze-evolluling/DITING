part of 'legacy_settings.dart';

extension LegacyHubSettings on LegacySettings {
  String get excludedAppsFilterRaw =>
      _string(LegacySettings.uiContainer, 'excluded_apps_filter') ?? 'USER';

  void setExcludedAppsFilterRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'excluded_apps_filter',
    value,
  );

  String get excludedAppsSortRaw =>
      _string(LegacySettings.uiContainer, 'excluded_apps_sort') ?? 'LABEL_ASC';

  void setExcludedAppsSortRaw(String value) =>
      _store.putString(LegacySettings.uiContainer, 'excluded_apps_sort', value);

  String get appAllowlistFilterRaw =>
      _string(LegacySettings.uiContainer, 'app_allowlist_filter') ?? 'USER';

  void setAppAllowlistFilterRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'app_allowlist_filter',
    value,
  );

  String get appAllowlistSortRaw =>
      _string(LegacySettings.uiContainer, 'app_allowlist_sort') ?? 'LABEL_ASC';

  void setAppAllowlistSortRaw(String value) =>
      _store.putString(LegacySettings.uiContainer, 'app_allowlist_sort', value);

  String get blockedAppsFilterRaw =>
      _string(LegacySettings.uiContainer, 'blocked_apps_filter') ??
      excludedAppsFilterRaw;

  void setBlockedAppsFilterRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'blocked_apps_filter',
    value,
  );

  String get blockedAppsSortRaw =>
      _string(LegacySettings.uiContainer, 'blocked_apps_sort') ?? 'LABEL_ASC';

  void setBlockedAppsSortRaw(String value) =>
      _store.putString(LegacySettings.uiContainer, 'blocked_apps_sort', value);

  String get httpInspectionAppsFilterRaw =>
      _string(LegacySettings.uiContainer, 'http_inspection_apps_filter') ??
      excludedAppsFilterRaw;

  void setHttpInspectionAppsFilterRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'http_inspection_apps_filter',
    value,
  );

  String get httpInspectionAppsSortRaw =>
      _string(LegacySettings.uiContainer, 'http_inspection_apps_sort') ??
      'LABEL_ASC';

  void setHttpInspectionAppsSortRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'http_inspection_apps_sort',
    value,
  );

  bool get globalMirrorEnabled =>
      _bool(LegacySettings.uiContainer, 'global_mirror_enabled', false);

  void setGlobalMirrorEnabled(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'global_mirror_enabled',
    value,
  );

  String? get globalMirrorTemplate {
    final value = _string(LegacySettings.uiContainer, 'global_mirror_template');
    return value == null || value.trim().isEmpty ? null : value;
  }

  void setGlobalMirrorTemplate(String template) => _store.putString(
    LegacySettings.uiContainer,
    'global_mirror_template',
    template,
  );

  Set<String> get httpsBypassRules =>
      _stringSet('https_bypass_rules', container: LegacySettings.uiContainer) ??
      const {};

  void setHttpsBypassRules(Set<String> rules) =>
      _store.putStringSet(LegacySettings.uiContainer, 'https_bypass_rules', {
        for (final rule in rules)
          if (rule.trim().isNotEmpty) rule.trim(),
      });

  bool get rootDnsTakeoverEnabled =>
      _bool(LegacySettings.uiContainer, 'root_dns_takeover_enabled', false);

  void setRootDnsTakeoverEnabled(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'root_dns_takeover_enabled',
    value,
  );

  bool get rootDnsRunning =>
      _bool(LegacySettings.uiContainer, 'root_dns_running', false);

  void setRootDnsRunning(bool value) =>
      _store.putBool(LegacySettings.uiContainer, 'root_dns_running', value);
}
