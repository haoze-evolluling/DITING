part of 'rust_dns_config_core.dart';

extension DocumentBuilders on RustDnsConfigCore {
  TunnelDocument buildTunnel({
    required String modeRaw,
    required String selectedProviderId,
    required List<String> smartPredictionProviderIds,
    required List<String> parallelRaceProviderIds,
    required List<String> primaryBackupProviderIds,
    required String? userProvidersJson,
    required bool bootstrapEnabled,
    required List<String> bootstrapPresetIds,
    required String? bootstrapCustomJson,
    required String blockResponseModeRaw,
    required bool cacheEnabled,
    required String cacheModeRaw,
    required int cacheMaxTtlSeconds,
    required int cacheFixedTtlSeconds,
    required bool cacheMinTtlEnabled,
    required int cacheMinTtlSeconds,
    required bool cacheStaleFallbackEnabled,
    required int cacheStaleFallbackSeconds,
    required bool dynamicBlockEnabled,
    required int dynamicBlockRequestThreshold,
    required int dynamicBlockWindowSeconds,
    required int dynamicBlockNxDomainDurationSeconds,
    required List<ProviderRow> presetProviders,
    required List<BootstrapEntryRow> presetBootstrap,
    bool blockHttpsSvcb = false,
    bool rebindingProtection = false,
    bool dns64Enabled = false,
    required bool connectionRateLimitEnabled,
    required int connectionRateLimitRate,
    required int connectionRateLimitBurst,
  }) {
    final writer = _PayloadWriter()
      ..u8(
        (bootstrapEnabled ? 0x1 : 0) |
            (cacheEnabled ? 0x2 : 0) |
            (cacheMinTtlEnabled ? 0x4 : 0) |
            (cacheStaleFallbackEnabled ? 0x8 : 0) |
            (dynamicBlockEnabled ? 0x10 : 0) |
            (blockHttpsSvcb ? 0x20 : 0) |
            (rebindingProtection ? 0x40 : 0) |
            (dns64Enabled ? 0x80 : 0),
      )
      ..u8(connectionRateLimitEnabled ? 0x1 : 0)
      ..utf8(modeRaw)
      ..utf8(selectedProviderId)
      ..strings(smartPredictionProviderIds)
      ..strings(parallelRaceProviderIds)
      ..strings(primaryBackupProviderIds)
      ..optionalUtf8(userProvidersJson)
      ..strings(bootstrapPresetIds)
      ..optionalUtf8(bootstrapCustomJson)
      ..utf8(blockResponseModeRaw)
      ..utf8(cacheModeRaw)
      ..i32(cacheMaxTtlSeconds)
      ..i32(cacheFixedTtlSeconds)
      ..i32(cacheMinTtlSeconds)
      ..i32(cacheStaleFallbackSeconds)
      ..i32(dynamicBlockRequestThreshold)
      ..i32(dynamicBlockWindowSeconds)
      ..i32(dynamicBlockNxDomainDurationSeconds)
      ..i32(connectionRateLimitRate)
      ..i32(connectionRateLimitBurst)
      ..providerRows(presetProviders)
      ..bootstrapEntryRows(presetBootstrap);
    final reader = _call('tunnel', writer);
    final mode = reader.string();
    final document = reader.string();
    final providers = reader.providerRows();
    return (
      mode: mode,
      document: document,
      providers: providers,
      bootstrap: reader.bootstrapEntryRows(),
    );
  }

}
