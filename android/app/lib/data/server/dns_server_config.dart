/// DNS snapshot for server mode (`DnsServerEngine.applyDnsConfig`), read from
/// `diting_dns_mode_prefs`; the Go engine rejects unknown fields.
///
/// The document — the picked upstream row(s) in engine attempt order, the cache preset's nine
/// values, the block/dynamic keys and their clamps — is assembled in
/// `rust/diting-dns-config-core/src/document.rs`. This file keeps the preset labels and the
/// editor's validation messages.
library;

import 'dart:convert';

import 'package:diting_android/data/vpn/dns_config_builder.dart';
import 'package:diting_android/data/vpn/rust_dns_config_core.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

class ServerUpstream {
  const ServerUpstream({
    required this.id,
    required this.name,
    required this.protocol,
    required this.address,
    required this.port,
  });

  final String id;
  final String name;
  final DnsProtocol protocol;
  final String address;
  final int port;

  String get endpointLabel => protocol == DnsProtocol.doh
      ? '${protocol.storageValue} · $address'
      : '${protocol.storageValue} · $address:$port';

  /// `host:port` with a bare IPv6 address bracketed; the join itself lives in the kernel.
  String get hostPort =>
      RustDnsConfigCore.instance.serverHostPort(address, port);
}

List<ServerUpstream> serverPresetUpstreams(AppL10n l10n) => <ServerUpstream>[
  ServerUpstream(
    id: 'preset_alidns_dns',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.dns,
    address: '223.5.5.5',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_dnspod_dns',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.dns,
    address: '119.29.29.29',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_360_dns',
    name: '360',
    protocol: DnsProtocol.dns,
    address: '101.226.4.6',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_onedns_dns',
    name: 'OneDNS',
    protocol: DnsProtocol.dns,
    address: '117.50.10.10',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_cloudflare_dns',
    name: 'Cloudflare',
    protocol: DnsProtocol.dns,
    address: '1.1.1.1',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_google_dns',
    name: 'Google',
    protocol: DnsProtocol.dns,
    address: '8.8.8.8',
    port: 53,
  ),
  ServerUpstream(
    id: 'preset_alidns_doh',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.doh,
    address: 'https://dns.alidns.com/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_dnspod_doh',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.doh,
    address: 'https://doh.pub/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_360_doh',
    name: '360',
    protocol: DnsProtocol.doh,
    address: 'https://doh.360.cn/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_onedns_doh',
    name: 'OneDNS',
    protocol: DnsProtocol.doh,
    address: 'https://doh.onedns.net/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_cloudflare_doh',
    name: 'Cloudflare',
    protocol: DnsProtocol.doh,
    address: 'https://cloudflare-dns.com/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_google_doh',
    name: 'Google',
    protocol: DnsProtocol.doh,
    address: 'https://dns.google/dns-query',
    port: 443,
  ),
  ServerUpstream(
    id: 'preset_alidns_dot',
    name: l10n.upstreamPresetAliyun,
    protocol: DnsProtocol.dot,
    address: 'dns.alidns.com',
    port: 853,
  ),
  ServerUpstream(
    id: 'preset_dnspod_dot',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.dot,
    address: 'dot.pub',
    port: 853,
  ),
  ServerUpstream(
    id: 'preset_360_dot',
    name: '360',
    protocol: DnsProtocol.dot,
    address: 'dot.360.cn',
    port: 853,
  ),
  ServerUpstream(
    id: 'preset_onedns_dot',
    name: 'OneDNS',
    protocol: DnsProtocol.dot,
    address: 'dot.onedns.net',
    port: 853,
  ),
  ServerUpstream(
    id: 'preset_cloudflare_dot',
    name: 'Cloudflare',
    protocol: DnsProtocol.dot,
    address: 'one.one.one.one',
    port: 853,
  ),
  ServerUpstream(
    id: 'preset_google_dot',
    name: 'Google',
    protocol: DnsProtocol.dot,
    address: 'dns.google',
    port: 853,
  ),
];

class ServerDnsConfig {
  const ServerDnsConfig({
    required this.port,
    required this.mode,
    required this.providers,
    required this.adBlockEnabled,
    required this.document,
  });

  final int port;

  /// The scheduling mode written to the document (`single` / `smart_prediction` /
  /// `parallel_race` / `primary_backup`).
  final String mode;

  /// The upstreams in engine attempt order: one for `single`, the picked race list otherwise.
  final List<ServerUpstream> providers;

  /// The domain-rule master switch (`domain_rules_enabled`, read through
  /// `LegacyServerSettings.serverAdBlockEnabled`). The service hands it to `setFilterDNS`, and the
  /// rule snapshot uses the same key as its own `filterEnabled`, so the two gates agree.
  final bool adBlockEnabled;

  /// The whole document, as the kernel assembled it.
  final String document;

  /// The first upstream; what the single-mode UI and the notification name.
  ServerUpstream get upstream => providers.first;

  int get providerCount => providers.length;

  Map<String, Object?> toJson() =>
      jsonDecode(document) as Map<String, Object?>;

  String encode() => document;
}

ServerUpstream serverUpstreamOf(ServerUpstreamRow row) => ServerUpstream(
  id: row.id,
  name: row.name,
  protocol: DnsProtocol.fromStorage(row.protocolStorage) ?? DnsProtocol.dns,
  address: row.address,
  port: row.port,
);

ServerUpstreamRow serverUpstreamRowOf(ServerUpstream upstream) => (
  id: upstream.id,
  name: upstream.name,
  protocolStorage: upstream.protocol.storageValue,
  address: upstream.address,
  port: upstream.port,
);

ServerDnsConfig buildServerDnsConfig(LegacySettings settings) {
  // Resolution mode and candidate lists are data-set scoped; read them through a server view so a
  // call with the normal / express settings object still uses the server data set's own values.
  final serverScope = settings.forServer();
  final document = RustDnsConfigCore.instance.buildServer(
    resolutionModeRaw: serverScope.resolutionModeRaw,
    selectedUpstreamId: settings.serverSelectedUpstreamId,
    smartPredictionProviderIds: serverScope.smartPredictionProviderIds,
    parallelRaceProviderIds: serverScope.parallelRaceProviderIds,
    primaryBackupProviderIds: serverScope.primaryBackupProviderIds,
    port: settings.serverPort,
    adBlockEnabled: settings.serverAdBlockEnabled,
    cachePresetRaw: settings.serverCachePresetRaw,
    cacheEnabled: settings.serverCacheEnabled,
    blockResponseModeRaw: settings.serverBlockResponseModeRaw,
    dynamicBlockEnabled: settings.serverDynamicBlockEnabled,
    dynamicBlockRequestThreshold: settings.serverDynamicBlockThreshold,
    dynamicBlockWindowSeconds: settings.serverDynamicBlockWindowSeconds,
    dynamicBlockNxDomainDurationSeconds:
        settings.serverDynamicBlockNxDomainDurationSeconds,
    customUpstreamsJson: settings.serverCustomUpstreamsJson,
    blockHttpsSvcb: settings.blockHttpsSvcbRecordTypes,
    rebindingProtection: settings.dnsRebindingProtection,
    dns64Enabled: settings.dns64Enabled,
    rateLimitEnabled: settings.lanRateLimitEnabled,
    rateLimitRate: settings.lanRateLimitRate,
    rateLimitBurst: settings.lanRateLimitBurst,
    rateLimitIpv4Prefix: settings.lanRateLimitIpv4Prefix,
    rateLimitIpv6Prefix: settings.lanRateLimitIpv6Prefix,
    rateLimitExemptCsv: settings.lanRateLimitExemptCsv,
    presetUpstreams: [
      for (final upstream in serverPresetUpstreams(currentL10n))
        serverUpstreamRowOf(upstream),
    ],
  );
  return ServerDnsConfig(
    port: document.port,
    mode: document.mode,
    providers: [
      for (final row in document.providers) serverUpstreamOf(row),
    ],
    adBlockEnabled: settings.serverAdBlockEnabled,
    document: document.document,
  );
}

List<ServerUpstream> serverUpstreams(LegacySettings settings) => [
  ...serverPresetUpstreams(currentL10n),
  ...parseServerCustomUpstreams(settings.serverCustomUpstreamsJson),
];

/// Reads `custom_upstreams`, dropping rows the editor could not have produced.
List<ServerUpstream> parseServerCustomUpstreams(String? raw) => [
  for (final row in RustDnsConfigCore.instance.parseCustomUpstreams(raw))
    serverUpstreamOf(row),
];

/// Encodes custom upstreams for `custom_upstreams`: `id`, `name`, `protocol`, `address`, `port`;
/// `isCustom` comes from the `preset_` prefix.
String encodeServerCustomUpstreams(List<ServerUpstream> servers) =>
    RustDnsConfigCore.instance.encodeCustomUpstreams([
      for (final server in servers) serverUpstreamRowOf(server),
    ]);

sealed class UpstreamValidation {
  const UpstreamValidation();
}

class UpstreamOk extends UpstreamValidation {
  const UpstreamOk();
}

class UpstreamInvalid extends UpstreamValidation {
  const UpstreamInvalid(this.message);

  final String message;
}

/// Validates one custom upstream: DoH needs an `https://` address, DNS/DoT default to ports 53/853,
/// and bracketed IPv6 is accepted but stored bare. The decision is the kernel's; the sentence is
/// this app's.
UpstreamValidation validateServerUpstream({
  required String name,
  required DnsProtocol protocol,
  required String address,
  required int port,
}) {
  final rejection = RustDnsConfigCore.instance.validateUpstream(
    name: name,
    protocolStorage: protocol.storageValue,
    address: address,
    port: port,
  );
  return switch (rejection) {
    null => const UpstreamOk(),
    UpstreamRejection.nameRequired => UpstreamInvalid(
      currentL10n.upstreamNameRequired,
    ),
    UpstreamRejection.addressRequired => UpstreamInvalid(
      currentL10n.upstreamAddressRequired,
    ),
    UpstreamRejection.dohNeedsHttps => UpstreamInvalid(
      currentL10n.upstreamDohNeedsHttps,
    ),
    UpstreamRejection.dohInvalidUrl => UpstreamInvalid(
      currentL10n.upstreamDohInvalidUrl,
    ),
    UpstreamRejection.portRange => UpstreamInvalid(
      currentL10n.upstreamPortRange,
    ),
    UpstreamRejection.ipv6Invalid => UpstreamInvalid(
      currentL10n.upstreamIpv6Invalid,
    ),
  };
}

String normalizeServerUpstreamAddress(DnsProtocol protocol, String address) =>
    RustDnsConfigCore.instance.normalizeUpstreamAddress(
      protocol.storageValue,
      address,
    );
