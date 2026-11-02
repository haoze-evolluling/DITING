/// Dart side of `com.haoze.diting/dns_latency`, matching Kotlin `DnsLatencyBridge.kt`. `probe`
/// takes `{providers, domain, attempts}` and returns per-provider results. Failure is
/// `success=false` plus `message`, never an exception; `MissingPluginException` means no channel.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:flutter/services.dart';

const dnsLatencyChannelName = 'com.haoze.diting/dns_latency';

enum DnsLatencyProtocol {
  dns('dns', 'DNS'),
  doh('doh', 'DoH'),
  dot('dot', 'DoT');

  const DnsLatencyProtocol(this.wireValue, this.label);

  final String wireValue;
  final String label;

  static DnsLatencyProtocol? fromWire(String? value) {
    final normalized = value?.toLowerCase();
    for (final protocol in values) {
      if (protocol.wireValue == normalized) return protocol;
    }
    return null;
  }
}

/// One provider to probe. The native side has no catalog, so host, port and protocol all come from
/// Dart.
class DnsLatencyProviderSpec {
  const DnsLatencyProviderSpec({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.protocol,
    this.url = '',
  });

  final String id;
  final String name;

  /// Hostname or IP; for DoH, the host parsed out of [url] (may be empty).
  final String host;

  final int port;

  final DnsLatencyProtocol protocol;

  final String url;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'protocol': protocol.wireValue,
    'url': url,
  };
}

class DnsLatencySample {
  const DnsLatencySample({
    required this.providerId,
    required this.providerName,
    required this.protocol,
    required this.elapsedMs,
    required this.success,
    required this.attempts,
    required this.successCount,
    this.samplesMs = const [],
    this.message,
  });

  final String providerId;
  final String providerName;
  final DnsLatencyProtocol protocol;

  /// Average of successful samples; on failure, the elapsed time at failure.
  final int elapsedMs;

  final bool success;

  final String? message;

  final int attempts;

  final int successCount;

  final List<int> samplesMs;

  String get successRateLabel =>
      currentL10n.dnsLatencySuccessRate(successCount, attempts);

  static DnsLatencySample fromMap(Map<Object?, Object?> map) {
    final rawSamples = map['elapsedSamplesMs'];
    final attempts = (map['attempts'] as num?)?.toInt() ?? 1;
    final success = map['success'] == true;
    final successCount =
        (map['successCount'] as num?)?.toInt() ?? (success ? 1 : 0);
    return DnsLatencySample(
      providerId: map['providerId'] as String? ?? '',
      providerName: map['providerName'] as String? ?? '',
      protocol:
          DnsLatencyProtocol.fromWire(map['protocol'] as String?) ??
          DnsLatencyProtocol.dns,
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      success: success,
      message: map['message'] as String?,
      attempts: attempts < 1 ? 1 : attempts,
      successCount: successCount,
      samplesMs: [
        if (rawSamples is List)
          for (final item in rawSamples)
            if (item is num) item.toInt(),
      ],
    );
  }
}

/// The host has no latency channel, which is not the same as every probe failing.
class DnsLatencyUnavailable implements Exception {
  const DnsLatencyUnavailable([this.message]);

  final String? message;

  @override
  String toString() => message ?? currentL10n.dnsLatencyUnsupported;
}

abstract class DnsLatencyRunner {
  /// Probes an empty provider list: native rejects it with `result.error`, which proves the channel
  /// exists. Never probe an unknown method name, since `notImplemented()` also looks like
  /// MissingPluginException.
  Future<bool> checkAvailable();

  Future<List<DnsLatencySample>> probe({
    required List<DnsLatencyProviderSpec> providers,
    required String domain,
    int attempts = 3,
  });
}

class MethodChannelDnsLatencyRunner implements DnsLatencyRunner {
  MethodChannelDnsLatencyRunner({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(dnsLatencyChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> checkAvailable() async {
    try {
      await _channel.invokeMethod<Object?>('probe', {
        'providers': const <Object?>[],
        'domain': '',
        'attempts': 1,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      // Channel exists; it just rejected the empty provider list.
      return true;
    }
  }

  @override
  Future<List<DnsLatencySample>> probe({
    required List<DnsLatencyProviderSpec> providers,
    required String domain,
    int attempts = 3,
  }) async {
    final safeAttempts = attempts.clamp(1, 10);
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('probe', {
        'providers': [for (final provider in providers) provider.toMap()],
        'domain': domain,
        'attempts': safeAttempts,
      });
    } on MissingPluginException {
      throw const DnsLatencyUnavailable();
    } on PlatformException catch (error) {
      final detail = error.message;
      throw DnsLatencyUnavailable(
        detail == null || detail.isEmpty
            ? currentL10n.dnsLatencyChannelFailedCode(error.code)
            : currentL10n.dnsLatencyChannelFailedDetail(detail),
      );
    }
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          DnsLatencySample.fromMap(Map<Object?, Object?>.from(item)),
    ];
  }
}

class UnavailableDnsLatencyRunner implements DnsLatencyRunner {
  const UnavailableDnsLatencyRunner();

  @override
  Future<bool> checkAvailable() async => false;

  @override
  Future<List<DnsLatencySample>> probe({
    required List<DnsLatencyProviderSpec> providers,
    required String domain,
    int attempts = 3,
  }) async => throw const DnsLatencyUnavailable();
}
