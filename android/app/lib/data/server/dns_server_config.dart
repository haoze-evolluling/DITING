/// DNS snapshot for server mode (`DnsServerEngine.applyDnsConfig`), read from
/// `diting_dns_mode_prefs`; the Go engine rejects unknown fields.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:convert';

import 'package:diting_shared/data/prefs/legacy_settings.dart';
import 'package:diting_android/data/vpn/dns_config_builder.dart';

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

  String get hostPort => address.contains(':')
      ? '[${address.replaceAll(RegExp(r'^\[|\]$'), '')}]:$port'
      : '$address:$port';
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
    required this.upstream,
    required this.adBlockEnabled,
    required this.cache,
    required this.blockResponse,
    required this.dynamicResponse,
  });

  final int port;
  final ServerUpstream upstream;
  final bool adBlockEnabled;
  final Map<String, Object?> cache;
  final String blockResponse;
  final Map<String, Object?> dynamicResponse;

  Map<String, Object?> toJson() => {
    'mode': 'single',
    'blockResponse': blockResponse,
    'dynamicResponse': dynamicResponse,
    'cache': cache,
    'providers': [
      {
        'id': upstream.id,
        'protocol': upstream.protocol.goValue,
        'server': upstream.protocol == DnsProtocol.doh ? '' : upstream.hostPort,
        'url': upstream.protocol == DnsProtocol.doh ? upstream.address : '',
      },
    ],
    // Server mode never used bootstrap: LAN clients resolve through this device.
    'bootstrap': {'enabled': false, 'ips': <Object?>[]},
  };

  String encode() => jsonEncode(toJson());
}

ServerDnsConfig buildServerDnsConfig(LegacySettings settings) {
  final upstreams = serverUpstreams(settings);
  final byId = {for (final upstream in upstreams) upstream.id: upstream};
  final upstream =
      byId[settings.serverSelectedUpstreamId] ??
      byId['preset_alidns_dns'] ??
      serverPresetUpstreams(currentL10n).first;
  return ServerDnsConfig(
    port: settings.serverPort,
    upstream: upstream,
    adBlockEnabled: settings.serverAdBlockEnabled,
    cache: _cachePolicy(
      settings.serverCachePresetRaw,
      settings.serverCacheEnabled,
    ),
    blockResponse: _goBlockResponse(settings.serverBlockResponseModeRaw),
    dynamicResponse: {
      'enabled': settings.serverDynamicBlockEnabled,
      'requestThreshold': settings.serverDynamicBlockThreshold.clamp(2, 100),
      'windowSeconds': settings.serverDynamicBlockWindowSeconds.clamp(10, 300),
      'nxDomainDurationSeconds': settings
          .serverDynamicBlockNxDomainDurationSeconds
          .clamp(60, 3600),
    },
  );
}

List<ServerUpstream> serverUpstreams(LegacySettings settings) => [
  ...serverPresetUpstreams(currentL10n),
  ...parseServerCustomUpstreams(settings.serverCustomUpstreamsJson),
];

List<ServerUpstream> parseServerCustomUpstreams(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final upstreams = <ServerUpstream>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = (item['id'] as String?)?.trim();
    final name = (item['name'] as String?)?.trim();
    final address = (item['address'] as String?)?.trim();
    if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
    if (address == null || address.isEmpty) continue;
    final protocol =
        DnsProtocol.fromStorage(item['protocol'] as String?) ?? DnsProtocol.dns;
    final port = item['port'] is int
        ? item['port'] as int
        : protocol == DnsProtocol.dot
        ? 853
        : 53;
    if (protocol == DnsProtocol.doh) {
      if (!address.toLowerCase().startsWith('https://')) continue;
    } else if (port < 1 || port > 65535) {
      continue;
    }
    upstreams.add(
      ServerUpstream(
        id: id,
        name: name,
        protocol: protocol,
        address: address,
        port: port,
      ),
    );
  }
  return upstreams;
}

/// Encodes custom upstreams for `custom_upstreams`: `id`, `name`, `protocol`, `address`, `port`;
/// `isCustom` comes from the `preset_` prefix.
String encodeServerCustomUpstreams(List<ServerUpstream> servers) => jsonEncode([
  for (final server in servers)
    {
      'id': server.id,
      'name': server.name,
      'protocol': server.protocol.storageValue,
      'address': server.address,
      'port': server.port,
    },
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
/// and bracketed IPv6 is accepted but stored bare.
UpstreamValidation validateServerUpstream({
  required String name,
  required DnsProtocol protocol,
  required String address,
  required int port,
}) {
  if (name.trim().isEmpty) {
    return UpstreamInvalid(currentL10n.upstreamNameRequired);
  }
  final trimmed = address.trim();
  if (trimmed.isEmpty) {
    return UpstreamInvalid(currentL10n.upstreamAddressRequired);
  }
  if (protocol == DnsProtocol.doh) {
    if (!trimmed.toLowerCase().startsWith('https://')) {
      return UpstreamInvalid(currentL10n.upstreamDohNeedsHttps);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return UpstreamInvalid(currentL10n.upstreamDohInvalidUrl);
    }
    return const UpstreamOk();
  }
  if (port < 1 || port > 65535) {
    return UpstreamInvalid(currentL10n.upstreamPortRange);
  }
  // A bare IPv6 address must parse as host-only, otherwise the engine fails when it joins
  // host:port.
  final bare = _stripBrackets(trimmed);
  if (bare.contains(':') && Uri.tryParse('http://[$bare]') == null) {
    return UpstreamInvalid(currentL10n.upstreamIpv6Invalid);
  }
  return const UpstreamOk();
}

String normalizeServerUpstreamAddress(DnsProtocol protocol, String address) =>
    protocol == DnsProtocol.doh
    ? address.trim()
    : _stripBrackets(address.trim());

String _stripBrackets(String value) {
  var result = value;
  if (result.startsWith('[')) result = result.substring(1);
  if (result.endsWith(']')) result = result.substring(0, result.length - 1);
  return result;
}

Map<String, Object?> _cachePolicy(String preset, bool enabled) {
  switch (preset) {
    case 'conservative':
      return {
        'enabled': enabled,
        'mode': 'follow_dns_ttl',
        'maxTtlSeconds': 3600,
        'fixedTtlSeconds': 3600,
        'minTtlEnabled': false,
        'minTtlSeconds': 60,
        'staleFallbackEnabled': false,
        'staleFallbackSeconds': 300,
        'negativeTtlEnabled': true,
        'negativeTtlSeconds': 15,
      };
    case 'high_hit_rate':
      return {
        'enabled': enabled,
        'mode': 'limit_max_ttl',
        'maxTtlSeconds': 21600,
        'fixedTtlSeconds': 3600,
        'minTtlEnabled': true,
        'minTtlSeconds': 120,
        'staleFallbackEnabled': true,
        'staleFallbackSeconds': 900,
        'negativeTtlEnabled': true,
        'negativeTtlSeconds': 60,
      };
    default:
      return {
        'enabled': enabled,
        'mode': 'limit_max_ttl',
        'maxTtlSeconds': 3600,
        'fixedTtlSeconds': 3600,
        'minTtlEnabled': true,
        'minTtlSeconds': 60,
        'staleFallbackEnabled': true,
        'staleFallbackSeconds': 300,
        'negativeTtlEnabled': true,
        'negativeTtlSeconds': 30,
      };
  }
}

String _goBlockResponse(String value) => switch (value) {
  'nodata' => 'NODATA',
  'refused' => 'REFUSED',
  'zero_address' => 'CUSTOM_IP',
  _ => 'NXDOMAIN',
};
