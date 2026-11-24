part of 'legacy_settings.dart';

extension LegacySettingsParity on LegacySettings {
  String get _ui => LegacySettings.uiContainer;

  String get _notification => LegacySettings.notificationContainer;

  String get dnsLogModeRaw => _string(dnsContainer, 'dns_log_mode') ?? 'all';

  void setDnsLogModeRaw(String storageValue) =>
      _store.putString(dnsContainer, 'dns_log_mode', storageValue);

  int get logRetentionDays => _int(dnsContainer, 'log_retention_days', 7);

  void setLogRetentionDays(int days) =>
      _store.putInt(dnsContainer, 'log_retention_days', days.clamp(1, 30));

  bool get floatingLogEnabled => _bool(_ui, 'floating_log_enabled', false);

  void setFloatingLogEnabled(bool value) =>
      _store.putBool(_ui, 'floating_log_enabled', value);

  int get floatingLogPanelSize =>
      _int(_ui, 'floating_log_panel_size', 1).clamp(0, 2);

  void setFloatingLogPanelSize(int value) =>
      _store.putInt(_ui, 'floating_log_panel_size', value.clamp(0, 2));

  double get floatingLogOpacity =>
      _double(_ui, 'floating_log_opacity', 1).clamp(0.3, 1).toDouble();

  void setFloatingLogOpacity(double value) =>
      _store.putFloat(_ui, 'floating_log_opacity', value.clamp(0.3, 1));

  bool get hideFromRecentsEnabled =>
      _bool(_ui, 'hide_from_recents_enabled', false);

  void setHideFromRecentsEnabled(bool value) =>
      _store.putBool(_ui, 'hide_from_recents_enabled', value);

  bool get vpnWatchdogEnabled => _bool(_ui, 'vpn_watchdog_enabled', true);

  void setVpnWatchdogEnabled(bool value) =>
      _store.putBool(_ui, 'vpn_watchdog_enabled', value);

  bool get autoStartOnLaunchEnabled =>
      _bool(_ui, 'auto_start_on_launch_enabled', false);

  void setAutoStartOnLaunchEnabled(bool value) =>
      _store.putBool(_ui, 'auto_start_on_launch_enabled', value);

  bool get autoStartOnBootEnabled =>
      _bool(_ui, 'auto_start_on_boot_enabled', false);

  void setAutoStartOnBootEnabled(bool value) =>
      _store.putBool(_ui, 'auto_start_on_boot_enabled', value);

  void setBypassLanEnabled(bool value) =>
      _store.putBool(_ui, 'bypass_lan_enabled', value);

  void setTunnelIpv6Enabled(bool value) =>
      _store.putBool(dnsContainer, 'vpn_ipv6_enabled', value);

  void setDnsAaaaEnabled(bool value) =>
      _store.putBool(dnsContainer, 'dns_aaaa_enabled', value);

  void setVpnRouteAddress(Iterable<String> values) =>
      _store.putStringSet(_ui, 'vpn_route_address', _routeSet(values));

  void setVpnRouteExcludeAddress(Iterable<String> values) =>
      _store.putStringSet(_ui, 'vpn_route_exclude_address', _routeSet(values));

  Set<String> _routeSet(Iterable<String> values) => {
    for (final item in values)
      if (item.trim().isNotEmpty) item.trim(),
  };

  String get appLanguageModeRaw =>
      _string(_ui, 'app_language_mode') ?? 'system';

  void setAppLanguageModeRaw(String storageValue) =>
      _store.putString(_ui, 'app_language_mode', storageValue);

  bool get initialAgreementAccepted =>
      _bool(_ui, 'initial_agreement_accepted', false);

  void setInitialAgreementAccepted(bool value) =>
      _store.putBool(_ui, 'initial_agreement_accepted', value);

  bool get disableStartupUpdateCheck =>
      _bool(_ui, 'disable_startup_update_check', true);

  void setDisableStartupUpdateCheck(bool value) =>
      _store.putBool(_ui, 'disable_startup_update_check', value);

  bool get customBackgroundEnabled =>
      _bool(_ui, 'custom_background_enabled', false);

  void setCustomBackgroundEnabled(bool value) =>
      _store.putBool(_ui, 'custom_background_enabled', value);

  String? get customBackgroundUri => _string(_ui, 'custom_background_uri');

  void setCustomBackgroundUri(String uri) =>
      _store.putString(_ui, 'custom_background_uri', uri);

  List<String> get customBackgroundUris {
    final raw = _string(_ui, 'custom_background_uris');
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    } on FormatException {
      return const [];
    }
  }

  void setCustomBackgroundUris(List<String> uris) => _store.putString(
    _ui,
    'custom_background_uris',
    jsonEncode([
      for (final uri in uris)
        if (uri.trim().isNotEmpty) uri,
    ]),
  );

  bool get notificationPersistent => _bool(_notification, 'persistent', true);

  void setNotificationPersistent(bool value) =>
      _store.putBool(_notification, 'persistent', value);

  bool get notificationSpeed => _bool(_notification, 'speed', false);

  void setNotificationSpeed(bool value) {
    _store.putBool(_notification, 'speed', value);
    if (_string(_notification, 'stats_items') == null) return;
    final items = [...notificationStatsItems]..remove('speed');
    if (value) items.add('speed');
    _store.putString(_notification, 'stats_items', items.join(','));
  }

  List<String> get notificationStatsItems {
    final raw = _string(_notification, 'stats_items');
    if (raw == null) return notificationSpeed ? const ['speed'] : const [];
    return [
      for (final id in raw.split(',').map((id) => id.trim()).toSet())
        if (id.isNotEmpty) id,
    ];
  }

  void setNotificationStatsItems(List<String> ids) {
    _store.putString(_notification, 'stats_items', ids.toSet().join(','));
    _store.putBool(_notification, 'speed', ids.contains('speed'));
  }

  void setNotificationStatsLabelsJson(String value) =>
      _store.putString(_notification, 'stats_labels', value);

  ({String running, String stopped}) get notificationTexts => (
    running: _string(_notification, 'custom_running_text') ?? '',
    stopped: _string(_notification, 'custom_stopped_text') ?? '',
  );

  void setNotificationTexts({
    required String running,
    required String stopped,
  }) {
    _store.putString(_notification, 'custom_running_text', running);
    _store.putString(_notification, 'custom_stopped_text', stopped);
  }

  void setNotificationDefaultRunningText(String value) =>
      _store.putString(_notification, 'default_running_text', value);

  void setNotificationDefaultExpressText(String value) =>
      _store.putString(_notification, 'default_express_text', value);

  bool get subscriptionAutoUpdateEnabled => _bool(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateEnabledKey,
    false,
  );

  int get subscriptionAutoUpdateIntervalHours {
    final value = _int(
      dnsContainer,
      LegacySettings.subscriptionAutoUpdateIntervalKey,
      LegacySettings.defaultSubscriptionAutoUpdateIntervalHours,
    );
    return value >= LegacySettings.minSubscriptionAutoUpdateIntervalHours &&
            value <= LegacySettings.maxSubscriptionAutoUpdateIntervalHours
        ? value
        : LegacySettings.defaultSubscriptionAutoUpdateIntervalHours;
  }

  void setSubscriptionAutoUpdateEnabled(bool value) => _store.putBool(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateEnabledKey,
    value,
  );

  void setSubscriptionAutoUpdateIntervalHours(int hours) => _store.putInt(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateIntervalKey,
    hours.clamp(
      LegacySettings.minSubscriptionAutoUpdateIntervalHours,
      LegacySettings.maxSubscriptionAutoUpdateIntervalHours,
    ),
  );

  String get subscriptionAutoUpdateScheduleRaw {
    final value = _string(
      dnsContainer,
      LegacySettings.subscriptionAutoUpdateScheduleKey,
    );
    return const {'interval', 'daily', 'every_other_day'}.contains(value)
        ? value!
        : 'interval';
  }

  void setSubscriptionAutoUpdateScheduleRaw(String value) => _store.putString(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateScheduleKey,
    value,
  );

  int get subscriptionAutoUpdateTimeMinutes {
    final value = _int(
      dnsContainer,
      LegacySettings.subscriptionAutoUpdateTimeKey,
      LegacySettings.defaultSubscriptionAutoUpdateTimeMinutes,
    );
    return value >= 0 && value < 24 * 60
        ? value
        : LegacySettings.defaultSubscriptionAutoUpdateTimeMinutes;
  }

  void setSubscriptionAutoUpdateTimeMinutes(int minutes) => _store.putInt(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateTimeKey,
    minutes.clamp(0, 24 * 60 - 1),
  );

  int get subscriptionAutoUpdateSinceMs =>
      _int(dnsContainer, LegacySettings.subscriptionAutoUpdateSinceKey, 0);

  void setSubscriptionAutoUpdateSinceMs(int epochMs) => _store.putLong(
    dnsContainer,
    LegacySettings.subscriptionAutoUpdateSinceKey,
    epochMs,
  );

  bool get agentApiEnabled => _bool(_ui, 'agent_api_enabled', true);

  void setAgentApiEnabled(bool value) =>
      _store.putBool(_ui, 'agent_api_enabled', value);

  void setAgentApiKey(String value) =>
      _store.putString(_ui, 'agent_api_key', value.trim());

  void setAgentApiBaseUrl(String value) =>
      _store.putString(_ui, 'agent_api_base_url', value.trim());

  void setAgentApiModel(String value) =>
      _store.putString(_ui, 'agent_api_model', value.trim());

  double get agentApiTemperature {
    final raw = _store.read(_ui, 'agent_api_temperature');
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final parsed = double.tryParse(raw.trim());
      if (parsed != null) return parsed;
    }
    return 0.7;
  }

  void setAgentApiTemperature(double value) =>
      _store.putString(_ui, 'agent_api_temperature', value.toStringAsFixed(1));

  String get agentApiSystemPrompt =>
      _string(_ui, 'agent_api_system_prompt') ?? '';

  void setAgentApiSystemPrompt(String value) =>
      _store.putString(_ui, 'agent_api_system_prompt', value);

  String? get agentAiProvidersJson => _string(_ui, 'agent_ai_providers_json');

  void setAgentAiProvidersJson(String value) =>
      _store.putString(_ui, 'agent_ai_providers_json', value);

  String get agentAiActiveProviderId =>
      _string(_ui, 'agent_ai_active_provider_id') ?? '';

  void setAgentAiActiveProviderId(String value) =>
      _store.putString(_ui, 'agent_ai_active_provider_id', value);
}
