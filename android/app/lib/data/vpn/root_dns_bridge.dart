library;

import 'package:flutter/services.dart';

import 'vpn_bridge.dart';

const rootDnsChannelName = 'com.haoze.diting/root_dns';

class RootDnsProbe {
  const RootDnsProbe({required this.available, this.message = ''});

  const RootDnsProbe.unavailable([this.message = '']) : available = false;

  final bool available;

  final String message;

  factory RootDnsProbe.fromMap(Object? raw) {
    final map = raw is Map ? Map<Object?, Object?>.from(raw) : const {};
    final message = map['message'];
    return RootDnsProbe(
      available: map['available'] == true,
      message: message is String ? message : '',
    );
  }
}

Future<RootDnsProbe> probeRootDns() async {
  try {
    final raw = await MethodChannel(rootDnsChannelName)
        .invokeMethod<Object?>('probeRoot');
    return RootDnsProbe.fromMap(raw);
  } on MissingPluginException {
    return const RootDnsProbe.unavailable('当前平台不支持');
  } on PlatformException catch (error) {
    return RootDnsProbe.unavailable(error.message ?? error.code);
  }
}

class MethodChannelRootDnsController implements VpnController {
  MethodChannelRootDnsController({MethodChannel? channel})
    : _channel = channel ?? MethodChannel(rootDnsChannelName);

  final MethodChannel _channel;

  @override
  void Function(bool granted)? onPrepareResult;

  @override
  Future<bool> prepare() async => true;

  @override
  Future<VpnStartResult> start(VpnStartRequest request) async {
    final result = await _channel.invokeMethod<Object?>('start', {
      'dnsConfig': request.dnsConfig,
    });
    return VpnStartResult.fromMap(result);
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  Future<VpnStatus> status() async {
    return VpnStatus.fromMap(await _channel.invokeMethod<Object?>('status'));
  }

  @override
  Future<String?> applyDnsConfig(String dnsConfig) async {
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
