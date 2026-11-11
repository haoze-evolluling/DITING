part of 'legacy_settings.dart';

// Server-mode (DNS-only LAN) settings, all in the `diting_dns_mode_prefs` container.

extension LegacyServerSettings on LegacySettings {
  int get serverPort => LegacySettings._clampedPort(
    _int(
      LegacySettings.serverContainer,
      'local_listen_port',
      LegacySettings.defaultServerPort,
    ),
  );

  void setServerPort(int port) => _store.putInt(
    LegacySettings.serverContainer,
    'local_listen_port',
    LegacySettings._clampedPort(port),
  );

  String get serverSelectedUpstreamId =>
      _stringIn(LegacySettings.serverContainer, 'selected_upstream_id') ??
      'preset_alidns_dns';

  void setServerSelectedUpstreamId(String id) => _store.putString(
    LegacySettings.serverContainer,
    'selected_upstream_id',
    id,
  );

  String? get serverCustomUpstreamsJson =>
      _stringIn(LegacySettings.serverContainer, 'custom_upstreams');

  /// Stored as `[]` rather than removed, which keeps the fact that custom upstreams once existed.
  void setServerCustomUpstreamsJson(String json) => _store.putString(
    LegacySettings.serverContainer,
    'custom_upstreams',
    json,
  );

  bool get serverCacheEnabled =>
      _boolIn(LegacySettings.serverContainer, 'cache_enabled', true);

  void setServerCacheEnabled(bool value) =>
      _store.putBool(LegacySettings.serverContainer, 'cache_enabled', value);

  String get serverCachePresetRaw =>
      _stringIn(LegacySettings.serverContainer, 'cache_preset') ?? 'balanced';

  bool get serverAdBlockEnabled =>
      _boolIn(LegacySettings.serverContainer, 'ad_block_enabled', false);

  void setServerAdBlockEnabled(bool value) =>
      _store.putBool(LegacySettings.serverContainer, 'ad_block_enabled', value);

  bool get serverLogQueries =>
      _boolIn(LegacySettings.serverContainer, 'log_queries', false);

  bool get serverServiceActive =>
      _boolIn(LegacySettings.serverContainer, 'service_active', false);

  void setServerServiceActive(bool value) =>
      _store.putBool(LegacySettings.serverContainer, 'service_active', value);

  String get serverBlockResponseModeRaw =>
      _stringIn(LegacySettings.serverContainer, 'block_response_mode') ??
      'nxdomain';

  bool get serverDynamicBlockEnabled => _boolIn(
    LegacySettings.serverContainer,
    'block_response_dynamic_enabled',
    false,
  );

  int get serverDynamicBlockThreshold => _intIn(
    LegacySettings.serverContainer,
    'block_response_dynamic_threshold',
    5,
  );

  int get serverDynamicBlockWindowSeconds => _intIn(
    LegacySettings.serverContainer,
    'block_response_dynamic_window_seconds',
    60,
  );

  int get serverDynamicBlockNxDomainDurationSeconds => _intIn(
    LegacySettings.serverContainer,
    'block_response_dynamic_nxdomain_duration_seconds',
    300,
  );

  void setServerLogQueries(bool value) =>
      _store.putBool(LegacySettings.serverContainer, 'log_queries', value);
}
