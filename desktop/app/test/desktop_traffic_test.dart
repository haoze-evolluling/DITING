// Desktop devices (desktop parity): the recognised clients on the dashboard, and the ACL and rate
// limit on the feature hub's client-access page. Every value comes from the service; each write
// re-reads the state it touched.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/data/api/desktop_traffic_models.dart';
import 'package:diting_desktop/pages/home/desktop_home_page.dart';
import 'package:diting_desktop/pages/hub/desktop_client_access_page.dart';
import 'package:diting_desktop/pages/hub/widgets/filter_common.dart';
import 'package:diting_desktop/pages/traffic/desktop_client_groups_page.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_access_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_list_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_groups_card.dart';
import 'package:diting_desktop/pages/traffic/widgets/client_rate_limit_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpTraffic(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
    bool accessPage = false,
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: DesktopApp(
          initialLocation: accessPage
              ? DesktopClientAccessPage.path
              : Routes.home,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) {
    final page = find.byType(DesktopClientAccessPage);
    return tester.element(
      page.evaluate().isEmpty ? find.byType(DesktopHomePage) : page,
    ).l10n;
  }

  Finder inClients(Finder matching) =>
      find.descendant(of: find.byType(DesktopClientListCard), matching: matching);
  Finder inAccess(Finder matching) =>
      find.descendant(of: find.byType(ClientAccessCard), matching: matching);
  Finder inRateLimit(Finder matching) => find.descendant(
    of: find.byType(ClientRateLimitCard),
    matching: matching,
  );

  Future<void> tapAt(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(
      tester.element(finder),
      alignment: 0.5,
      duration: Duration.zero,
    );
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> clearMessages(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  test('缺字段按零值解析，限流回落到服务默认值', () {
    final client = DesktopClient.fromJson(const {});
    expect(client.ip, isEmpty);
    expect(client.queryCount, 0);
    expect(client.lastSeen, 0);

    final limits = DesktopClientLimits.fromJson(const {});
    expect(limits.access.allowed, isEmpty);
    expect(limits.rateLimit.enabled, isFalse);
    expect(limits.rateLimit.rate, 0);

    const fallback = DesktopRateLimit.fallback;
    expect(fallback.rate, 50);
    expect(fallback.exemptIPs, contains('127.0.0.1'));
    expect(DesktopRateLimit.fromJson(fallback.toJson()).ipv6Prefix, 128);
  });

  testWidgets('设备列表显示名称、状态与最近活跃', (tester) async {
    await pumpTraffic(tester);
    final l10n = l10nOf(tester);

    expect(find.text('192.168.1.20'), findsOneWidget);
    expect(find.text('laptop.lan'), findsOneWidget);
    expect(find.text('192.168.1.21'), findsOneWidget);
    expect(find.text(l10n.desktopTrafficClientUnnamed), findsOneWidget);
    expect(find.text(l10n.desktopTrafficStateOpen), findsNWidgets(2));
    expect(
      find.text(l10n.desktopTrafficClientQueries(321)),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopTrafficClientNever), findsOneWidget);
    expect(
      find.text(
        l10n.desktopTrafficClientLastSeen(
          desktopMonthDayTime(
            DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
          ),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('别名弹窗提交新名称，留空则清除', (tester) async {
    final backend = await pumpTraffic(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inClients(find.text(l10n.desktopTrafficAlias)).first);
    final field = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '客厅电视');
    await tapAt(tester, find.text(l10n.desktopTrafficAliasSave));
    expect(backend.aliasUpdates.single, {'ip': '192.168.1.20', 'name': '客厅电视'});
    expect(find.text('客厅电视'), findsOneWidget);
    await clearMessages(tester);

    await tapAt(tester, inClients(find.text(l10n.desktopTrafficAlias)).first);
    await tester.enterText(field, '  ');
    await tapAt(tester, find.text(l10n.desktopTrafficAliasSave));
    expect(backend.aliasUpdates.last['name'], isEmpty);
    expect(
      find.text(l10n.desktopTrafficAliasCleared('192.168.1.20')),
      findsOneWidget,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('白名单与阻断互斥并提交整份名单', (tester) async {
    final backend = await pumpTraffic(
      tester,
      backend: FakeDesktopBackend(
        status: statusPayload(blockedClients: ['192.168.1.20']),
      ),
    );
    final l10n = l10nOf(tester);

    expect(
      find.descendant(
        of: find.byType(DashboardChip),
        matching: find.text(l10n.desktopTrafficStateBlocked),
      ),
      findsOneWidget,
    );
    await tapAt(
      tester,
      inClients(find.text(l10n.desktopTrafficAllowedAdd)).first,
    );
    final body = backend.accessUpdates.single;
    expect(body['allowedClients'], ['192.168.1.20']);
    expect(body['blockedClients'], isEmpty);
    expect(
      find.descendant(
        of: find.byType(DashboardChip),
        matching: find.text(l10n.desktopTrafficStateAllowed),
      ),
      findsOneWidget,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ACL 草稿按行去空行保存，撤销恢复服务端值', (tester) async {
    final backend = await pumpTraffic(tester, accessPage: true);
    final l10n = l10nOf(tester);

    final allowed = inAccess(find.byType(TextField)).first;
    await tester.enterText(allowed, ' 192.168.1.0/24 \n\n10.0.0.7\n');
    await tapAt(tester, inAccess(find.text(l10n.desktopTrafficAccessReset)));
    expect(
      tester.widget<TextField>(allowed).controller?.text,
      isEmpty,
    );

    await tester.enterText(allowed, ' 192.168.1.0/24 \n\n10.0.0.7\n');
    await tapAt(tester, inAccess(find.text(l10n.desktopTrafficAccessSave)));
    expect(backend.accessUpdates.single['allowedClients'], [
      '192.168.1.0/24',
      '10.0.0.7',
    ]);
    expect(find.text(l10n.desktopTrafficAccessSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('限流开关提交整份表单，非法数值不提交', (tester) async {
    final backend = await pumpTraffic(tester, accessPage: true);
    final l10n = l10nOf(tester);

    final rate = inRateLimit(find.byType(TextFormField)).first;
    await tester.enterText(rate, '0');
    await tapAt(
      tester,
      inRateLimit(find.text(l10n.desktopTrafficRateLimitSave)),
    );
    expect(backend.rateLimitUpdates, isEmpty);
    expect(find.text(l10n.desktopTrafficRateInvalid), findsOneWidget);

    await tester.enterText(rate, '80');
    await tapAt(tester, inRateLimit(find.byType(DashboardSwitch)));
    final body = backend.rateLimitUpdates.single;
    expect(body['enabled'], isTrue);
    expect(body['rate'], 80);
    expect(body['burst'], 100);
    expect(find.text(l10n.desktopTrafficRateLimitSavedOn), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = FakeDesktopBackend()..rejectWrites = true;
    await pumpTraffic(tester, backend: backend, accessPage: true);
    final l10n = l10nOf(tester);

    await tapAt(tester, inRateLimit(find.byType(DashboardSwitch)));
    expect(
      find.text(l10n.desktopTrafficSaveFailed('write rejected')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.desktopTrafficRateLimitOff),
      findsOneWidget,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设备页可进入客户端分组子页', (tester) async {
    await pumpTraffic(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inClients(find.byTooltip(l10n.desktopGroupsOpen)));
    expect(find.byType(DesktopClientGroupsPage), findsOneWidget);
    expect(find.byType(ClientGroupsCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpTraffic(tester, size: const Size(390, 844));
    expect(find.byType(DesktopClientListCard), findsOneWidget);
    // The dashboard offers no ACL; that page is its own single column.
    expect(find.byType(ClientAccessCard), findsNothing);
    expect(find.byType(ClientRateLimitCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('访问控制页窄窗单列且不横向溢出', (tester) async {
    await pumpTraffic(tester, size: const Size(390, 844), accessPage: true);
    expect(find.byType(ClientAccessCard), findsOneWidget);
    expect(find.byType(ClientRateLimitCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
