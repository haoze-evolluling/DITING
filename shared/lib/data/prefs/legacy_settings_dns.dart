part of 'legacy_settings.dart';

/// DNS-domain settings: providers, cache policy, block response, bootstrap and the inspection
/// switches.
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

  /// As recorded by the Go resolver: EWMA milliseconds, absent without history.
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

  /// Written verbatim; the legacy contract expects `id`/`name`/`protocol`/`url`/`host`/`port`.
  void setUserProvidersJson(String json) =>
      _store.putString(dnsContainer, 'user_providers_json', json);

  List<String> get smartPredictionProviderIds =>
      _idList('smart_prediction_provider_ids');

  List<String> get parallelRaceProviderIds =>
      _idList('parallel_race_provider_ids');

  List<String> get primaryBackupProviderIds =>
      _idList('primary_backup_provider_ids');

  /// A separate historical key from `parallel_race_provider_ids`; backups must keep the name.
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

  /// Only `DNS` / `DoT` / `DoH`; a restore without it falls back to `DNS` and loses the race
  /// protocol.
  String get presetDnsServiceRaw =>
      _string(dnsContainer, 'preset_dns_service') ?? 'DNS';

  void setPresetDnsServiceRaw(String value) =>
      _store.putString(dnsContainer, 'preset_dns_service', value);

  /// Home race probe domain; backups must carry the effective value, not an empty string.
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

  /// Single mode has no candidate list: the selection lives in `selected_provider_id`.
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

  /// Stored as sorted JSON arrays, like the legacy `writeStringSet`.
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

  String get cacheModeRaw =>
      _string(dnsContainer, 'dns_cache_mode_v2') ?? 'limit_max_ttl';

  int get cacheMaxTtlSeconds =>
      _int(dnsContainer, 'dns_cache_max_ttl_seconds_v2', 3600);

  int get cacheFixedTtlSeconds =>
      _int(dnsContainer, 'dns_cache_fixed_ttl_seconds_v2', 3600);

  bool get cacheMinTtlEnabled =>
      _bool(dnsContainer, 'dns_cache_min_ttl_enabled_v2', false);

  int get cacheMinTtlSeconds =>
      _int(dnsContainer, 'dns_cache_min_ttl_seconds_v2', 60);

  bool get cacheStaleFallbackEnabled =>
      _bool(dnsContainer, 'dns_cache_stale_fallback_enabled_v2', false);

  int get cacheStaleFallbackSeconds =>
      _int(dnsContainer, 'dns_cache_stale_fallback_seconds_v2', 300);

  /// Absent on installs predating presets, where the UI derives the preset from the stored policy.
  String? get cachePresetRaw => _string(dnsContainer, 'dns_cache_preset_v3');

  /// Writes all nine keys so the engine reads a consistent policy.
  void applyCachePreset({
    required String storageValue,
    required bool enabled,
    required String mode,
    required int maxTtlSeconds,
    required int fixedTtlSeconds,
    required bool minTtlEnabled,
    required int minTtlSeconds,
    required bool staleFallbackEnabled,
    required int staleFallbackSeconds,
  }) {
    int clamp(int seconds) => LegacySettings._clampSeconds(seconds);
    _store.putString(dnsContainer, 'dns_cache_preset_v3', storageValue);
    _store.putBool(dnsContainer, 'dns_cache_enabled_v2', enabled);
    _store.putString(dnsContainer, 'dns_cache_mode_v2', mode);
    _store.putLong(
      dnsContainer,
      'dns_cache_max_ttl_seconds_v2',
      clamp(maxTtlSeconds),
    );
    _store.putLong(
      dnsContainer,
      'dns_cache_fixed_ttl_seconds_v2',
      clamp(fixedTtlSeconds),
    );
    _store.putBool(dnsContainer, 'dns_cache_min_ttl_enabled_v2', minTtlEnabled);
    _store.putLong(
      dnsContainer,
      'dns_cache_min_ttl_seconds_v2',
      clamp(minTtlSeconds),
    );
    _store.putBool(
      dnsContainer,
      'dns_cache_stale_fallback_enabled_v2',
      staleFallbackEnabled,
    );
    _store.putLong(
      dnsContainer,
      'dns_cache_stale_fallback_seconds_v2',
      clamp(staleFallbackSeconds),
    );
  }

  void setCacheEnabled(bool value) =>
      _store.putBool(dnsContainer, 'dns_cache_enabled_v2', value);

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

  /// Clamps to 2-100 / 10-300 / 60-3600; out-of-range input must never reach the engine.
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

  /// The caller filters ids against the built-in catalog before writing.
  void setBootstrapPresetIds(Set<String> ids) => _store.putString(
    dnsContainer,
    'bootstrap_preset_ids',
    LegacySettings._encodeSet(ids),
  );

  void setBootstrapCustomJson(String json) =>
      _store.putString(dnsContainer, 'bootstrap_custom_json', json);

  /// Global rather than dataset-scoped; only the CA flow turns `http_inspection_enabled` on.
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

  /// Written by the native CA flow; pages only read it.
  bool get httpsInspectionReady =>
      _bool(LegacySettings.uiContainer, 'https_inspection_ready', false);

  /// View over the express data set's container. Production code selects the active data set via
  /// `activeDataSetProvider`; this stays for data-set-scoped reads and tests.
  LegacySettings forExpress() =>
      LegacySettings(_store, dnsContainer: LegacySettings.expressContainer);
}
