/// Dart side of `com.haoze.diting/diagnostics`: probe results arrive as plain maps. Panels bypass
/// the tunnel (this app's UID is in `addDisallowedApplication`) unless a `*ViaTunnel` flag
/// reproduces a per-tool escape hatch.
library;

import 'package:flutter/services.dart';

const diagnosticsChannelName = 'com.haoze.diting/diagnostics';

class PingReply {
  const PingReply({
    required this.sequence,
    this.elapsedMs,
    this.ttl,
    this.error,
  });

  final int sequence;
  final double? elapsedMs;
  final int? ttl;
  final String? error;

  bool get ok => elapsedMs != null;

  static PingReply fromMap(Map<Object?, Object?> map) => PingReply(
    sequence: (map['sequence'] as num?)?.toInt() ?? 0,
    elapsedMs: (map['elapsedMs'] as num?)?.toDouble(),
    ttl: (map['ttl'] as num?)?.toInt(),
    error: map['error'] as String?,
  );
}

class PingSummary {
  const PingSummary({
    required this.target,
    required this.transmitted,
    required this.received,
    required this.lossPercent,
    required this.success,
    this.resolvedAddress,
    this.addressFamily,
    this.minMs,
    this.avgMs,
    this.maxMs,
    this.jitterMs,
    this.message,
    this.measuredWithFallback = false,
    this.replies = const [],
  });

  final String target;
  final String? resolvedAddress;
  final String? addressFamily;
  final int transmitted;
  final int received;
  final double lossPercent;
  final double? minMs;
  final double? avgMs;
  final double? maxMs;
  final double? jitterMs;
  final List<PingReply> replies;
  final bool success;
  final String? message;

  /// True when the system `ping` binary was missing and the probe used `InetAddress.isReachable` or
  /// TCP timing, so the numbers measure a handshake, not ICMP.
  final bool measuredWithFallback;

  static PingSummary fromMap(Map<Object?, Object?> map) {
    final rawReplies = map['replies'];
    return PingSummary(
      target: map['target'] as String? ?? '',
      resolvedAddress: map['resolvedAddress'] as String?,
      addressFamily: map['addressFamily'] as String?,
      transmitted: (map['transmitted'] as num?)?.toInt() ?? 0,
      received: (map['received'] as num?)?.toInt() ?? 0,
      lossPercent: (map['lossPercent'] as num?)?.toDouble() ?? 100,
      minMs: (map['minMs'] as num?)?.toDouble(),
      avgMs: (map['avgMs'] as num?)?.toDouble(),
      maxMs: (map['maxMs'] as num?)?.toDouble(),
      jitterMs: (map['jitterMs'] as num?)?.toDouble(),
      replies: [
        if (rawReplies is List)
          for (final item in rawReplies)
            if (item is Map)
              PingReply.fromMap(Map<Object?, Object?>.from(item)),
      ],
      success: map['success'] == true,
      message: map['message'] as String?,
      measuredWithFallback: map['measuredWithFallback'] == true,
    );
  }
}

class TraceHop {
  const TraceHop({
    required this.hop,
    this.address,
    this.elapsedMs,
    this.reachedTarget = false,
  });

  final int hop;
  final String? address;
  final double? elapsedMs;
  final bool reachedTarget;

  bool get responded => address != null;

  static TraceHop fromMap(Map<Object?, Object?> map) => TraceHop(
    hop: (map['hop'] as num?)?.toInt() ?? 0,
    address: map['address'] as String?,
    elapsedMs: (map['elapsedMs'] as num?)?.toDouble(),
    reachedTarget: map['reachedTarget'] == true,
  );
}

class TraceResult {
  const TraceResult({
    required this.target,
    required this.hops,
    required this.success,
    this.resolvedAddress,
    this.message,
    this.cancelled = false,
  });

  final String target;
  final String? resolvedAddress;
  final List<TraceHop> hops;
  final bool success;
  final String? message;
  final bool cancelled;

  static TraceResult fromMap(Map<Object?, Object?> map) {
    final rawHops = map['hops'];
    return TraceResult(
      target: map['target'] as String? ?? '',
      resolvedAddress: map['resolvedAddress'] as String?,
      hops: [
        if (rawHops is List)
          for (final item in rawHops)
            if (item is Map) TraceHop.fromMap(Map<Object?, Object?>.from(item)),
      ],
      success: map['success'] == true,
      message: map['message'] as String?,
      cancelled: map['cancelled'] == true,
    );
  }
}

class DnsAnswer {
  const DnsAnswer({
    required this.recordType,
    required this.value,
    this.ttl = 0,
  });

  final String recordType;
  final String value;
  final int ttl;

  static DnsAnswer fromMap(Map<Object?, Object?> map) => DnsAnswer(
    recordType: map['type'] as String? ?? 'A',
    value: map['value'] as String? ?? '',
    ttl: (map['ttl'] as num?)?.toInt() ?? 0,
  );
}

/// Result of one manual DNS lookup. `source` is `upstream`, `rewrite`, `blocked`, `cache` or
/// `error`; only `upstream` means the query reached a resolver.
class DnsLookupResult {
  const DnsLookupResult({
    required this.domain,
    required this.source,
    required this.answers,
    required this.elapsedMs,
    this.error,
  });

  final String domain;
  final String source;
  final List<DnsAnswer> answers;
  final double elapsedMs;
  final String? error;

  bool get success => error == null && answers.isNotEmpty;

  static DnsLookupResult fromMap(Map<Object?, Object?> map) {
    final rawAnswers = map['answers'];
    return DnsLookupResult(
      domain: map['domain'] as String? ?? '',
      source: map['source'] as String? ?? 'error',
      answers: [
        if (rawAnswers is List)
          for (final item in rawAnswers)
            if (item is Map)
              DnsAnswer.fromMap(Map<Object?, Object?>.from(item)),
      ],
      elapsedMs: (map['elapsedMs'] as num?)?.toDouble() ?? 0,
      error: map['error'] as String?,
    );
  }
}

class NetworkInfoSnapshot {
  const NetworkInfoSnapshot({
    required this.interfaceName,
    required this.localIpv4,
    required this.privateDns,
    required this.vpnActive,
    this.localIpv6,
    this.dnsServers = const [],
    this.gateway,
  });

  final String interfaceName;
  final String localIpv4;
  final String? localIpv6;
  final List<String> dnsServers;
  final String? gateway;

  final bool vpnActive;

  final String privateDns;

  static NetworkInfoSnapshot fromMap(Map<Object?, Object?> map) {
    final rawServers = map['dnsServers'];
    return NetworkInfoSnapshot(
      interfaceName: map['interfaceName'] as String? ?? '',
      localIpv4: map['localIpv4'] as String? ?? '',
      localIpv6: map['localIpv6'] as String?,
      dnsServers: [
        if (rawServers is List)
          for (final item in rawServers)
            if (item is String) item,
      ],
      gateway: map['gateway'] as String?,
      vpnActive: map['vpnActive'] == true,
      privateDns: map['privateDns'] as String? ?? 'off',
    );
  }
}

abstract class DiagnosticsRunner {
  /// [count] is clamped to 1-20, [timeoutSeconds] applies per reply.
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  });

  /// [maxHops] is clamped to 1-30. Hops come back all at once: a traceroute finishes in seconds on
  /// mobile.
  Future<TraceResult> traceRoute(String target, {int maxHops = 30});

  /// Resolves through the tunnel's decision path when [viaTunnel], otherwise asks [server] over
  /// UDP; a null or empty [server] means the device resolver, which [viaTunnel] ignores.
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  });

  Future<NetworkInfoSnapshot> networkInfo();
}

class MethodChannelDiagnosticsRunner implements DiagnosticsRunner {
  MethodChannelDiagnosticsRunner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(diagnosticsChannelName);

  final MethodChannel _channel;

  @override
  Future<PingSummary> ping(
    String target, {
    int count = 4,
    int timeoutSeconds = 3,
  }) async {
    final raw = await _channel.invokeMethod<Object?>('ping', {
      'target': target,
      'count': count,
      'timeoutSeconds': timeoutSeconds,
    });
    return PingSummary.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<TraceResult> traceRoute(String target, {int maxHops = 30}) async {
    final raw = await _channel.invokeMethod<Object?>('traceRoute', {
      'target': target,
      'maxHops': maxHops,
    });
    return TraceResult.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<DnsLookupResult> lookupDns(
    String domain, {
    bool viaTunnel = false,
    bool ipv4 = true,
    String? server,
  }) async {
    final raw = await _channel.invokeMethod<Object?>('lookupDns', {
      'domain': domain,
      'viaTunnel': viaTunnel,
      'ipv4': ipv4,
      // Empty string and null both mean "system" natively; pass it explicitly so "absent" is never
      // a separate case.
      'server': server ?? '',
    });
    return DnsLookupResult.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }

  @override
  Future<NetworkInfoSnapshot> networkInfo() async {
    final raw = await _channel.invokeMethod<Object?>('networkInfo');
    return NetworkInfoSnapshot.fromMap(
      raw is Map ? Map<Object?, Object?>.from(raw) : const {},
    );
  }
}
