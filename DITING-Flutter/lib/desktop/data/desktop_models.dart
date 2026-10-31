import 'package:flutter/foundation.dart';

/// Immutable view models for the desktop UI. They intentionally mirror only the
/// fields consumed by the new shell; the Go API remains the source of truth.
@immutable
class DesktopSnapshot {
  const DesktopSnapshot({
    required this.version,
    required this.uptimeSeconds,
    required this.dns,
    required this.takeover,
    required this.metrics,
    this.cache,
    this.filter,
  });

  factory DesktopSnapshot.fromJson(Map<String, dynamic> json) {
    return DesktopSnapshot(
      version: json['version'] as String? ?? '',
      uptimeSeconds: _asInt(json['uptimeSeconds']),
      dns: DnsStatus.fromJson(_asMap(json['dns'])),
      takeover: TakeoverStatus.fromJson(_asMap(json['takeover'])),
      metrics: MetricsStatus.fromJson(_asMap(json['metrics'])),
      cache: json['cache'] is Map
          ? CacheStatus.fromJson(_asMap(json['cache']))
          : null,
      filter: json['filter'] is Map
          ? FilterStatus.fromJson(_asMap(json['filter']))
          : null,
    );
  }

  final String version;
  final int uptimeSeconds;
  final DnsStatus dns;
  final TakeoverStatus takeover;
  final MetricsStatus metrics;
  final CacheStatus? cache;
  final FilterStatus? filter;

  double get successRate => metrics.totalQueries == 0
      ? 1
      : metrics.successQueries / metrics.totalQueries;
}

@immutable
class DnsStatus {
  const DnsStatus({
    required this.running,
    required this.mode,
    required this.listenAddresses,
    required this.allowLan,
    required this.lanAddresses,
    required this.upstreams,
  });

  factory DnsStatus.fromJson(Map<String, dynamic> json) => DnsStatus(
    running: json['running'] == true,
    mode: json['mode'] as String? ?? '',
    listenAddresses: _asStrings(json['listenAddresses']),
    allowLan: json['allowLAN'] == true,
    lanAddresses: _asStrings(json['lanAddresses']),
    upstreams: [
      for (final item in json['upstreams'] as List? ?? const [])
        if (item is Map) UpstreamStatus.fromJson(_asMap(item)),
    ],
  );

  final bool running;
  final String mode;
  final List<String> listenAddresses;
  final bool allowLan;
  final List<String> lanAddresses;
  final List<UpstreamStatus> upstreams;

  String get modeLabel => switch (mode.toLowerCase()) {
    'single' => '单服务器',
    'primary_backup' || 'sequential' => '主备容灾',
    'parallel_race' || 'fastest' => '并发竞速',
    'smart_prediction' || 'load_balance' || 'smart' => '智能优选',
    _ when mode.isNotEmpty => mode,
    _ => '尚未配置',
  };

  String get primaryAddress => listenAddresses.isEmpty
      ? (allowLan ? '0.0.0.0:53' : '127.0.0.1:53')
      : listenAddresses.first;
}

@immutable
class UpstreamStatus {
  const UpstreamStatus({
    required this.id,
    required this.protocol,
    required this.server,
    required this.active,
    required this.averageLatencyMs,
  });

  factory UpstreamStatus.fromJson(Map<String, dynamic> json) => UpstreamStatus(
    id: json['id'] as String? ?? '',
    protocol: json['protocol'] as String? ?? '',
    server: json['server'] as String? ?? json['url'] as String? ?? '',
    active: json['active'] == true,
    averageLatencyMs: _asDouble(json['avgLatencyMs']),
  );

  final String id;
  final String protocol;
  final String server;
  final bool active;
  final double averageLatencyMs;
}

@immutable
class TakeoverStatus {
  const TakeoverStatus({required this.active, required this.adapterCount});

  factory TakeoverStatus.fromJson(Map<String, dynamic> json) => TakeoverStatus(
    active: json['active'] == true,
    adapterCount: (json['adapters'] as List?)?.length ?? 0,
  );

  final bool active;
  final int adapterCount;
}

@immutable
class MetricsStatus {
  const MetricsStatus({
    required this.totalQueries,
    required this.successQueries,
    required this.failedQueries,
    required this.averageLatencyMs,
    required this.qps,
  });

  factory MetricsStatus.fromJson(Map<String, dynamic> json) => MetricsStatus(
    totalQueries: _asInt(json['totalQueries']),
    successQueries: _asInt(json['successQueries']),
    failedQueries: _asInt(json['failedQueries']),
    averageLatencyMs: _asDouble(json['avgLatencyMs']),
    qps: _asDouble(json['qps']),
  );

  final int totalQueries;
  final int successQueries;
  final int failedQueries;
  final double averageLatencyMs;
  final double qps;
}

@immutable
class CacheStatus {
  const CacheStatus({
    required this.enabled,
    required this.hitRatio,
    required this.entryCount,
    required this.maxEntries,
  });

  factory CacheStatus.fromJson(Map<String, dynamic> json) => CacheStatus(
    enabled: json['enabled'] == true,
    hitRatio: _asDouble(json['hitRatio']),
    entryCount: _asInt(json['entryCount']),
    maxEntries: _asInt(json['maxEntries']),
  );

  final bool enabled;
  final double hitRatio;
  final int entryCount;
  final int maxEntries;
}

@immutable
class FilterStatus {
  const FilterStatus({
    required this.enabled,
    required this.totalRules,
    required this.activeLists,
    required this.blockedQueries,
    required this.blockRate,
    required this.paused,
  });

  factory FilterStatus.fromJson(Map<String, dynamic> json) => FilterStatus(
    enabled: json['enabled'] == true,
    totalRules: _asInt(json['totalRules']),
    activeLists: _asInt(json['activeLists']),
    blockedQueries: _asInt(json['blockedQueries']),
    blockRate: _asDouble(json['blockRate']),
    paused: json['paused'] == true,
  );

  final bool enabled;
  final int totalRules;
  final int activeLists;
  final int blockedQueries;
  final double blockRate;
  final bool paused;
}

@immutable
class CoreServiceStatus {
  const CoreServiceStatus({
    required this.installed,
    required this.running,
    required this.stateText,
    required this.canInstall,
    required this.message,
  });

  factory CoreServiceStatus.fromJson(Map<String, dynamic> json) =>
      CoreServiceStatus(
        installed: json['installed'] == true,
        running: json['running'] == true,
        stateText: json['stateText'] as String? ?? '状态未知',
        canInstall: json['canInstall'] == true,
        message: json['message'] as String? ?? '',
      );

  final bool installed;
  final bool running;
  final String stateText;
  final bool canInstall;
  final String message;
}

Map<String, dynamic> _asMap(Object? value) =>
    Map<String, dynamic>.from(value! as Map);
List<String> _asStrings(Object? value) => [
  for (final item in value as List? ?? const []) item.toString(),
];
int _asInt(Object? value) => value is num ? value.toInt() : 0;
double _asDouble(Object? value) => value is num ? value.toDouble() : 0;
