library;

import 'dart:convert';

import 'package:diting_android/data/server/server_models.dart';

/// 把服务器配置映射成内核的 `DnsConfig` 文档。
///
/// 这里是服务器模式与普通/简洁模式共用 Rust 内核的关键：上游调度、缓存、
/// Bootstrap、阻断响应都交给内核解析，不再维护第二套 DNS 配置格式。
String encodeServerDnsConfig(ServerConfig config) {
  final upstream = config.upstream;
  final cache = config.cache;
  final filter = config.filter;
  return jsonEncode({
    'mode': upstream.mode,
    'providers': [
      for (final provider in upstream.providers)
        {
          'id': provider.id,
          'protocol': provider.protocol,
          'server': provider.protocol == 'DOH' ? '' : provider.server,
          'url': provider.protocol == 'DOH' ? provider.url : '',
          'weight': provider.weight,
          'pin': provider.pin,
        },
    ],
    'blockResponse': switch (filter.blockMode) {
      'nxdomain' => 'NXDOMAIN',
      'refused' => 'REFUSED',
      _ => '0.0.0.0',
    },
    'dynamicResponse': const {
      'enabled': false,
      'requestThreshold': 0,
      'windowSeconds': 0,
      'nxDomainDurationSeconds': 0,
    },
    'cache': {
      'enabled': cache.enabled,
      'mode': cache.mode == 'fixed' ? 'fixed_ttl' : 'limit_max_ttl',
      'ttlScalePercent': 100,
      'maxTtlSeconds': cache.maxTtlSeconds,
      'fixedTtlSeconds': cache.fixedTtlSeconds,
      'minTtlEnabled': cache.minTtlEnabled,
      'minTtlSeconds': cache.minTtlSeconds,
      'staleFallbackEnabled': cache.staleFallbackEnabled,
      'staleFallbackSeconds': cache.staleFallbackSeconds,
      'negativeTtlEnabled': cache.negativeTtlEnabled,
      'negativeTtlSeconds': cache.negativeTtlSeconds,
      'maxEntries': cache.maxEntries,
    },
    'bootstrap': {
      'enabled': upstream.bootstrapEnabled,
      'ips': [
        for (final entry in upstream.bootstrap)
          {
            'id': entry.id,
            'name': entry.name,
            'ip': entry.address,
            'weight': entry.weight,
          },
      ],
    },
    'privacy': const {
      'blockRecordTypes': <String>[],
      'rebindingProtection': false,
    },
    'dns64': const {'enabled': false},
    'rateLimit': const {
      'enabled': false,
      'rate': 0,
      'burst': 0,
      'ipv4Prefix': 0,
      'ipv6Prefix': 0,
      'exempt': <String>[],
    },
    'connectionRateLimit': null,
    'raceMaxParallel': null,
  });
}
