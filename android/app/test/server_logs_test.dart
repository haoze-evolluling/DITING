// Server-mode log dashboard: a third shell tab, sharing the normal/express card language while
// omitting traffic bytes and HTTPS inspection that do not exist without a VPN tunnel.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/pages/server/server_logs_page.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_dns_server_controller.dart';
import 'support/test_hooks.dart';

void main() {
  installGlobalTestHooks();
  group('服务器模式日志仪表盘', _serverLogs);
}

void _serverLogs() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpServerApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore({
              'diting_settings': {'app_work_mode': 'dns'},
              'diting_dns_mode_prefs': <String, Object?>{},
            }),
          ),
          dnsServerControllerProvider.overrideWithValue(
            FakeDnsServerController(),
          ),
        ],
        child: const DitingApp(),
      ),
    );
    await tester.pump();
    await settle(tester);
  }

  testWidgets('日志仪表盘 tab 打开服务器专用日志页', (tester) async {
    await pumpServerApp(tester);
    await tester.tap(find.text('日志仪表盘').last);
    await settle(tester);

    expect(find.byType(ServerLogsPage), findsOneWidget);
    expect(find.text('服务器日志仪表盘'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
  });

  testWidgets('服务器日志仪表盘不展示流量数据段', (tester) async {
    await pumpServerApp(tester);
    await tester.tap(find.text('日志仪表盘').last);
    await settle(tester);

    // 统计卡只保留请求计数；服务器模式没有上下行流量，不能展示三个 0 B 的数据段。
    expect(find.text('数据使用'), findsNothing);
    expect(find.text('请求'), findsOneWidget);
  });
}
