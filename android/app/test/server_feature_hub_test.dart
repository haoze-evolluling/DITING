// Server mode's feature center: it groups the module entries, hosts the upstream editor and mode
// settings (which no longer have dock tabs), and the config import/export entry opens the shared
// transfer page.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/app/app.dart';
import 'package:diting_android/pages/hub/config_transfer_page.dart';
import 'package:diting_android/pages/server/server_feature_hub_page.dart';
import 'package:diting_android/pages/server/server_mode_shell.dart';
import 'package:diting_android/pages/server/server_settings_page.dart';
import 'package:diting_android/pages/server/server_upstream_page.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/routes/server_routes.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/ui/ui.dart' show NavigationDock;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_dns_server_controller.dart';
import 'support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  group('服务器模式功能中心', _featureCenter);
}

void _featureCenter() {
  test('功能中心集中了各功能模块，并包含配置导入导出与上游/设置入口', () {
    final l10n = lookupAppL10n(const Locale('zh'));
    final categories = serverFeatureCategories(l10n);
    final cards = [for (final category in categories) ...category.cards];
    final routes = cards.map((card) => card.route);

    expect(
      categories.map((category) => category.title),
      containsAll(['DNS 服务', '策略与规则', '数据与维护', '界面与设置']),
    );
    // 上游与设置不再占用底栏 tab，而是作为功能中心里的路由入口。
    expect(
      routes,
      containsAll([
        ServerPaths.upstream,
        ServerPaths.settings,
        HubPaths.configTransfer,
      ]),
    );
  });

  /// Pumps a few frames without waiting for every animation to stop.
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

  Future<void> openFeatureCenter(WidgetTester tester) async {
    await pumpServerApp(tester);
    // Server mode has three tabs: overview, feature center and the server log dashboard.
    expect(find.byType(ServerModeShell), findsOneWidget);
    await tester.tap(find.text('功能中心').last);
    await settle(tester);
    expect(find.byType(ServerFeatureHubPage), findsOneWidget);
  }

  testWidgets('服务器外壳有首页、功能中心与日志仪表盘三个 tab', (tester) async {
    await openFeatureCenter(tester);
    final dock = tester.widget<NavigationDock>(find.byType(NavigationDock));
    expect(dock.destinations.map((destination) => destination.label), [
      '首页',
      '功能中心',
      '日志仪表盘',
    ]);
  });

  testWidgets('功能中心展示配置导入导出卡片', (tester) async {
    await openFeatureCenter(tester);
    expect(find.text('备份与迁移'), findsOneWidget);
  });

  testWidgets('功能中心的备份与迁移打开配置导入导出页', (tester) async {
    await openFeatureCenter(tester);
    await tester.tap(find.text('备份与迁移'));
    await settle(tester);

    expect(find.byType(ConfigTransferPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);

    // The import/export rows sit below the fold; scroll them into view to prove they exist.
    final scrollable = find
        .descendant(
          of: find.byType(ConfigTransferPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('导出应用配置 (JSON)'),
      400,
      scrollable: scrollable,
    );
    expect(find.text('导出应用配置 (JSON)'), findsOneWidget);
    expect(find.text('导入应用配置 (JSON)'), findsOneWidget);
  });

  testWidgets('功能中心的上游服务器入口打开上游页面', (tester) async {
    await openFeatureCenter(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ServerFeatureHubPage),
        matching: find.text('上游服务器'),
      ),
    );
    await settle(tester);

    expect(find.byType(ServerUpstreamPage), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('功能中心的模式设置入口打开设置页面', (tester) async {
    await openFeatureCenter(tester);
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
    expect(find.byType(BackButton), findsOneWidget);
  });
}
