// Desktop adapter takeover (docs/development/flutter-desktop-ui.md §8.29): the adapter list from
// `/adapters`, the takeover set from `/status`, and the three writes. Every value comes from the
// service; a rejected write keeps the state the service still holds.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_adapters_models.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/hub/desktop_adapters_page.dart';
import 'package:diting/desktop/pages/hub/widgets/adapter_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/routes/branches.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpAdapters(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
  }) async {
    final fake =
        backend ??
        FakeDesktopBackend(status: statusPayload(takeover: false));
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
        child: const DesktopApp(initialLocation: DesktopAdaptersPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopAdaptersPage)).l10n;

  Finder inCard(String name, Finder matching) => find.descendant(
    of: find.ancestor(
      of: find.text(name),
      matching: find.byType(AdapterCard),
    ),
    matching: matching,
  );

  test('缺字段按零值解析，连接状态按 Up 判定', () {
    final adapter = DesktopAdapter.fromJson(const {});
    expect(adapter.id, isEmpty);
    expect(adapter.name, isEmpty);
    expect(adapter.index, 0);
    expect(adapter.isUp, isFalse);
    expect(adapter.dns, isEmpty);
    expect(adapter.ipv4Dhcp, isFalse);

    final up = DesktopAdapter.fromJson(const {
      'id': 'wlan-guid',
      'status': 'Up',
      'ipv4DNS': ['192.168.1.1'],
      'ipv6DNS': ['fe80::1'],
    });
    expect(up.isUp, isTrue);
    expect(up.dns, ['192.168.1.1', 'fe80::1']);
  });

  testWidgets('网卡卡片显示状态、网关、IP 模式与接管前后 DNS', (tester) async {
    await pumpAdapters(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(AdapterCard), findsNWidgets(2));
    expect(find.text('WLAN'), findsOneWidget);
    expect(find.text('以太网'), findsOneWidget);
    expect(
      find.text('Intel(R) Wi-Fi 6E AX210 160MHz'),
      findsOneWidget,
    );

    // Connection state and IP mode come from the service, not from the card.
    expect(inCard('WLAN', find.text(l10n.desktopAdaptersConnected)), findsOneWidget);
    expect(
      inCard('以太网', find.text(l10n.desktopAdaptersDisconnected)),
      findsOneWidget,
    );
    // Gateway and the adapter's original DNS are the same value, so both rows show it.
    expect(inCard('WLAN', find.text('192.168.1.1')), findsNWidgets(2));
    expect(inCard('WLAN', find.text(l10n.desktopAdaptersDhcp)), findsOneWidget);
    expect(
      inCard('以太网', find.text(l10n.desktopAdaptersStatic)),
      findsOneWidget,
    );

    // Original DNS: the value the service reported, or the automatic label when it had none.
    expect(
      inCard('以太网', find.text(l10n.desktopAdaptersAutoDns)),
      findsOneWidget,
    );
    // Nothing is taken over yet, so both cards report the system default.
    expect(
      find.text(l10n.desktopAdaptersEffectiveSystem),
      findsNWidgets(2),
    );
    expect(find.text(l10n.desktopAdaptersProtecting), findsNothing);
  });

  testWidgets('单个网卡开关提交 adapterId 并采用服务端接管状态', (tester) async {
    final backend = await pumpAdapters(tester);
    final l10n = l10nOf(tester);

    await tester.tap(inCard('WLAN', find.byType(DashboardSwitch)));
    await tester.pumpAndSettle();

    expect(backend.adapterTakeovers, [
      {'adapterId': 'wlan-guid', 'enable': true},
    ]);
    // The switch, the protecting chip and the effective-DNS line all follow the service.
    expect(find.text(l10n.desktopAdaptersProtecting), findsWidgets);
    expect(
      inCard('WLAN', find.text(l10n.desktopAdaptersEffectiveLoopback)),
      findsOneWidget,
    );
    expect(
      inCard('以太网', find.text(l10n.desktopAdaptersEffectiveSystem)),
      findsOneWidget,
    );
  });

  testWidgets('全部开启保护提交 /takeover/enable，恢复默认提交 /takeover/disable', (
    tester,
  ) async {
    final backend = await pumpAdapters(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.desktopAdaptersTakeoverAll));
    await tester.pumpAndSettle();

    expect(backend.status['takeover'], {
      'active': true,
      'adapters': [
        {'id': 'wlan-guid'},
        {'id': 'eth-guid'},
      ],
    });
    expect(find.text(l10n.desktopAdaptersProtecting), findsWidgets);

    await tester.tap(find.text(l10n.desktopAdaptersRestoreAll));
    await tester.pumpAndSettle();

    expect(backend.status['takeover'], {'active': false, 'adapters': []});
    expect(find.text(l10n.desktopAdaptersEffectiveSystem), findsNWidgets(2));
  });

  testWidgets('写被拒时说明原因并保留服务端状态', (tester) async {
    final backend = await pumpAdapters(tester)..rejectWrites = true;
    final l10n = l10nOf(tester);

    await tester.tap(inCard('WLAN', find.byType(DashboardSwitch)));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.desktopAdaptersActionFailed('write rejected')),
      findsOneWidget,
    );
    // The rejected write changed nothing on screen: the card still reports the service's answer.
    expect(
      inCard('WLAN', find.text(l10n.desktopAdaptersEffectiveSystem)),
      findsOneWidget,
    );
    final toggle = tester.widget<DashboardSwitch>(
      inCard('WLAN', find.byType(DashboardSwitch)),
    );
    expect(toggle.value, isFalse);
    expect(backend.adapterTakeovers, hasLength(1));
  });

  testWidgets('无网卡时给空态并可重新检测', (tester) async {
    final backend = FakeDesktopBackend(
      status: statusPayload(takeover: false),
      adapters: const [],
    );
    await pumpAdapters(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopAdaptersEmpty), findsOneWidget);
    expect(find.text(l10n.desktopAdaptersEmptyBody), findsOneWidget);
    expect(find.byType(AdapterCard), findsNothing);

    await tester.tap(find.text(l10n.desktopAdaptersRefresh));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopAdaptersEmpty), findsOneWidget);
  });

  testWidgets('需要令牌时给出鉴权提示', (tester) async {
    final backend = FakeDesktopBackend(statusCode: 401);
    await pumpAdapters(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopAdaptersLoadFailed), findsOneWidget);
    expect(find.text(l10n.desktopBackendUnauthorizedBody), findsOneWidget);
  });

  testWidgets('窄窗单列不横向溢出', (tester) async {
    await pumpAdapters(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(AdapterCard), findsNWidgets(2));
  });

  test('路由挂在 hub 分支下', () {
    expect(DesktopAdaptersPage.path, '/hub/adapters');
    expect(Routes.hub, '/hub');
  });
}
