/// Builds the exact JSON for `Engine.applyDNSConfig`; the Go side rejects unknown fields. Below two
/// providers, resolution falls back to the selected one.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';

import 'package:diting_android/data/mock_data.dart';
import 'package:diting_shared/data/prefs/legacy_settings.dart';

enum DnsProtocol {
  dns('DNS', 'PLAIN'),
  doh('DOH', 'DOH'),
  dot('DOT', 'DOT');

  const DnsProtocol(this.storageValue, this.goValue);

  final String storageValue;
  final String goValue;

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

  String get hostPort => host.contains(':') && !host.startsWith('[')
      ? '[$host]:$port'
      : '$host:$port';

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

  Map<String, Object?> toJson() => {
    'id': id,
    'protocol': protocol.goValue,
    'server': protocol == DnsProtocol.doh ? '' : hostPort,
    'url': url,
  };
}

class BootstrapEntry {
  const BootstrapEntry(this.id, this.name, this.ip, {this.enabled = true});

  final String id;
  final String name;
  final String ip;

  /// Only for custom entries in `bootstrap_custom_json`; presets are filtered earlier.
  final bool enabled;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'ip': ip};
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
  ),
  DnsProviderEntry(
    id: 'preset_dnspod_dot',
    name: l10n.upstreamPresetTencent,
    protocol: DnsProtocol.dot,
    host: 'dot.pub',
  ),
  DnsProviderEntry(
    id: 'preset_360_dot',
    name: '360',
    protocol: DnsProtocol.dot,
    host: 'dot.360.cn',
  ),
  DnsProviderEntry(
    id: 'preset_onedns_dot',
    name: 'OneDNS',
    protocol: DnsProtocol.dot,
    host: 'dot.onedns.net',
  ),
  DnsProviderEntry(
    id: 'preset_cloudflare_dot',
    name: 'Cloudflare',
    protocol: DnsProtocol.dot,
    host: 'one.one.one.one',
  ),
  DnsProviderEntry(
    id: 'preset_google_dot',
    name: 'Google',
    protocol: DnsProtocol.dot,
    host: 'dns.google',
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

const _defaultSelectedProviderId = 'preset_alidns_dns';
const _defaultRaceIds = ['preset_alidns_dns', 'preset_dnspod_dns'];

class DnsConfig {
  DnsConfig({
    required this.mode,
    required this.providers,
    required this.bootstrap,
  });

  final String mode;
  final List<DnsProviderEntry> providers;
  final List<BootstrapEntry> bootstrap;

  Map<String, Object?> toJson(LegacySettings settings) => {
    'mode': mode,
    'blockResponse': _goBlockResponse(settings.blockResponseModeRaw),
    'dynamicResponse': {
      'enabled': _bool(settings, 'dynamic_block_response_enabled', false),
      'requestThreshold': _int(
        settings,
        'dynamic_block_request_threshold',
        5,
      ).clamp(2, 100),
      'windowSeconds': _int(
        settings,
        'dynamic_block_window_seconds',
        60,
      ).clamp(10, 300),
      'nxDomainDurationSeconds': _int(
        settings,
        'dynamic_block_nxdomain_duration_seconds',
        300,
      ).clamp(60, 3600),
    },
    'cache': {
      'enabled': settings.cacheEnabled,
      'mode': settings.cacheModeRaw,
      'maxTtlSeconds': settings.cacheMaxTtlSeconds.clamp(30, 86400),
      'fixedTtlSeconds': settings.cacheFixedTtlSeconds.clamp(30, 86400),
      'minTtlEnabled': settings.cacheMinTtlEnabled,
      'minTtlSeconds': settings.cacheMinTtlSeconds.clamp(30, 86400),
      'staleFallbackEnabled': settings.cacheStaleFallbackEnabled,
      'staleFallbackSeconds': settings.cacheStaleFallbackSeconds.clamp(
        30,
        86400,
      ),
      // 1.4.3 has no negative-TTL UI; the Go defaults are kept explicitly.
      'negativeTtlEnabled': true,
      'negativeTtlSeconds': 30,
    },
    'providers': [for (final provider in providers) provider.toJson()],
    'bootstrap': {
      'enabled': settings.bootstrapEnabled,
      'ips': [for (final entry in bootstrap) entry.toJson()],
    },
  };

  String encode(LegacySettings settings) => jsonEncode(toJson(settings));
}

DnsConfig buildDnsConfig(LegacySettings settings) {
  final all = [
    ...defaultDnsProviders(currentL10n),
    ...parseUserProviders(settings.userProvidersJson),
  ];
  final byId = {for (final provider in all) provider.id: provider};
  final mode = _validResolutionModes.contains(settings.resolutionModeRaw)
      ? settings.resolutionModeRaw
      : 'single';

  List<DnsProviderEntry> pick(List<String> ids) => [
    for (final id in ids)
      if (byId[id] != null) byId[id]!,
  ];

  List<DnsProviderEntry> providers;
  switch (mode) {
    case 'smart_prediction':
    case 'parallel_race':
      final ids = mode == 'smart_prediction'
          ? settings.smartPredictionProviderIds
          : settings.parallelRaceProviderIds;
      final picked = pick(ids.isEmpty ? _defaultRaceIds : ids);
      providers = picked.length >= 2
          ? picked
          : [_selected(byId, settings.selectedProviderId)];
    case 'primary_backup':
      final picked = pick(
        settings.primaryBackupProviderIds.isEmpty
            ? _defaultRaceIds
            : settings.primaryBackupProviderIds,
      );
      providers = picked.length >= 2
          ? picked
          : [_selected(byId, settings.selectedProviderId)];
    default:
      providers = [_selected(byId, settings.selectedProviderId)];
  }

  return DnsConfig(
    mode: mode,
    providers: providers,
    bootstrap: _bootstrapEntries(settings),
  );
}

DnsProviderEntry _selected(
  Map<String, DnsProviderEntry> byId,
  String selectedId,
) =>
    byId[selectedId] ??
    byId[_defaultSelectedProviderId] ??
    defaultDnsProviders(currentL10n).first;

List<DnsProviderEntry> parseUserProviders(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final providers = <DnsProviderEntry>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final protocol = DnsProtocol.fromStorage(item['protocol'] as String?);
    if (protocol == null) continue;
    final id = item['id'] as String?;
    final name = item['name'] as String?;
    if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
    final url = (item['url'] as String?)?.trim() ?? '';
    final host = (item['host'] as String?)?.trim() ?? '';
    final port = item['port'] is int ? item['port'] as int : 853;
    if (protocol == DnsProtocol.doh) {
      if (!url.toLowerCase().startsWith('https://')) continue;
      providers.add(
        DnsProviderEntry(id: id, name: name, protocol: protocol, url: url),
      );
    } else {
      if (host.isEmpty || port < 1 || port > 65535) continue;
      providers.add(
        DnsProviderEntry(
          id: id,
          name: name,
          protocol: protocol,
          host: host,
          port: port,
        ),
      );
    }
  }
  return providers;
}

List<BootstrapEntry> _bootstrapEntries(LegacySettings settings) {
  if (!settings.bootstrapEnabled) return const [];
  final selected = settings.bootstrapPresetIds.toSet();
  final entries = [
    for (final entry in defaultBootstrapEntries(currentL10n))
      if (selected.contains(entry.id)) entry,
  ];
  final raw = settings.bootstrapCustomJson;
  if (raw == null || raw.isEmpty) return entries;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return entries;
  }
  if (decoded is! List) return entries;
  for (final item in decoded) {
    if (item is! Map) continue;
    if (item['enabled'] == false) continue;
    final ip = (item['ip'] as String?)?.trim() ?? '';
    if (ip.isEmpty) continue;
    final id = (item['id'] as String?)?.trim();
    final name = (item['name'] as String?)?.trim();
    entries.add(
      BootstrapEntry(
        id == null || id.isEmpty ? 'custom_$ip' : id,
        name == null || name.isEmpty ? ip : name,
        ip,
      ),
    );
  }
  return entries;
}

bool _bool(LegacySettings settings, String key, bool fallback) {
  final value = settings.rawValue(key);
  return value is bool ? value : fallback;
}

int _int(LegacySettings settings, String key, int fallback) {
  final value = settings.rawValue(key);
  return value is int ? value : fallback;
}

const _validResolutionModes = {
  'single',
  'smart_prediction',
  'parallel_race',
  'primary_backup',
};

String _goBlockResponse(String storageValue) => switch (storageValue) {
  'nodata' => 'NODATA',
  'refused' => 'REFUSED',
  'zero_address' => 'CUSTOM_IP',
  _ => 'NXDOMAIN',
};
