// Desktop LAN DNS service (docs/development/flutter-desktop-ui.md §8.30): the listen addresses, the
// host's LAN addresses and the 53-port firewall rule, all from `/dns/lan`. Each write re-reads it.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_lan_models.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/pages/hub/desktop_lan_dns_page.dart';
import 'package:diting/desktop/widgets/desktop_copy_row.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpLan(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Size size = const Size(1280, 900),
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
        child: const DesktopApp(initialLocation: DesktopLanDnsPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopLanDnsPage)).l10n;

  test('缺字段按零值解析，防火墙后端为空按支持处理', () {
    final status = DesktopLanStatus.fromJson(const {});
    expect(status.allowLan, isFalse);
    expect(status.listenAddresses, isEmpty);
    expect(status.lanAddresses, isEmpty);
    expect(status.firewallBackend, isEmpty);
    expect(status.firewallSupported, isTrue);

    final none = DesktopLanStatus.fromJson(const {'firewallBackend': 'none'});
    expect(none.firewallSupported, isFalse);
  });

  testWidgets('显示监听地址、局域网地址与两种配置方案', (tester) async {
    await pumpLan(tester);
    final l10n = l10nOf(tester);

    // Page title and card title carry the same name.
    expect(find.text(l10n.desktopLanDnsServiceTitle), findsNWidgets(2));
    expect(find.text(l10n.desktopLanDnsOffChip), findsOneWidget);
    // Listen addresses come from the service, both stacks.
    expect(find.text('127.0.0.1:53'), findsOneWidget);
    // The LAN addresses are listed as copyable rows, tagged by family.
    expect(find.text('192.168.1.10'), findsWidgets);
    expect(find.text('fe80::1'), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsIpv4), findsWidgets);
    expect(find.text(l10n.desktopLanDnsIpv6), findsOneWidget);
    expect(find.byType(DesktopCopyRow), findsWidgets);
    // Both guides show the first LAN address.
    expect(find.text(l10n.desktopLanDnsRouterTitle), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsDeviceTitle), findsOneWidget);
    expect(
      find.text(l10n.desktopLanDnsRouterHint('192.168.1.10')),
      findsOneWidget,
    );
  });

  testWidgets('开启局域网服务提交 allowLAN 与 configureFirewall 并采用服务端状态', (tester) async {
    final backend = await pumpLan(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.byType(DashboardSwitch));
    await tester.pumpAndSettle();

    expect(backend.lanUpdates, [
      {'allowLAN': true, 'configureFirewall': true},
    ]);
    expect(find.text(l10n.desktopLanDnsOnChip), findsOneWidget);
    expect(find.text('0.0.0.0:53'), findsOneWidget);
    expect(find.text('[::]:53'), findsOneWidget);
  });

  testWidgets('关闭局域网服务只提交 allowLAN:false', (tester) async {
    final backend = FakeDesktopBackend(lan: lanPayload(allowLan: true));
    await pumpLan(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanDnsOnChip), findsOneWidget);
    await tester.tap(find.byType(DashboardSwitch));
    await tester.pumpAndSettle();

    expect(backend.lanUpdates, [
      {'allowLAN': false, 'configureFirewall': false},
    ]);
    expect(find.text(l10n.desktopLanDnsOffChip), findsOneWidget);
  });

  testWidgets('放行与移除 53 端口入站规则各自提交 enable', (tester) async {
    final backend = await pumpLan(tester);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanDnsFirewallBlocked), findsOneWidget);
    await tester.tap(find.text(l10n.desktopLanDnsFirewallAllow));
    await tester.pumpAndSettle();

    expect(backend.lanFirewallUpdates, [
      {'enable': true},
    ]);
    expect(find.text(l10n.desktopLanDnsFirewallAllowed), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsFirewallStatusOn), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLanDnsFirewallRemove));
    await tester.pumpAndSettle();

    expect(backend.lanFirewallUpdates, [
      {'enable': true},
      {'enable': false},
    ]);
    expect(find.text(l10n.desktopLanDnsFirewallBlocked), findsOneWidget);
  });

  testWidgets('没有防火墙后端时说明无需放行，不给放行按钮', (tester) async {
    await pumpLan(
      tester,
      backend: FakeDesktopBackend(
        lan: lanPayload(firewallBackend: 'none'),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanDnsFirewallNone), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsFirewallNoneBody), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsFirewallAllow), findsNothing);
    expect(find.text(l10n.desktopLanDnsFirewallRemove), findsNothing);
  });

  testWidgets('没有局域网 IP 时如实说明而不是画占位地址', (tester) async {
    await pumpLan(
      tester,
      backend: FakeDesktopBackend(
        lan: lanPayload(lanAddresses: const []),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanDnsNoAddresses), findsOneWidget);
    expect(find.text(l10n.desktopLanDnsPlaceholder), findsNWidgets(2));
  });

  testWidgets('写被拒时说明原因且开关保持服务端值', (tester) async {
    final backend = await pumpLan(tester)..rejectWrites = true;
    final l10n = l10nOf(tester);

    await tester.tap(find.byType(DashboardSwitch));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.desktopLanDnsFailed('write rejected')),
      findsOneWidget,
    );
    final toggle = tester.widget<DashboardSwitch>(
      find.byType(DashboardSwitch),
    );
    expect(toggle.value, isFalse);
    expect(find.text(l10n.desktopLanDnsOffChip), findsOneWidget);
  });

  testWidgets('需要令牌时给出鉴权提示', (tester) async {
    await pumpLan(tester, backend: FakeDesktopBackend(statusCode: 401));
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanDnsLoadFailed), findsOneWidget);
    expect(find.text(l10n.desktopBackendUnauthorizedBody), findsOneWidget);
  });

  testWidgets('窄窗单列不横向溢出', (tester) async {
    await pumpLan(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.byType(DesktopCopyRow), findsWidgets);
  });

  test('路由挂在 hub 分支下', () {
    expect(DesktopLanDnsPage.path, '/hub/lan-dns');
  });
}
