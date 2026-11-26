import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/data/prefs/legacy_prefs_store.dart';
import 'package:diting_android/data/prefs/legacy_settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_vpn_controller.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, String workMode) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final vpn = FakeVpnController()
      ..statusValue = const VpnStatus(running: false, persisted: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          vpnControllerProvider.overrideWithValue(vpn),
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore({
              'diting_settings': {'app_work_mode': workMode},
            }),
          ),
        ],
        child: const DitingApp(initialLocation: HubPaths.ruleControl),
      ),
    );
    await tester.pump();
    await settle(tester);
  }

  testWidgets('普通模式保留 URL 规则与内容过滤入口', (tester) async {
    await pump(tester, AppWorkMode.normal.storageValue);
    expect(find.text('启用域名规则'), findsOneWidget);
    expect(find.text('URL 规则与内容过滤'), findsOneWidget);
  });

  testWidgets('规则控制页按子类拆分拦截策略并包含场景自动化入口', (tester) async {
    await pump(tester, AppWorkMode.normal.storageValue);
    expect(find.text('规则测试'), findsOneWidget);
    expect(find.text('临时暂停'), findsOneWidget);
    expect(find.text('命中排行'), findsOneWidget);
    expect(find.text('拦截响应'), findsOneWidget);
    expect(find.text('域名黑名单'), findsOneWidget);
    expect(find.text('域名白名单'), findsOneWidget);
    expect(find.text('域名覆写'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('场景自动化'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('场景自动化'), findsOneWidget);
    expect(find.text('规则订阅'), findsNothing);
    expect(find.text('隐私套件'), findsNothing);
  });

  testWidgets('简洁模式保留域名规则，但隐藏依赖全隧道的 URL 规则入口', (tester) async {
    await pump(tester, AppWorkMode.express.storageValue);
    expect(find.text('启用域名规则'), findsOneWidget);
    expect(find.text('URL 规则与内容过滤'), findsNothing);
  });
}
