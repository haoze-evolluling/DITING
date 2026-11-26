part of 'legacy_settings.dart';

extension LegacyDnsSettings on LegacySettings {
  bool get vpnRunning =>
      _bool(LegacySettings.uiContainer, 'vpn_running', false);

  void setVpnRunning(bool value) =>
      _store.putBool(LegacySettings.uiContainer, 'vpn_running', value);

  bool get expressVpnRunning => _bool(
    LegacySettings.expressRunningContainer,
    'express_vpn_running',
    false,
  );

  void setExpressVpnRunning(bool value) => _store.putBool(
    LegacySettings.expressRunningContainer,
    'express_vpn_running',
    value,
  );

  String get selectedProviderId =>
      _string(dnsContainer, 'selected_provider_id') ?? 'preset_alidns_dns';

  void setSelectedProviderId(String id) =>
      _store.putString(dnsContainer, 'selected_provider_id', id);

  String? get userProvidersJson => _string(dnsContainer, 'user_providers_json');

  Map<String, int> get providerLatenciesMs {
    final raw = _string(dnsContainer, 'provider_health_json');
    if (raw == null || raw.isEmpty) return const {};
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const {};
    }
    if (decoded is! Map) return const {};
    final result = <String, int>{};
    decoded.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final ewma = value['ewmaMs'];
      if (ewma is num && ewma > 0) {
        result[key] = ewma.round();
      }
    });
    return result;
  }

  void setUserProvidersJson(String json) =>
      _store.putString(dnsContainer, 'user_providers_json', json);

  List<String> get smartPredictionProviderIds =>
      _idList('smart_prediction_provider_ids');

  List<String> get parallelRaceProviderIds =>
      _idList('parallel_race_provider_ids');

  List<String> get primaryBackupProviderIds =>
      _idList('primary_backup_provider_ids');

  List<String> get raceProviderIds => _idList('race_provider_ids');

  void setRaceProviderIds(List<String> ids) =>
      _store.putString(dnsContainer, 'race_provider_ids', jsonEncode(ids));

  List<String> get latencyTestProviderIds =>
      _idList('latency_test_provider_ids');

  void setLatencyTestProviderIds(List<String> ids) => _store.putString(
    dnsContainer,
    'latency_test_provider_ids',
    jsonEncode(ids),
  );

  String get presetDnsServiceRaw =>
      _string(dnsContainer, 'preset_dns_service') ?? 'DNS';

  void setPresetDnsServiceRaw(String value) =>
      _store.putString(dnsContainer, 'preset_dns_service', value);

  String get raceTestDomain =>
      _string(dnsContainer, 'race_test_domain') ?? 'mihoyo.com';

  void setRaceTestDomain(String domain) =>
      _store.putString(dnsContainer, 'race_test_domain', domain);

  void setSmartPredictionProviderIds(List<String> ids) => _store.putString(
    dnsContainer,
    'smart_prediction_provider_ids',
    jsonEncode(ids),
  );

  void setParallelRaceProviderIds(List<String> ids) => _store.putString(
    dnsContainer,
    'parallel_race_provider_ids',
    jsonEncode(ids),
  );

  void setPrimaryBackupProviderIds(List<String> ids) => _store.putString(
    dnsContainer,
    'primary_backup_provider_ids',
    jsonEncode(ids),
  );

  List<String> providerIdsOf(String resolutionMode) => switch (resolutionMode) {
    'smart_prediction' => smartPredictionProviderIds,
    'parallel_race' => parallelRaceProviderIds,
    'primary_backup' => primaryBackupProviderIds,
    _ => const [],
  };

  void setProviderIdsOf(String resolutionMode, List<String> ids) {
    switch (resolutionMode) {
      case 'smart_prediction':
        setSmartPredictionProviderIds(ids);
      case 'parallel_race':
        setParallelRaceProviderIds(ids);
      case 'primary_backup':
        setPrimaryBackupProviderIds(ids);
      default:
        break;
    }
  }

  List<String> get providerDisplayOrderIds =>
      _idList('provider_display_order_ids', fallback: const []);

  void setProviderDisplayOrderIds(List<String> ids) => _store.putString(
    dnsContainer,
    'provider_display_order_ids',
    jsonEncode(ids),
  );

  Set<String> get homeVisibleProtocols =>
      _stringSet('home_visible_protocols') ?? const {'DNS', 'DOH', 'DOT'};

  Set<String> get homeHiddenProviderIds =>
      _stringSet('home_hidden_provider_ids') ?? const {};

  Set<String> get homeVisibleProviderIds =>
      _stringSet('home_visible_provider_ids') ?? const {};

  void setHomeProviderVisibility({
    required Set<String> visibleProtocols,
    required Set<String> hiddenProviderIds,
    required Set<String> visibleProviderIds,
  }) {
    _store.putString(
      dnsContainer,
      'home_visible_protocols',
      LegacySettings._encodeSet(visibleProtocols),
    );
    _store.putString(
      dnsContainer,
      'home_hidden_provider_ids',
      LegacySettings._encodeSet(hiddenProviderIds),
    );
    _store.putString(
      dnsContainer,
      'home_visible_provider_ids',
      LegacySettings._encodeSet(visibleProviderIds),
    );
  }

  bool get cacheEnabled => _bool(dnsContainer, 'dns_cache_enabled_v2', true);

  String? get cachePresetV4 => _string(dnsContainer, 'dns_cache_preset_v4');

  int? get cacheScalePercentV4 {
    final value = _store.read(dnsContainer, 'dns_cache_scale_percent_v4');
    return value is int ? value : null;
  }

  void writeCachePolicy({
    required bool enabled,
    required String preset,
    required int scalePercent,
  }) {
    _store.putBool(dnsContainer, 'dns_cache_enabled_v2', enabled);
    _store.putString(dnsContainer, 'dns_cache_preset_v4', preset);
    _store.putLong(
      dnsContainer,
      'dns_cache_scale_percent_v4',
      scalePercent.clamp(10, 500),
    );
  }

  String get blockResponseModeRaw =>
      _string(dnsContainer, 'block_response_mode') ?? 'nxdomain';

  void setBlockResponseModeRaw(String value) =>
      _store.putString(dnsContainer, 'block_response_mode', value);

  bool get dynamicBlockEnabled =>
      _bool(dnsContainer, 'dynamic_block_response_enabled', false);

  int get dynamicBlockRequestThreshold =>
      _int(dnsContainer, 'dynamic_block_request_threshold', 5);

  int get dynamicBlockWindowSeconds =>
      _int(dnsContainer, 'dynamic_block_window_seconds', 60);

  int get dynamicBlockNxDomainDurationSeconds =>
      _int(dnsContainer, 'dynamic_block_nxdomain_duration_seconds', 300);

  void setDynamicBlockPolicy({
    required bool enabled,
    required int requestThreshold,
    required int windowSeconds,
    required int nxDurationSeconds,
  }) {
    _store.putBool(dnsContainer, 'dynamic_block_response_enabled', enabled);
    _store.putInt(
      dnsContainer,
      'dynamic_block_request_threshold',
      requestThreshold.clamp(2, 100),
    );
    _store.putInt(
      dnsContainer,
      'dynamic_block_window_seconds',
      windowSeconds.clamp(10, 300),
    );
    _store.putInt(
      dnsContainer,
      'dynamic_block_nxdomain_duration_seconds',
      nxDurationSeconds.clamp(60, 3600),
    );
  }

  bool get domainRulesEnabled =>
      _bool(dnsContainer, 'domain_rules_enabled', true);

  void setDomainRulesEnabled(bool value) =>
      _store.putBool(dnsContainer, 'domain_rules_enabled', value);

  bool get bootstrapEnabled => _bool(dnsContainer, 'bootstrap_enabled', true);

  List<String> get bootstrapPresetIds => _idList(
    'bootstrap_preset_ids',
    fallback: const ['preset_volcengine', 'preset_dnspod', 'preset_alidns'],
  );

  String? get bootstrapCustomJson =>
      _string(dnsContainer, 'bootstrap_custom_json');

  void setBootstrapEnabled(bool value) =>
      _store.putBool(dnsContainer, 'bootstrap_enabled', value);

  void setBootstrapPresetIds(Set<String> ids) => _store.putString(
    dnsContainer,
    'bootstrap_preset_ids',
    LegacySettings._encodeSet(ids),
  );

  void setBootstrapCustomJson(String json) =>
      _store.putString(dnsContainer, 'bootstrap_custom_json', json);

  bool get http3InspectionEnabled =>
      _bool(LegacySettings.uiContainer, 'http3_inspection_enabled', false);

  bool get encryptedDnsBlockingEnabled => _bool(
    LegacySettings.uiContainer,
    'encrypted_dns_blocking_enabled',
    false,
  );

  bool get addressRulesEnabled =>
      _bool(LegacySettings.uiContainer, 'address_rules_enabled', true);

  void setHttpInspectionToggles({
    required bool http3,
    required bool encryptedDns,
    required bool addressRules,
  }) {
    _store.putBool(
      LegacySettings.uiContainer,
      'http3_inspection_enabled',
      http3,
    );
    _store.putBool(
      LegacySettings.uiContainer,
      'encrypted_dns_blocking_enabled',
      encryptedDns,
    );
    _store.putBool(
      LegacySettings.uiContainer,
      'address_rules_enabled',
      addressRules,
    );
  }

  bool get blockHttpsSvcbRecordTypes =>
      _bool(LegacySettings.uiContainer, 'block_https_svcb_record_types', false);

  void setBlockHttpsSvcbRecordTypes(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'block_https_svcb_record_types',
    value,
  );

  bool get dnsRebindingProtection =>
      _bool(LegacySettings.uiContainer, 'dns_rebinding_protection', false);

  void setDnsRebindingProtection(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'dns_rebinding_protection',
    value,
  );

  bool get dns64Enabled =>
      _bool(LegacySettings.uiContainer, 'dns64_enabled', false);

  void setDns64Enabled(bool value) =>
      _store.putBool(LegacySettings.uiContainer, 'dns64_enabled', value);

  bool get connectionRateLimitEnabled =>
      _bool(LegacySettings.uiContainer, 'connection_rate_limit_enabled', false);

  void setConnectionRateLimitEnabled(bool value) => _store.putBool(
    LegacySettings.uiContainer,
    'connection_rate_limit_enabled',
    value,
  );

  int get connectionRateLimitRate =>
      _int(LegacySettings.uiContainer, 'connection_rate_limit_rate', 50);

  void setConnectionRateLimitRate(int value) => _store.putInt(
    LegacySettings.uiContainer,
    'connection_rate_limit_rate',
    value,
  );

  int get connectionRateLimitBurst =>
      _int(LegacySettings.uiContainer, 'connection_rate_limit_burst', 100);

  void setConnectionRateLimitBurst(int value) => _store.putInt(
    LegacySettings.uiContainer,
    'connection_rate_limit_burst',
    value,
  );

  LegacySettings forExpress() =>
      LegacySettings(_store, dnsContainer: LegacySettings.expressContainer);
}
