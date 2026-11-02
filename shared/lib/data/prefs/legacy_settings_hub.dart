part of 'legacy_settings.dart';

/// Keys owned by the app-list / CA screens. Every name is a verbatim legacy key; renaming one
/// silently resets that setting on upgrade, and all five live in the global `dns_vpn_prefs`.
extension LegacyHubSettings on LegacySettings {
  /// `ALL` / `SYSTEM` / `USER` / `SELECTED`, returned raw, so consumers fall back to `USER`.
  String get excludedAppsFilterRaw =>
      _string(LegacySettings.uiContainer, 'excluded_apps_filter') ?? 'USER';

  void setExcludedAppsFilterRaw(String value) => _store.putString(
    LegacySettings.uiContainer,
    'excluded_apps_filter',
    value,
  );

  /// `LABEL_ASC` / `LABEL_DESC` / `PACKAGE_ASC` / `PACKAGE_DESC`.
  String get excludedAppsSortRaw =>
      _string(LegacySettings.uiContainer, 'excluded_apps_sort') ?? 'LABEL_ASC';

  void setExcludedAppsSortRaw(String value) =>
      _store.putString(LegacySettings.uiContainer, 'excluded_apps_sort', value);

  /// Same values as [excludedAppsFilterRaw], own key, defaulting to `USER`.
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

  /// Blocked-apps picker; 1.4.3 defaults the filter to whatever the excluded list uses.
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

  /// HTTPS-inspection picker; same default fallback as the blocked list.
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

  /// Global mirror: when on, remote subscriptions without their own template and app updates
  /// download through [globalMirrorTemplate]. New keys, absent in 1.4.3.
  bool get globalMirrorEnabled =>
      _bool(LegacySettings.uiContainer, 'global_mirror_enabled', false);

  void setGlobalMirrorEnabled(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'global_mirror_enabled',
    value,
  );

  /// The template string itself, not a row id: templates live in the per-mode rule database,
  /// while this setting is global.
  String? get globalMirrorTemplate {
    final value = _string(LegacySettings.uiContainer, 'global_mirror_template');
    return value == null || value.trim().isEmpty ? null : value;
  }

  void setGlobalMirrorTemplate(String template) => _store.putString(
    LegacySettings.uiContainer,
    'global_mirror_template',
    template,
  );

  /// The custom half of the MITM bypass list; presets from `assets/https_passthrough.txt` are
  /// unioned in, never stored here.
  Set<String> get httpsBypassRules =>
      _stringSet('https_bypass_rules', container: LegacySettings.uiContainer) ??
      const {};

  void setHttpsBypassRules(Set<String> rules) =>
      _store.putStringSet(LegacySettings.uiContainer, 'https_bypass_rules', {
        for (final rule in rules)
          if (rule.trim().isNotEmpty) rule.trim(),
      });
}
