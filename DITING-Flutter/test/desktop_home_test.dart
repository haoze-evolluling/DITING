// Desktop home dashboard (docs/development/flutter-desktop-ui.md step 3–4): FlClash's board over
// the local service API. The figures must come from the snapshot, and every state that is not a
// live snapshot must say so.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/pages/home/desktop_format.dart';
import 'package:diting/desktop/pages/home/desktop_home_page.dart';
import 'package:diting/desktop/pages/home/widgets/dashboard_tiles.dart';
import 'package:diting/desktop/pages/home/widgets/recent_queries_card.dart';
import 'package:diting/desktop/pages/home/widgets/desktop_power_button.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpHome(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 800),
    Map<String, Map<String, Object?>>? seed,
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore(seed),
          ),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopHomePage)).l10n;

  testWidgets('宽屏按上游桌面网格铺开全部卡片', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopHomePage), findsOneWidget);
    // Two summary cards, two switches plus the host service, four cards.
    for (final title in [
      l10n.desktopDnsServiceTitle,
      l10n.desktopQueriesTitle,
      l10n.desktopTakeoverTitle,
      l10n.desktopFilterPauseTitle,
      l10n.desktopServiceHostTitle,
      l10n.desktopCacheTitle,
      l10n.desktopFilterTitle,
      l10n.desktopPerformanceTitle,
      l10n.desktopRuntimeTitle,
    ]) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    expect(find.byType(DashboardCard), findsNWidgets(10));
    expect(find.byType(RecentQueriesCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('卡片显示服务返回的数字，而不是占位', (tester) async {
    await pumpHome(tester);
    final l10n = l10nOf(tester);

    // Version, uptime and query counts come straight from the payload.
    expect(find.text('2.2.9'), findsOneWidget);
    expect(find.text('4242'), findsOneWidget);
    expect(
      find.text(desktopUptime(const Duration(seconds: 90061))),
      findsWidgets,
    );
    expect(find.text('12,345'), findsWidgets);
    expect(find.text('67%'), findsOneWidget);
    // The query list comes from its own endpoint, newest first.
    expect(find.text('example1.com'), findsOneWidget);
    expect(find.text('laptop'), findsOneWidget);
    expect(find.text('8.0%'), findsOneWidget);
    expect(find.text('127.0.0.1:5353'), findsOneWidget);
    expect(find.text(l10n.stateRunning), findsWidgets);
  });

  testWidgets('连不上服务时说明试过的地址，并可重试', (tester) async {
    final backend = FakeDesktopBackend(failAfter: 0);
    await pumpHome(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopBackendOfflineTitle), findsOneWidget);
    expect(
      find.text(l10n.desktopBackendOfflineBody('127.0.0.1:15353')),
      findsOneWidget,
    );
    expect(find.byType(DashboardCard), findsNothing);

    backend.failAfter = null;
    await tester.tap(find.text(l10n.desktopRetry));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardCard), findsNWidgets(10));
    expect(find.byType(RecentQueriesCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('令牌缺失时说清是鉴权问题而不是服务没起来', (tester) async {
    await pumpHome(tester, backend: FakeDesktopBackend(statusCode: 401));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopBackendUnauthorizedTitle), findsOneWidget);
    expect(find.text(l10n.desktopBackendOfflineTitle), findsNothing);
  });

  testWidgets('轮询失败后保留上一份快照并标注为过期', (tester) async {
    final backend = FakeDesktopBackend(failAfter: 1);
    await pumpHome(tester, backend: backend);
    final l10n = l10nOf(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopHomePage)),
    );

    // The first answer landed; the second one is refused.
    await container.read(desktopStatusProvider.notifier).refresh();
    await tester.pumpAndSettle();

    expect(find.text('2.2.9'), findsOneWidget);
    expect(find.byType(StaleStatusNotice), findsOneWidget);
    expect(find.text(l10n.desktopBackendOfflineTitle), findsOneWidget);
  });

  testWidgets('电源按钮确认后停止 DNS，并重新读取状态', (tester) async {
    final backend = FakeDesktopBackend(status: statusPayload(dnsRunning: true));
    await pumpHome(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tester.tap(find.byType(DesktopPowerButton));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopStopDnsTitle), findsOneWidget);

    backend.status = statusPayload(dnsRunning: false);
    await tester.tap(find.text(l10n.commonConfirm));
    await tester.pumpAndSettle();

    expect(backend.has('/api/v1/dns/stop'), isTrue);
    expect(find.text(l10n.stateStopped), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('取消确认不会发出停止请求', (tester) async {
    final backend = FakeDesktopBackend();
    await pumpHome(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tester.tap(find.byType(DesktopPowerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.commonCancel));
    await tester.pumpAndSettle();

    expect(backend.has('/api/v1/dns/stop'), isFalse);
  });

  testWidgets('接管开关把请求发到服务端', (tester) async {
    final backend = FakeDesktopBackend(status: statusPayload(takeover: false));
    await pumpHome(tester, backend: backend);

    backend.status = statusPayload(takeover: true);
    await tester.tap(
      find.descendant(
        of: find.byType(TakeoverTile),
        matching: find.byType(DashboardCard),
      ),
    );
    await tester.pumpAndSettle();

    expect(backend.has('/api/v1/takeover/enable'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中等宽度按双列瀑布流排布，卡片保持内容高度', (tester) async {
    await pumpHome(tester, size: const Size(1000, 800));

    final cards = find.byType(DashboardCard).evaluate().toList();
    expect(cards, hasLength(10));
    final boxes = [
      for (final element in cards) element.renderObject! as RenderBox,
    ];
    // Two columns, not one stretched list and not the four-column design grid.
    final lefts = boxes.map((box) => box.localToGlobal(Offset.zero).dx).toSet();
    expect(lefts, hasLength(2));
    // Cards keep their own height: a masonry board cannot give every card one row height.
    final heights = boxes.map((box) => box.size.height).toSet();
    expect(heights.length, greaterThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗把卡片排成一列，不套桌面行高', (tester) async {
    await pumpHome(tester, size: const Size(390, 844));

    expect(find.byType(DesktopDashboardBoard), findsOneWidget);
    expect(find.byType(DashboardCard), findsNWidgets(10));
    // Every card is full width in one column.
    final widths = {
      for (final element in find.byType(DashboardCard).evaluate())
        (element.renderObject! as RenderBox).size.width,
    };
    expect(widths, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
