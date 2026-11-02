// The web console login page: the same Flutter bundle is served to a browser, and only the browser
// authenticates — the native Windows window is never web. Every branch below is a promise the old
// console's `LoginView.vue` made.

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_auth_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_desktop/data/host/desktop_platform_host.dart';
import 'package:diting_desktop/pages/auth/desktop_login_page.dart';
import 'package:diting_desktop/pages/auth/widgets/login_background_dialog.dart';
import 'package:diting_desktop/pages/auth/widgets/login_change_password_card.dart';
import 'package:diting_desktop/pages/home/desktop_home_page.dart';
import 'package:diting_desktop/pages/about/desktop_about_page.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/desktop_api_fakes.dart';

void main() {
  final origin = Uri.parse('http://192.168.1.10:15353');

  Future<(FakeDesktopBackend, MemoryLegacyPrefsStore)> pumpConsole(
    WidgetTester tester, {
    FakeDesktopBackend? backend,
    Map<String, Map<String, Object?>>? seed,
    bool web = true,
    Uri? pageOrigin,
    String? initialLocation,
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
          desktopWebConsoleProvider.overrideWithValue(web),
          desktopPageOriginProvider.overrideWithValue(pageOrigin ?? origin),
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(fake.client()),
        ],
        child: DesktopApp(initialLocation: initialLocation),
      ),
    );
    await tester.pumpAndSettle();
    return (fake, store);
  }

  AppL10n l10nOf(WidgetTester tester) =>
      tester.element(find.byType(DesktopLoginPage)).l10n;

  Map<String, Map<String, Object?>> seededToken({String token = 'stored'}) => {
    'diting_desktop': {'session_token': token, 'session_user': 'admin'},
  };

  test('背景图按 1920×1080 等比缩放，不放大小图', () {
    expect(desktopBackgroundSize(3840, 2160), (width: 1920, height: 1080));
    expect(desktopBackgroundSize(4000, 1000), (width: 1920, height: 480));
    expect(desktopBackgroundSize(1000, 4000), (width: 270, height: 1080));
    expect(desktopBackgroundSize(1280, 720), (width: 1280, height: 720));
    expect(desktopBackgroundSize(0, 0), (width: 0, height: 0));
  });

  test('体积仍然过大时二次降采样到 1280×720 以内且有下限', () {
    expect(
      desktopBackgroundShrinkSize(1920, 1080),
      (width: 1280, height: 720),
    );
    // 0.75 of the first pass wins when the caps allow it.
    expect(
      desktopBackgroundShrinkSize(800, 600),
      (width: 600, height: 450),
    );
    // Never below the console's floor.
    expect(
      desktopBackgroundShrinkSize(100, 100),
      (width: desktopBackgroundMinWidth, height: desktopBackgroundMinHeight),
    );
  });

  test('非 web 宿主没有压缩能力，原样返回而不丢图', () async {
    const dataUrl = 'data:image/png;base64,AAAA';
    expect(await compressDesktopImageDataUrl(dataUrl), dataUrl);
  });

  testWidgets('登录页可改密码：提交原密码、新密码并回到登录', (tester) async {
    final (backend, _) = await pumpConsole(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.desktopLoginChangePassword));
    await tester.pumpAndSettle();
    expect(find.byType(LoginChangePasswordCard), findsOneWidget);
    expect(find.text(l10n.desktopLoginChangeSubtitle), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(LoginChangePasswordCard),
      matching: find.byType(TextField),
    );
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(0), 'old-pass');
    await tester.enterText(fields.at(1), 'new-pass');
    await tester.enterText(fields.at(2), 'new-pass');
    await tester.tap(find.text(l10n.desktopLoginChangeSubmit));
    await tester.pumpAndSettle();

    expect(backend.passwordUpdates.single, {
      'username': 'admin',
      'oldPassword': 'old-pass',
      'newPassword': 'new-pass',
    });
    expect(find.text(l10n.desktopLoginChangeSuccess), findsOneWidget);

    await tester.tap(find.text(l10n.desktopLoginBackToSignIn));
    await tester.pumpAndSettle();
    expect(find.byType(LoginChangePasswordCard), findsNothing);
    expect(find.text(l10n.desktopLoginSubmit), findsOneWidget);
  });

  testWidgets('改密码缺原密码或两次不一致时不提交', (tester) async {
    final (backend, _) = await pumpConsole(tester);
    final l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.desktopLoginChangePassword));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(LoginChangePasswordCard),
      matching: find.byType(TextField),
    );

    await tester.enterText(fields.at(1), 'new-pass');
    await tester.enterText(fields.at(2), 'new-pass');
    await tester.tap(find.text(l10n.desktopLoginChangeSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginOldPasswordRequired), findsOneWidget);

    await tester.enterText(fields.at(0), 'old-pass');
    await tester.enterText(fields.at(1), 'new-pass');
    await tester.enterText(fields.at(2), 'other-pass');
    await tester.tap(find.text(l10n.desktopLoginChangeSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginPasswordMismatch), findsOneWidget);

    expect(backend.passwordUpdates, isEmpty);
  });

  testWidgets('首次初始化时不提供改密码入口', (tester) async {
    await pumpConsole(
      tester,
      backend: FakeDesktopBackend(auth: authPayload(initialized: false)),
    );
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLoginChangePassword), findsNothing);
  });

  testWidgets('桌面窗口不出现登录页，直接进入控制台', (tester) async {
    final backend = FakeDesktopBackend();
    await pumpConsole(tester, backend: backend, web: false);

    expect(find.byType(DesktopLoginPage), findsNothing);
    expect(find.byType(DesktopHomePage), findsOneWidget);
    expect(backend.loginRequests, isEmpty);
  });

  testWidgets('浏览器没有会话时先登录，并预填服务端的管理员名', (tester) async {
    await pumpConsole(tester);
    final l10n = l10nOf(tester);

    expect(find.byType(DesktopHomePage), findsNothing);
    expect(find.text(l10n.desktopLoginSubtitle), findsOneWidget);
    expect(find.text(l10n.desktopLoginSubmit), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byType(TextField).first,
          )
          .controller
          ?.text,
      'admin',
    );
  });

  testWidgets('登录成功后保存会话并进入控制台', (tester) async {
    final (backend, store) = await pumpConsole(tester);

    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.text(l10nOf(tester).desktopLoginSubmit));
    await tester.pumpAndSettle();

    expect(backend.loginRequests, [
      {'username': 'admin', 'password': 'secret123'},
    ]);
    expect(
      store.read('diting_desktop', desktopSessionTokenKey),
      'session-token',
    );
    expect(find.byType(DesktopLoginPage), findsNothing);
    expect(find.byType(DesktopHomePage), findsOneWidget);
  });

  testWidgets('密码错误时说明服务端原因并留在登录页', (tester) async {
    final backend = FakeDesktopBackend()..loginAccepted = false;
    await pumpConsole(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text(l10n.desktopLoginSubmit));
    await tester.pumpAndSettle();

    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(find.byType(DesktopLoginPage), findsOneWidget);
    expect(backend.loginRequests, hasLength(1));
  });

  testWidgets('空用户名与空密码不发出请求', (tester) async {
    final (backend, _) = await pumpConsole(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField).first, '');
    await tester.tap(find.text(l10n.desktopLoginSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginUserRequired), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'admin');
    await tester.tap(find.text(l10n.desktopLoginSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginPasswordRequired), findsOneWidget);
    expect(backend.loginRequests, isEmpty);
  });

  testWidgets('尚未初始化时进入首次设置，提交 setup 后再登录', (tester) async {
    final backend = FakeDesktopBackend(
      auth: authPayload(initialized: false),
    );
    final (_, store) = await pumpConsole(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLoginSetupSubtitle), findsOneWidget);
    expect(find.text(l10n.desktopLoginSetupSubmit), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.enterText(find.byType(TextField).at(2), 'secret123');
    await tester.tap(find.text(l10n.desktopLoginSetupSubmit));
    await tester.pumpAndSettle();

    expect(backend.auth['initialized'], isTrue);
    expect(backend.loginRequests, hasLength(1));
    expect(
      store.read('diting_desktop', desktopSessionTokenKey),
      'session-token',
    );
    expect(find.byType(DesktopHomePage), findsOneWidget);
  });

  testWidgets('首次设置的密码过短或两次不一致时不提交', (tester) async {
    final backend = FakeDesktopBackend(
      auth: authPayload(initialized: false),
    );
    await pumpConsole(tester, backend: backend);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField).at(1), 'abc');
    await tester.enterText(find.byType(TextField).at(2), 'abc');
    await tester.tap(find.text(l10n.desktopLoginSetupSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginPasswordTooShort), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.enterText(find.byType(TextField).at(2), 'secret456');
    await tester.tap(find.text(l10n.desktopLoginSetupSubmit));
    await tester.pumpAndSettle();
    expect(find.text(l10n.desktopLoginPasswordMismatch), findsOneWidget);

    expect(backend.auth['initialized'], isFalse);
    expect(backend.loginRequests, isEmpty);
  });

  testWidgets('已保存的令牌直接进入控制台，无需再登录', (tester) async {
    await pumpConsole(tester, seed: seededToken());

    expect(find.byType(DesktopLoginPage), findsNothing);
    expect(find.byType(DesktopHomePage), findsOneWidget);
  });

  testWidgets('令牌失效时清掉会话并回到登录页', (tester) async {
    final backend = FakeDesktopBackend()..statusRejected = true;
    final (_, store) = await pumpConsole(
      tester,
      backend: backend,
      seed: seededToken(),
    );

    expect(find.byType(DesktopLoginPage), findsOneWidget);
    expect(store.read('diting_desktop', desktopSessionTokenKey), isNull);
  });

  testWidgets('页面请求 401 时通知鉴权失效，登录页重新出现', (tester) async {
    await pumpConsole(tester, seed: seededToken());
    expect(find.byType(DesktopHomePage), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DesktopHomePage)),
    );
    container.read(desktopAuthSignalProvider).fire();
    await tester.pumpAndSettle();

    expect(find.byType(DesktopLoginPage), findsOneWidget);
  });

  testWidgets('服务端报告锁定时显示倒计时并禁用提交', (tester) async {
    final backend = FakeDesktopBackend(
      auth: authPayload(locked: true, lockoutRemainingSec: 120),
    );
    await pumpConsole(tester, backend: backend);
    final l10n = l10nOf(tester);

    expect(find.text(l10n.desktopLoginLockout(120)), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(l10n.desktopLoginSubmit),
        matching: find.byType(FilledButton),
      ),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets('服务不可达时给重试而不是登录表单', (tester) async {
    final backend = FakeDesktopBackend(statusCode: 500);
    await pumpConsole(tester, backend: backend);
    final l10n = tester.element(find.byType(Scaffold).first).l10n;

    expect(find.byType(DesktopLoginPage), findsNothing);
    expect(find.text(l10n.desktopLoginUnreachable), findsOneWidget);
    expect(find.text(l10n.desktopLoginRetry), findsOneWidget);
  });

  testWidgets('登录背景保存提交地址、暗度与模糊，恢复默认走 DELETE', (tester) async {
    final (backend, _) = await pumpConsole(
      tester,
      pageOrigin: Uri.parse('http://127.0.0.1:15353'),
    );
    final l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.desktopLoginBackground));
    await tester.pumpAndSettle();

    expect(find.byType(LoginBackgroundDialog), findsOneWidget);
    await tester.tap(find.text(l10n.desktopLoginBackgroundUrl));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, l10n.desktopLoginBackgroundUrlLabel),
      'https://example.com/bg.jpg',
    );
    await tester.tap(find.text(l10n.desktopLoginBackgroundSave));
    await tester.pumpAndSettle();

    expect(backend.backgroundUpdates, [
      {'url': 'https://example.com/bg.jpg', 'opacity': 40, 'blur': 0},
    ]);

    await tester.tap(find.byTooltip(l10n.desktopLoginBackgroundEnabled));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.desktopLoginBackgroundReset));
    await tester.pumpAndSettle();

    expect(backend.backgroundResets, [
      {'adminPassword': ''},
    ]);
  });

  testWidgets('局域网远程修改背景需要管理员密码', (tester) async {
    await pumpConsole(
      tester,
      backend: FakeDesktopBackend(
        background: backgroundPayload(
          type: 'url',
          url: 'https://example.com/bg.jpg',
        ),
      ),
    );
    final l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.desktopLoginBackgroundEnabled));
    await tester.pumpAndSettle();

    expect(find.text(l10n.desktopLoginBackgroundPasswordBody), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(LoginBackgroundDialog),
        matching: find.widgetWithText(
          TextField,
          l10n.desktopLoginBackgroundPassword,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('本机回环地址免密修改背景', (tester) async {
    await pumpConsole(tester, pageOrigin: Uri.parse('http://127.0.0.1:15353'));
    final l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.desktopLoginBackground));
    await tester.pumpAndSettle();

    expect(find.text(l10n.desktopLoginBackgroundPasswordBody), findsNothing);
  });

  testWidgets('关于页在 Web 模式下提供退出登录，退出后回到登录页', (tester) async {
    final backend = FakeDesktopBackend();
    await pumpConsole(
      tester,
      backend: backend,
      seed: seededToken(),
      initialLocation: Routes.about,
    );
    final l10n = tester.element(find.byType(DesktopAboutPage)).l10n;

    expect(find.text(l10n.desktopSettingsSessionSection), findsOneWidget);
    await tester.tap(find.text(l10n.desktopSettingsLogout));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(CommonDialog),
        matching: find.widgetWithText(TextButton, l10n.desktopSettingsLogout),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DesktopLoginPage), findsOneWidget);
  });

  testWidgets('桌面模式不显示退出登录', (tester) async {
    await pumpConsole(
      tester,
      web: false,
      initialLocation: Routes.about,
    );
    final l10n = tester.element(find.byType(DesktopAboutPage)).l10n;

    expect(find.text(l10n.desktopSettingsSessionSection), findsNothing);
    expect(find.text(l10n.desktopSettingsLogout), findsNothing);
  });
}
