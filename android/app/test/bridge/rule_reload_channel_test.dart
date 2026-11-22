import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('规则变更会同时通知普通/极速两个通道重载', () async {
    final calls = <String, List<String>>{};
    const channels = [vpnChannelName, expressVpnChannelName];

    for (final name in channels) {
      final channel = MethodChannel(name);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.putIfAbsent(name, () => []).add(call.method);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    }

    await requestVpnRuleReload();

    for (final name in channels) {
      expect(calls[name], ['reloadRules'], reason: name);
    }
  });
}
