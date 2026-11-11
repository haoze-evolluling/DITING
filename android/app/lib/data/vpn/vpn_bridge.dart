/// Dart side of `com.haoze.diting/vpn`. Dart decides policy, the platform side applies it; abstract
/// so state tests need no device.
library;

import 'package:flutter/services.dart';

const vpnChannelName = 'com.haoze.diting/vpn';
const expressVpnChannelName = 'com.haoze.diting/express_vpn';

class VpnStartRequest {
  const VpnStartRequest({
    required this.dnsConfig,
    this.outboundProxy = '',
    this.proxyAppPackage = '',
    this.bypassLan = true,
    this.ipv6Mode = 'auto',
    this.excludedPackages = const [],
    this.blockedPackages = const [],
    this.inspectionPackages = const [],
    this.inspectionEnabled = false,
  });

  final String dnsConfig;
  final String outboundProxy;

  /// App that owns the loopback proxy port. Excluded from the TUN: Android lets only one app
  /// bind that port, so its upstream sockets must not be captured or they loop back into it.
  final String proxyAppPackage;
  final bool bypassLan;
  final String ipv6Mode;

  /// `excluded_app_packages`: bypass the TUN via `addDisallowedApplication`.
  final List<String> excludedPackages;

  /// `blocked_app_packages`: resolved to UIDs for `Engine.setBlockedUIDs`.
  final List<String> blockedPackages;

  /// `http_inspection_app_packages`: resolved to UIDs for `Engine.setMitmAllowedUIDs`.
  final List<String> inspectionPackages;

  /// `http_inspection_enabled` AND `https_inspection_ready`: without the CA in the user trust
  /// store, MITM would break every HTTPS request.
  final bool inspectionEnabled;
}

class VpnStartResult {
  const VpnStartResult({
    required this.started,
    required this.needsPermission,
    this.error,
  });

  final bool started;
  final bool needsPermission;
  final String? error;

  factory VpnStartResult.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    return VpnStartResult(
      started: map['started'] == true,
      needsPermission: map['needsPermission'] == true,
      error: map['error'] as String?,
    );
  }
}

class VpnStatus {
  const VpnStatus({
    required this.running,
    required this.persisted,
    this.reclaiming = false,
    this.error,
    this.startedAt,
    this.stats = const {},
  });

  final bool running;
  final bool persisted;

  /// Another VPN took the slot and the service waits to reconnect; [running] is false meanwhile.
  final bool reclaiming;
  final String? error;

  /// When the service actually came up, reported by the native side. Null while stopped or on a
  /// build that does not report it.
  final DateTime? startedAt;

  /// Engine counters; empty when the tunnel has not started.
  final Map<String, Object?> stats;

  factory VpnStatus.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    final stats = map['stats'];
    return VpnStatus(
      running: map['running'] == true,
      persisted: map['persisted'] == true,
      reclaiming: map['reclaiming'] == true,
      error: map['error'] as String?,
      startedAt: epochMillis(map['startedAt']),
      stats: stats is Map ? Map<String, Object?>.from(stats) : const {},
    );
  }
}

/// Converts a native epoch-millis field to a `DateTime`; missing or non-positive means "unknown".
DateTime? epochMillis(Object? raw) {
  final millis = raw is num ? raw.toInt() : 0;
  return millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
}

/// One traffic sample in bytes per second. [unsupported] means no counters at all, which differs
/// from an idle 0 B/s.
class VpnTrafficRates {
  const VpnTrafficRates({
    required this.running,
    required this.txBps,
    required this.rxBps,
    this.unsupported = false,
  });

  const VpnTrafficRates.idle()
    : running = false,
      txBps = 0,
      rxBps = 0,
      unsupported = false;

  final bool running;
  final double txBps;
  final double rxBps;
  final bool unsupported;

  factory VpnTrafficRates.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    double read(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return VpnTrafficRates(
      running: map['running'] == true,
      txBps: read('txBps'),
      rxBps: read('rxBps'),
      unsupported: map['unsupported'] == true,
    );
  }
}

abstract class VpnController {
  void Function(bool granted)? onPrepareResult;

  /// True when the app already holds VPN permission; otherwise opens the system dialog and returns
  /// false.
  Future<bool> prepare();

  Future<VpnStartResult> start(VpnStartRequest request);

  Future<void> stop();

  Future<VpnStatus> status();

  /// Live up/down rates, polled at 1 Hz. A missing channel returns idle rates.
  Future<VpnTrafficRates> trafficRates();

  /// Hot-applies [dnsConfig] to the running engine; null on success, otherwise the reason.
  Future<String?> applyDnsConfig(String dnsConfig);
}

class MethodChannelVpnController implements VpnController {
  MethodChannelVpnController({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(vpnChannelName);

  final MethodChannel _channel;
  bool _handlerInstalled = false;

  @override
  void Function(bool granted)? onPrepareResult;

  /// Installing the handler needs an initialized binding, so it waits for the first platform call
  /// (provider tests build this without one).
  void _ensureHandler() {
    if (_handlerInstalled) return;
    _channel.setMethodCallHandler(_handleCall);
    _handlerInstalled = true;
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'onPrepareResult') {
      onPrepareResult?.call(call.arguments == true);
    }
    return null;
  }

  @override
  Future<bool> prepare() async {
    _ensureHandler();
    return await _channel.invokeMethod<bool>('prepare') ?? false;
  }

  @override
  Future<VpnStartResult> start(VpnStartRequest request) async {
    _ensureHandler();
    final result = await _channel.invokeMethod<Object?>('start', {
      'dnsConfig': request.dnsConfig,
      'outboundProxy': request.outboundProxy,
      'proxyAppPackage': request.proxyAppPackage,
      'bypassLan': request.bypassLan,
      'ipv6Mode': request.ipv6Mode,
      'excludedPackages': request.excludedPackages,
      'blockedPackages': request.blockedPackages,
      'inspectionPackages': request.inspectionPackages,
      'inspectionEnabled': request.inspectionEnabled,
    });
    return VpnStartResult.fromMap(result);
  }

  @override
  Future<void> stop() {
    _ensureHandler();
    return _channel.invokeMethod<void>('stop');
  }

  @override
  Future<VpnStatus> status() async {
    _ensureHandler();
    return VpnStatus.fromMap(await _channel.invokeMethod<Object?>('status'));
  }

  @override
  Future<String?> applyDnsConfig(String dnsConfig) async {
    _ensureHandler();
    try {
      return await _channel.invokeMethod<String>('applyDnsConfig', {
        'dnsConfig': dnsConfig,
      });
    } on MissingPluginException {
      return '当前平台不支持';
    } on PlatformException catch (error) {
      return error.message ?? error.code;
    }
  }

  @override
  Future<VpnTrafficRates> trafficRates() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('trafficRates');
      return VpnTrafficRates.fromMap(raw);
    } on MissingPluginException {
      // No native implementation (desktop host, tests): not 0 B/s and not an error.
      return const VpnTrafficRates(
        running: false,
        txBps: 0,
        rxBps: 0,
        unsupported: true,
      );
    } on PlatformException {
      return const VpnTrafficRates.idle();
    }
  }
}
