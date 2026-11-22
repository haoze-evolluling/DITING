library;

import 'package:flutter/services.dart';

const vpnChannelName = 'com.haoze.diting/vpn';
const expressVpnChannelName = 'com.haoze.diting/express_vpn';

const dataPlaneChannelNames = [
  vpnChannelName,
  expressVpnChannelName,
  'com.haoze.diting/root_dns',
];

Future<void> requestVpnRuleReload() async {
  for (final name in dataPlaneChannelNames) {
    try {
      await MethodChannel(name).invokeMethod<bool>('reloadRules');
    } catch (_) {
    }
  }
}

class VpnStartRequest {
  const VpnStartRequest({
    required this.dnsConfig,
    this.outboundProxy = '',
    this.proxyAppPackage = '',
    this.bypassLan = true,
    this.tunnelIpv6 = false,
    this.dnsAaaa = false,
    this.routeAddress = const [],
    this.routeExcludeAddress = const [],
    this.excludedPackages = const [],
    this.blockedPackages = const [],
    this.inspectionPackages = const [],
    this.inspectionEnabled = false,
  });

  final String dnsConfig;
  final String outboundProxy;

  final String proxyAppPackage;
  final bool bypassLan;
  final bool tunnelIpv6;
  final bool dnsAaaa;
  final List<String> routeAddress;
  final List<String> routeExcludeAddress;

  final List<String> excludedPackages;

  final List<String> blockedPackages;

  final List<String> inspectionPackages;

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
    this.starting = false,
    this.reclaiming = false,
    this.error,
    this.startedAt,
    this.stats = const {},
  });

  final bool running;
  final bool persisted;

  final bool starting;

  final bool reclaiming;
  final String? error;

  final DateTime? startedAt;

  final Map<String, Object?> stats;

  factory VpnStatus.fromMap(Object? raw) {
    final map = raw is Map ? raw : const {};
    final stats = map['stats'];
    return VpnStatus(
      running: map['running'] == true,
      persisted: map['persisted'] == true,
      starting: map['starting'] == true,
      reclaiming: map['reclaiming'] == true,
      error: map['error'] as String?,
      startedAt: epochMillis(map['startedAt']),
      stats: stats is Map ? Map<String, Object?>.from(stats) : const {},
    );
  }
}

DateTime? epochMillis(Object? raw) {
  final millis = raw is num ? raw.toInt() : 0;
  return millis > 0 ? DateTime.fromMillisecondsSinceEpoch(millis) : null;
}

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

  Future<bool> prepare();

  Future<VpnStartResult> start(VpnStartRequest request);

  Future<void> stop();

  Future<VpnStatus> status();

  Future<VpnTrafficRates> trafficRates();

  Future<String?> applyDnsConfig(String dnsConfig);
}

class MethodChannelVpnController implements VpnController {
  MethodChannelVpnController({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(vpnChannelName);

  final MethodChannel _channel;
  bool _handlerInstalled = false;

  @override
  void Function(bool granted)? onPrepareResult;

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
      'tunnelIpv6': request.tunnelIpv6,
      'dnsAaaa': request.dnsAaaa,
      'routeAddress': request.routeAddress,
      'routeExcludeAddress': request.routeExcludeAddress,
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
