import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('运行中切换 IPv6 模式会通知全隧道通道并带上模式值', () async {
    final channel = MethodChannel(vpnChannelName);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await requestVpnIpv6ModeUpdate('auto');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'updateIpv6Mode');
    expect(calls.single.arguments, {'ipv6Mode': 'auto'});
  });

  test('原生通道不可用时静默忽略', () async {
    await requestVpnIpv6ModeUpdate('ipv4');
  });
}
