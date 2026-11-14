part of 'rust_dns_config_core.dart';

/// The two document builders. They live in a part so the FFI loader file stays within the
/// 600-line repository limit; an extension in the same library can read the private op handles and
/// `_call`, so the split is purely mechanical.
extension DocumentBuilders on RustDnsConfigCore {
  /// Builds the tunnel's `ApplyDNSConfig` document plus the rows the UI shows.
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
      ..providerRows(presetProviders)
      ..bootstrapEntryRows(presetBootstrap);
    final reader = _call(_tunnel, writer);
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

  /// Builds server mode's `applyDnsConfig` document plus the upstreams it picked.
  ///
  /// The resolution mode and its candidate lists use the same scheduling kernel as the tunnel, so
  /// `single` picks one upstream and the three race modes pick their list in engine attempt order.
  ServerDocument buildServer({
    required String resolutionModeRaw,
    required String selectedUpstreamId,
    required List<String> smartPredictionProviderIds,
    required List<String> parallelRaceProviderIds,
    required List<String> primaryBackupProviderIds,
    required int port,
    required bool adBlockEnabled,
    required String cachePresetRaw,
    required bool cacheEnabled,
    required String blockResponseModeRaw,
    required bool dynamicBlockEnabled,
    required int dynamicBlockRequestThreshold,
    required int dynamicBlockWindowSeconds,
    required int dynamicBlockNxDomainDurationSeconds,
    required String? customUpstreamsJson,
    required List<ServerUpstreamRow> presetUpstreams,
    bool blockHttpsSvcb = false,
    bool rebindingProtection = false,
    bool dns64Enabled = false,
    bool rateLimitEnabled = false,
    int rateLimitRate = 0,
    int rateLimitBurst = 0,
    int rateLimitIpv4Prefix = 0,
    int rateLimitIpv6Prefix = 0,
    String rateLimitExemptCsv = '',
  }) {
    final writer = _PayloadWriter()
      ..u8(
        (adBlockEnabled ? 0x1 : 0) |
            (cacheEnabled ? 0x2 : 0) |
            (dynamicBlockEnabled ? 0x4 : 0) |
            (blockHttpsSvcb ? 0x8 : 0) |
            (rebindingProtection ? 0x10 : 0) |
            (dns64Enabled ? 0x20 : 0) |
            (rateLimitEnabled ? 0x40 : 0),
      )
      ..utf8(resolutionModeRaw)
      ..utf8(selectedUpstreamId)
      ..strings(smartPredictionProviderIds)
      ..strings(parallelRaceProviderIds)
      ..strings(primaryBackupProviderIds)
      ..i32(port)
      ..utf8(cachePresetRaw)
      ..utf8(blockResponseModeRaw)
      ..i32(dynamicBlockRequestThreshold)
      ..i32(dynamicBlockWindowSeconds)
      ..i32(dynamicBlockNxDomainDurationSeconds)
      ..optionalUtf8(customUpstreamsJson)
      ..i32(rateLimitRate)
      ..i32(rateLimitBurst)
      ..i32(rateLimitIpv4Prefix)
      ..i32(rateLimitIpv6Prefix)
      ..utf8(rateLimitExemptCsv)
      ..upstreamRows(presetUpstreams);
    final reader = _call(_server, writer);
    final resolvedPort = reader.i32();
    final mode = reader.string();
    final document = reader.string();
    final upstreams = reader.upstreamRows();
    if (upstreams.isEmpty) {
      throw StateError('dns config core returned no upstream');
    }
    return (
      port: resolvedPort,
      mode: mode,
      document: document,
      providers: upstreams,
    );
  }
}
