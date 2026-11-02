// Desktop settings branch, service and connection (docs/development/flutter-desktop-ui.md step 4):
// the app's own IPC settings are editable, the host core service is read-only.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/pages/settings/desktop_service_page.dart';
import 'package:diting_desktop/pages/hub/desktop_hub_page.dart';
import 'package:diting_desktop/pages/settings/widgets/core_service_card.dart';
import 'package:diting_desktop/pages/settings/widgets/service_connection_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<MemoryLegacyPrefsStore> pumpService(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Map<String, Map<String, Object?>>? seed,
    Size size = const Size(1280, 900),
  }) async {
    final fake = backend ?? FakeDesktopBackend();
    final store = MemoryLegacyPrefsStore(seed);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(store),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: const DesktopApp(initialLocation: DesktopServicePage.path),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopServicePage)).l10n;

  Finder inConnection(Finder matching) => find.descendant(
    of: find.byType(ServiceConnectionCard),
    matching: matching,
  );
  Finder inCore(Finder matching) =>
      find.descendant(of: find.byType(CoreServiceCard), matching: matching);

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

  testWidgets('连接设置显示当前地址，测试连接报告可达', (tester) async {
    await pumpService(
      tester,
      seed: {
        desktopPrefsContainer: {
          'ipc_host': '10.0.0.5',
          'ipc_port': 15353,
          'ipc_token': 'secret',
        },
      },
    );
    final l10n = l10nOf(tester);

    final host = inConnection(find.byType(TextFormField)).first;
    expect(tester.widget<TextFormField>(host).controller?.text, '10.0.0.5');
    await tapAt(tester, inConnection(find.byTooltip(l10n.desktopServiceTest)));
    expect(find.text(l10n.desktopServiceReachable), findsWidgets);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存写入连接键并重建客户端', (tester) async {
    final store = await pumpService(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      inConnection(find.byType(TextFormField)).first,
      '192.168.1.9',
    );
    await tester.enterText(
      inConnection(find.byType(TextFormField)).at(1),
      '16000',
    );
    await tapAt(tester, inConnection(find.text(l10n.desktopServiceSave)));

    expect(store.read(desktopPrefsContainer, 'ipc_host'), '192.168.1.9');
    expect(store.read(desktopPrefsContainer, 'ipc_port'), 16000);
    expect(store.read(desktopPrefsContainer, 'ipc_token'), '');
    expect(find.text(l10n.desktopServiceSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('非法端口不写入', (tester) async {
    final store = await pumpService(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(
      inConnection(find.byType(TextFormField)).at(1),
      '70000',
    );
    await tapAt(tester, inConnection(find.text(l10n.desktopServiceSave)));

    expect(store.read(desktopPrefsContainer, 'ipc_port'), isNull);
    expect(find.text(l10n.desktopServiceAddressInvalid), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('服务不可达时报告连接异常', (tester) async {
    await pumpService(
      tester,
      backend: FakeDesktopBackend()..healthOk = false,
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, inConnection(find.byTooltip(l10n.desktopServiceTest)));
    expect(
      find.descendant(
        of: find.byType(DashboardChip),
        matching: find.text(l10n.desktopServiceUnreachable),
      ),
      findsWidgets,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('核心服务卡显示运行状态与开机自启', (tester) async {
    await pumpService(tester);
    final l10n = l10nOf(tester);

    expect(inCore(find.text(l10n.desktopServiceRunning)), findsOneWidget);
    expect(inCore(find.text(l10n.desktopServiceAutoStartOn)), findsOneWidget);
    expect(inCore(find.text('running')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未安装时核心服务卡给出未安装状态', (tester) async {
    await pumpService(
      tester,
      backend: FakeDesktopBackend(
        service: servicePayload(
          installed: false,
          running: false,
          autoStart: false,
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(
      inCore(find.text(l10n.desktopServiceNotInstalled)),
      findsOneWidget,
    );
    expect(inCore(find.text(l10n.desktopServiceAutoStartOff)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置分支列出服务入口并可进入', (tester) async {
    final fake = FakeDesktopBackend();
    tester.view.physicalSize = const Size(1280, 900);
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
        child: const DesktopApp(initialLocation: Routes.hub),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = tester.element(find.byType(DesktopFeatureHubPage)).l10n;

    await tapAt(tester, find.text(l10n.desktopServicePageTitle));
    expect(find.byType(DesktopServicePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpService(tester, size: const Size(390, 844));
    expect(find.byType(ServiceConnectionCard), findsOneWidget);
    expect(find.byType(CoreServiceCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
