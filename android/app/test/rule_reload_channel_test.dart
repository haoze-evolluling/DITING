// A rule edit must reach whichever data plane is running: normal tunnel, express tunnel or the
// standalone DNS server. `requestVpnRuleReload` fans out to all three channels and each native side
// no-ops when its mode is stopped, so this pins the wiring (a missing channel would silently drop
// server-mode hot reload).

import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('规则变更会同时通知普通/极速/服务器三个通道重载', () async {
    final calls = <String, List<String>>{};
    const channels = [
      vpnChannelName,
      expressVpnChannelName,
      dnsServerChannelName,
    ];

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
