library;

import 'package:diting_android/data/vpn/vpn_bridge.dart' show epochMillis;
import 'package:flutter/services.dart';

const dnsServerChannelName = 'com.haoze.diting/dns_server';

class DnsServerStartRequest {
  const DnsServerStartRequest({
    required this.port,
    required this.dnsConfig,
    required this.adBlockEnabled,
  });

  final int port;
  final String dnsConfig;
  final bool adBlockEnabled;
}

class DnsServerStartResult {
  const DnsServerStartResult({required this.started, this.error});

  final bool started;
  final String? error;

  factory DnsServerStartResult.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    return DnsServerStartResult(
      started: map['started'] == true,
      error: map['error'] as String?,
    );
  }
}

class DnsServerStatus {
  const DnsServerStatus({
    required this.running,
    required this.persisted,
    required this.port,
    this.error,
    this.startedAt,
    this.stats = const {},
  });

  final bool running;
  final bool persisted;
  final int port;
  final String? error;

  /// When the service actually came up, reported by the native side. Null while stopped.
  final DateTime? startedAt;

  final Map<String, Object?> stats;

  factory DnsServerStatus.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    final stats = map['stats'];
    return DnsServerStatus(
      running: map['running'] == true,
      persisted: map['persisted'] == true,
      port: map['port'] is int ? map['port'] as int : 1053,
      error: map['error'] as String?,
      startedAt: epochMillis(map['startedAt']),
      stats: stats is Map ? Map<String, Object?>.from(stats) : const {},
    );
  }
}

abstract class DnsServerController {
  Future<DnsServerStartResult> start(DnsServerStartRequest request);

  Future<void> stop();

  Future<DnsServerStatus> status();
}

class MethodChannelDnsServerController implements DnsServerController {
  MethodChannelDnsServerController({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(dnsServerChannelName);

  final MethodChannel _channel;

  @override
  Future<DnsServerStartResult> start(DnsServerStartRequest request) async {
    final result = await _channel.invokeMethod<Object?>('start', {
      'port': request.port,
      'dnsConfig': request.dnsConfig,
      'adBlockEnabled': request.adBlockEnabled,
    });
    return DnsServerStartResult.fromMap(result);
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<DnsServerStatus> status() async =>
      DnsServerStatus.fromMap(await _channel.invokeMethod<Object?>('status'));
}
