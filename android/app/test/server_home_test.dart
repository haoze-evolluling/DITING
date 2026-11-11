// Server-mode home dashboard: it mirrors the normal/express board with server widgets, and the
// mode settings page no longer repeats the feature-center module entries.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/pages/hub/cache_settings_page.dart';
import 'package:diting_android/pages/home/dashboard/dashboard_board.dart'
    show DashboardRemoveBadge;
import 'package:diting_android/pages/server/server_feature_hub_page.dart';
import 'package:diting_android/pages/server/server_home_page.dart';
import 'package:diting_android/pages/server/server_settings_page.dart';
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
  group('服务器模式首页仪表盘', _home);
}

void _home() {
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

  testWidgets('首页以仪表盘小组件展示服务信息与功能入口', (tester) async {
    await pumpServerApp(tester);
    expect(find.byType(ServerHomePage), findsOneWidget);
    expect(find.text('服务状态'), findsOneWidget);
    expect(find.text('当前上游'), findsOneWidget);
    expect(find.text('局域网接入'), findsOneWidget);
    expect(find.text('缓存设置'), findsOneWidget);
    expect(find.text('规则控制'), findsOneWidget);
    expect(find.text('域名规则'), findsOneWidget);
    // 小组件与普通模式一致，可进入编辑模式并移除卡片。
    await tester.tap(find.byTooltip('编辑仪表盘'));
    await settle(tester);
    final badgesBefore = tester
        .widgetList(find.byType(DashboardRemoveBadge))
        .length;
    expect(badgesBefore, greaterThan(0));
    await tester.tap(find.byType(DashboardRemoveBadge).first);
    await settle(tester);
    expect(
      tester.widgetList(find.byType(DashboardRemoveBadge)).length,
      badgesBefore - 1,
    );
  });

  testWidgets('首页缓存小组件打开缓存设置页', (tester) async {
    await pumpServerApp(tester);
    await tester.ensureVisible(find.text('缓存设置'));
    await settle(tester);
    await tester.tap(find.text('缓存设置'));
    await settle(tester);
    expect(find.byType(CacheSettingsPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('模式设置页不再重复功能中心的模块入口', (tester) async {
    await pumpServerApp(tester);
    await tester.tap(find.text('功能中心').last);
    await settle(tester);
    final settingsCard = find.descendant(
      of: find.byType(ServerFeatureHubPage),
      matching: find.text('模式设置'),
    );
    await tester.scrollUntilVisible(
      settingsCard,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ServerFeatureHubPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(settingsCard);
    await settle(tester);
    expect(find.byType(ServerSettingsPage), findsOneWidget);
    // 设置页只保留真正的运行时设置与操作。
    expect(find.text('本地监听端口'), findsOneWidget);
    expect(find.text('忽略电池优化'), findsOneWidget);
    expect(find.text('重新选择工作模式'), findsOneWidget);
    // 模块入口已统一收口到功能中心，不再在设置页重复。
    expect(find.text('缓存设置'), findsNothing);
    expect(find.text('规则控制'), findsNothing);
    expect(find.text('黑名单'), findsNothing);
    expect(find.text('白名单'), findsNothing);
    expect(find.text('Hosts 覆写'), findsNothing);
  });
}
