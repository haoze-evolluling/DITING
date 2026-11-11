/// Builds the exact JSON for `Engine.applyDNSConfig`; the Go side rejects unknown fields. Below two
/// providers, resolution falls back to the selected one.
///
/// The document itself — mode selection, the provider pick, the cache / block / dynamic keys and
/// their clamps — comes from `rust/diting-dns-config-core/src/document.rs`. This file keeps the
/// catalog labels (they are localised) and the row types the UI carries around.
library;

import 'dart:convert';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/data/vpn/rust_dns_config_core.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DnsProtocol {
  dns('DNS'),
  doh('DOH'),
  dot('DOT');

  const DnsProtocol(this.storageValue);

  /// The prefs spelling, which is also what the kernel exchanges.
  final String storageValue;

  static DnsProtocol? fromStorage(String? value) {
    final upper = value?.toUpperCase();
    for (final protocol in values) {
      if (protocol.storageValue == upper) return protocol;
    }
    return null;
  }
}

class DnsProviderEntry {
  const DnsProviderEntry({
    required this.id,
    required this.name,
    required this.protocol,
    this.url = '',
    this.host = '',
    this.port = 853,
  });

  final String id;
  final String name;
  final DnsProtocol protocol;
  final String url;
  final String host;
  final int port;

  /// `host:port` with a bare IPv6 host bracketed; the join itself lives in the kernel.
  String get hostPort => RustDnsConfigCore.instance.joinHostPort(host, port);

  /// Endpoint as 1.4.3 renders it (`[DoH] https://...` / `[DNS] 1.1.1.1:53`).
  String get endpointLabel => switch (protocol) {
    DnsProtocol.doh => '[${protocol.storageValue}] $url',
    _ => '[${protocol.storageValue}] $hostPort',
  };

  /// `host:port` edited by the management UI; DoH providers keep it empty.
  String get address => protocol == DnsProtocol.doh ? url : hostPort;

  MockProvider toMock({int latencyMs = 0, bool isPreset = false}) =>
      MockProvider(
        id: id,
        name: name,
        protocol: switch (protocol) {
          DnsProtocol.dns => ProviderProtocol.dns,
          DnsProtocol.doh => ProviderProtocol.doh,
          DnsProtocol.dot => ProviderProtocol.dot,
        },
        address: switch (protocol) {
          DnsProtocol.doh => url,
          _ => hostPort,
        },
        latencyMs: latencyMs,
        isPreset: isPreset,
      );
}

/// `host:port`, bracketing bare IPv6 hosts so the engine can parse the result.
String joinHostPort(String host, int port) =>
    RustDnsConfigCore.instance.joinHostPort(host, port);

class BootstrapEntry {
  const BootstrapEntry(this.id, this.name, this.ip, {this.enabled = true});

  final String id;
  final String name;
  final String ip;

  /// Only for custom entries in `bootstrap_custom_json`; presets are filtered earlier.
  final bool enabled;
}

List<DnsProviderEntry> defaultDnsProviders(AppL10n l10n) => <DnsProviderEntry>[
  DnsProviderEntry(
    id: 'preset_alidns_dns',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.dns,
    host: '223.5.5.5',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_dnspod_dns',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.dns,
    host: '119.29.29.29',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_360_dns',
    name: '360',
    protocol: DnsProtocol.dns,
    host: '101.226.4.6',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_onedns_dns',
    name: 'OneDNS',
    protocol: DnsProtocol.dns,
    host: '117.50.10.10',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_cloudflare_dns',
    name: 'Cloudflare',
    protocol: DnsProtocol.dns,
    host: '1.1.1.1',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_google_dns',
    name: 'Google',
    protocol: DnsProtocol.dns,
    host: '8.8.8.8',
    port: 53,
  ),
  DnsProviderEntry(
    id: 'preset_alidns_doh',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.doh,
    url: 'https://dns.alidns.com/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_dnspod_doh',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.doh,
    url: 'https://doh.pub/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_360_doh',
    name: '360',
    protocol: DnsProtocol.doh,
    url: 'https://doh.360.cn/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_onedns_doh',
    name: 'OneDNS',
    protocol: DnsProtocol.doh,
    url: 'https://doh.onedns.net/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_cloudflare_doh',
    name: 'Cloudflare',
    protocol: DnsProtocol.doh,
    url: 'https://cloudflare-dns.com/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_google_doh',
    name: 'Google',
    protocol: DnsProtocol.doh,
    url: 'https://dns.google/dns-query',
  ),
  DnsProviderEntry(
    id: 'preset_alidns_dot',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.dot,
    host: 'dns.alidns.com',
    port: 853,
  ),
  DnsProviderEntry(
    id: 'preset_dnspod_dot',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.dot,
    host: 'dot.pub',
    port: 853,
  ),
  DnsProviderEntry(
    id: 'preset_360_dot',
    name: '360',
    protocol: DnsProtocol.dot,
    host: 'dot.360.cn',
    port: 853,
  ),
  DnsProviderEntry(
    id: 'preset_onedns_dot',
    name: 'OneDNS',
    protocol: DnsProtocol.dot,
    host: 'dot.onedns.net',
    port: 853,
  ),
  DnsProviderEntry(
    id: 'preset_cloudflare_dot',
    name: 'Cloudflare',
    protocol: DnsProtocol.dot,
    host: 'one.one.one.one',
    port: 853,
  ),
  DnsProviderEntry(
    id: 'preset_google_dot',
    name: 'Google',
    protocol: DnsProtocol.dot,
    host: 'dns.google',
    port: 853,
  ),
];

List<BootstrapEntry> defaultBootstrapEntries(AppL10n l10n) => <BootstrapEntry>[
  BootstrapEntry('preset_alidns', l10n.upstreamPresetAliyun, '223.5.5.5'),
  BootstrapEntry('preset_dnspod', l10n.upstreamPresetTencent, '119.29.29.29'),
  BootstrapEntry(
    'preset_volcengine',
    l10n.upstreamPresetByteDance,
    '180.184.1.1',
  ),
  BootstrapEntry('preset_cnnic', 'CNNIC DNS', '1.2.4.8'),
  BootstrapEntry('preset_114dns', '114DNS', '114.114.114.114'),
  BootstrapEntry('preset_cloudflare', 'Cloudflare', '1.1.1.1'),
  BootstrapEntry('preset_google', 'Google', '8.8.8.8'),
];

/// The row the kernel exchanges for one provider.
ProviderRow providerRowOf(DnsProviderEntry entry) => (
  id: entry.id,
  name: entry.name,
  protocolStorage: entry.protocol.storageValue,
  url: entry.url,
  host: entry.host,
  port: entry.port,
);

/// The UI type for one kernel row.
DnsProviderEntry providerEntryOf(ProviderRow row) => DnsProviderEntry(
  id: row.id,
  name: row.name,
  protocol: DnsProtocol.fromStorage(row.protocolStorage) ?? DnsProtocol.dns,
  url: row.url,
  host: row.host,
  port: row.port,
);

class DnsConfig {
  DnsConfig({
    required this.mode,
    required this.providers,
    required this.bootstrap,
  });

  final String mode;
  final List<DnsProviderEntry> providers;
  final List<BootstrapEntry> bootstrap;

  /// The document `ApplyDNSConfig` receives, rebuilt from [settings] so a late settings change is
  /// never pushed stale.
  Map<String, Object?> toJson(LegacySettings settings) =>
      jsonDecode(encode(settings)) as Map<String, Object?>;

  String encode(LegacySettings settings) => tunnelDocument(settings).document;
}

/// One kernel call: the document plus the rows it picked.
TunnelDocument tunnelDocument(LegacySettings settings) =>
    RustDnsConfigCore.instance.buildTunnel(
      modeRaw: settings.resolutionModeRaw,
      selectedProviderId: settings.selectedProviderId,
      smartPredictionProviderIds: settings.smartPredictionProviderIds,
      parallelRaceProviderIds: settings.parallelRaceProviderIds,
      primaryBackupProviderIds: settings.primaryBackupProviderIds,
      userProvidersJson: settings.userProvidersJson,
      bootstrapEnabled: settings.bootstrapEnabled,
      bootstrapPresetIds: settings.bootstrapPresetIds.toList(),
      bootstrapCustomJson: settings.bootstrapCustomJson,
      blockResponseModeRaw: settings.blockResponseModeRaw,
      cacheEnabled: settings.cacheEnabled,
      cacheModeRaw: settings.cacheModeRaw,
      cacheMaxTtlSeconds: settings.cacheMaxTtlSeconds,
      cacheFixedTtlSeconds: settings.cacheFixedTtlSeconds,
      cacheMinTtlEnabled: settings.cacheMinTtlEnabled,
      cacheMinTtlSeconds: settings.cacheMinTtlSeconds,
      cacheStaleFallbackEnabled: settings.cacheStaleFallbackEnabled,
      cacheStaleFallbackSeconds: settings.cacheStaleFallbackSeconds,
      dynamicBlockEnabled: settings.dynamicBlockEnabled,
      dynamicBlockRequestThreshold: settings.dynamicBlockRequestThreshold,
      dynamicBlockWindowSeconds: settings.dynamicBlockWindowSeconds,
      dynamicBlockNxDomainDurationSeconds:
          settings.dynamicBlockNxDomainDurationSeconds,
      presetProviders: [
        for (final provider in defaultDnsProviders(currentL10n))
          providerRowOf(provider),
      ],
      presetBootstrap: [
        for (final entry in defaultBootstrapEntries(currentL10n))
          (id: entry.id, name: entry.name, ip: entry.ip),
      ],
    );

DnsConfig buildDnsConfig(LegacySettings settings) {
  final document = tunnelDocument(settings);
  return DnsConfig(
    mode: document.mode,
    providers: [for (final row in document.providers) providerEntryOf(row)],
    bootstrap: [
      for (final row in document.bootstrap)
        BootstrapEntry(row.id, row.name, row.ip),
    ],
  );
}

/// Parses `user_providers_json`, dropping the same rows 1.4.3 drops.
List<DnsProviderEntry> parseUserProviders(String? raw) => [
  for (final row in RustDnsConfigCore.instance.parseUserProviders(raw))
    providerEntryOf(row),
];

/// `bootstrap_custom_json` rows, including the toggle the settings page edits.
List<BootstrapEntry> parseCustomBootstrapEntries(String? raw) => [
  for (final row in RustDnsConfigCore.instance.parseCustomBootstrap(raw))
    BootstrapEntry(row.id, row.name, row.ip, enabled: row.enabled),
];

/// Writes the custom bootstrap rows back in the four-field shape the page edits.
String encodeCustomBootstrapEntries(List<BootstrapEntry> entries) =>
    RustDnsConfigCore.instance.encodeCustomBootstrap([
      for (final entry in entries)
        (id: entry.id, name: entry.name, ip: entry.ip, enabled: entry.enabled),
    ]);
