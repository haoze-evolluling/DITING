// Desktop settings branch, LAN console (docs/development/flutter-desktop-ui.md step 4):
// `/web/status` decides the address, the firewall backend and the credential state.

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/desktop/data/api/desktop_web_models.dart';
import 'package:diting/desktop/pages/settings/desktop_lan_web_page.dart';
import 'package:diting/desktop/pages/settings/desktop_settings_page.dart';
import 'package:diting/desktop/pages/settings/widgets/lan_web_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_card.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  Future<FakeDesktopBackend> pumpLanWeb(
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
        child: const DesktopApp(initialLocation: DesktopLanWebPage.path),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopLanWebPage)).l10n;

  Finder inCard(Finder matching) =>
      find.descendant(of: find.byType(LanWebCard), matching: matching);

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

  test('缺字段按仅本地解析，防火墙后端未知按支持处理', () {
    final status = DesktopWebStatus.fromJson(const {});
    expect(status.enabled, isFalse);
    expect(status.port, 0);
    expect(status.webUrls, isEmpty);
    expect(status.firewallSupported, isTrue);
    expect(
      DesktopWebStatus.fromJson(const {'firewallBackend': 'none'})
          .firewallSupported,
      isFalse,
    );
  });

  testWidgets('关闭时显示仅本地与凭据', (tester) async {
    await pumpLanWeb(tester);
    final l10n = l10nOf(tester);

    expect(inCard(find.text(l10n.desktopLanWebLocal)), findsOneWidget);
    expect(find.text(l10n.desktopLanWebDisabledBody), findsOneWidget);
    expect(
      find.text(l10n.desktopLanWebUser('admin')),
      findsOneWidget,
    );
    expect(find.text(l10n.desktopLanWebProtected), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('开启控制台提交端口与防火墙意图，并显示访问地址', (tester) async {
    final backend = await pumpLanWeb(tester);
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.byType(DashboardSwitch)));
    final body = backend.webUpdates.single;
    expect(body['enabled'], isTrue);
    expect(body['port'], 15353);
    expect(body['configureFirewall'], isTrue);
    expect(find.text('http://192.168.1.10:15353'), findsOneWidget);
    expect(
      inCard(find.text(l10n.desktopLanWebOpen)),
      findsOneWidget,
    );
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('端口非法不提交，合法则保存', (tester) async {
    final backend = await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(enabled: true, firewallAllowed: true),
      ),
    );
    final l10n = l10nOf(tester);

    final port = inCard(find.byType(TextFormField)).first;
    await tester.enterText(port, '0');
    await tapAt(tester, inCard(find.text(l10n.desktopLanWebSavePort)));
    expect(backend.webUpdates, isEmpty);
    expect(find.text(l10n.desktopLanWebPortInvalid), findsOneWidget);

    await tester.enterText(port, '16000');
    await tapAt(tester, inCard(find.text(l10n.desktopLanWebSavePort)));
    expect(backend.webUpdates.single['port'], 16000);
    expect(backend.webUpdates.single['enabled'], isTrue);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('防火墙开关提交 enable 并采用回读状态', (tester) async {
    final backend = await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(enabled: true, firewallAllowed: false),
      ),
    );

    await tapAt(tester, inCard(find.byType(DashboardSwitch)).last);
    expect(backend.firewallUpdates.single, {'enable': true});
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无防火墙后端时说明无需放行', (tester) async {
    await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(
          enabled: true,
          firewallBackend: 'none',
          firewallAllowed: true,
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanWebNoFirewall), findsOneWidget);
    expect(find.byType(DashboardSwitch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('修改密码提交旧密码与新密码', (tester) async {
    final backend = await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(enabled: true, initialized: true),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.text(l10n.desktopLanWebChangePassword)));
    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'old-pass');
    await tester.enterText(fields.at(1), 'new-pass');
    await tester.enterText(fields.at(2), 'new-pass');
    await tapAt(tester, find.text(l10n.desktopLanWebPasswordSave));

    expect(backend.passwordUpdates.single, {
      'username': 'admin',
      'oldPassword': 'old-pass',
      'newPassword': 'new-pass',
    });
    expect(find.text(l10n.desktopLanWebPasswordSaved), findsOneWidget);
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('两次新密码不一致时不提交', (tester) async {
    final backend = await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(enabled: true, initialized: true),
      ),
    );
    final l10n = l10nOf(tester);

    await tapAt(tester, inCard(find.text(l10n.desktopLanWebChangePassword)));
    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'old-pass');
    await tester.enterText(fields.at(1), 'new-pass');
    await tester.enterText(fields.at(2), 'other-pass');
    await tapAt(tester, find.text(l10n.desktopLanWebPasswordSave));

    expect(backend.passwordUpdates, isEmpty);
    expect(find.text(l10n.desktopLanWebPasswordMismatch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未初始化时走 setup 只提交用户名与新密码', (tester) async {
    final backend = await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(
          enabled: true,
          initialized: false,
          username: 'admin',
        ),
      ),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLanWebUnprotected), findsOneWidget);
    await tapAt(tester, inCard(find.text(l10n.desktopLanWebSetPassword)));
    final fields = find.descendant(
      of: find.byType(CommonDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'first-pass');
    await tester.enterText(fields.at(1), 'first-pass');
    await tapAt(tester, find.text(l10n.desktopLanWebPasswordSave));

    expect(backend.passwordUpdates.single, {
      'username': 'admin',
      'password': 'first-pass',
    });
    await clearMessages(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('设置分支列出局域网控制台入口并可进入', (tester) async {
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
        child: const DesktopApp(initialLocation: Routes.settings),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = tester.element(find.byType(DesktopSettingsPage)).l10n;

    await tapAt(tester, find.text(l10n.desktopLanWebPageTitle));
    expect(find.byType(DesktopLanWebPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗单列且不横向溢出', (tester) async {
    await pumpLanWeb(
      tester,
      backend: FakeDesktopBackend(
        web: webStatusPayload(enabled: true, firewallAllowed: true),
      ),
      size: const Size(390, 844),
    );
    expect(find.byType(LanWebCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
