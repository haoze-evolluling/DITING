// The desktop app's self-screenshot entry point. Run it, then look at
// `desktop/app/build/screenshots/*.png`:
//
//   DITING_SCREENSHOTS=1 flutter test test/screenshot/desktop_screenshot_test.dart --update-goldens
//
// Without the environment variable every case is skipped, so a plain `flutter test` stays clean.
// The shots render `DesktopApp` as a Windows window, so the theme picks the Windows page
// transitions and leaves text to the system fonts the product uses.

import 'package:diting_desktop/app/desktop_app.dart';
import 'package:diting_desktop/data/api/desktop_api_providers.dart';
import 'package:diting_desktop/data/api/desktop_live_providers.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/desktop_api_fakes.dart';
import 'screenshot_harness.dart';

void main() {
  // Pin Chinese so the screenshots capture the shipped strings, exactly like the Android suites.
  setUp(() {
    final dispatcher = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });
  setUpAll(loadHostFonts);
  // `testWidgets` only takes a bool; the reason lives in the file header and the harness.
  final skip = !screenshotsEnabled;

  group('桌面', () {
    Widget app({
      String? location,
      Map<String, Object?>? settings,
      FakeDesktopBackend? backend,
    }) {
      return ProviderScope(
        overrides: [
          legacyPrefsStoreProvider.overrideWithValue(
            MemoryLegacyPrefsStore({'dns_vpn_prefs': ?settings}),
          ),
          // A deterministic backend: the shots must not depend on whether a service happens to be
          // listening on this machine, and no test may open a socket.
          desktopPollingEnabledProvider.overrideWithValue(false),
          desktopLiveEnabledProvider.overrideWithValue(false),
          desktopApiClientProvider.overrideWithValue(
            (backend ?? FakeDesktopBackend()).client(),
          ),
        ],
        child: DesktopApp(initialLocation: location),
      );
    }

    const window = Size(1280, 800);

    for (final location in desktopBranchOrder) {
      testWidgets('桌面 ${_slug(location)}', (tester) async {
        await captureScreenshot(
          tester,
          ScreenshotSpec(
            name: 'desktop-${_slug(location)}-light',
            app: app(location: location),
            size: window,
            platform: TargetPlatform.windows,
          ),
        );
      }, skip: skip);
    }

    testWidgets('桌面首页深色', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-dark',
          app: app(settings: {'app_theme_mode': 'dark'}),
          size: window,
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页窄窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-narrow',
          app: app(),
          size: const Size(390, 844),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面关于窄窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-about-narrow',
          app: app(location: '/about'),
          size: const Size(390, 844),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页放大字号', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-large-text',
          app: app(settings: {'app_text_scale': 1.4}),
          size: const Size(390, 844),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页小窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-small',
          app: app(),
          size: const Size(800, 600),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页双列', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-two-column',
          app: app(),
          size: const Size(1280, 900),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面缓存双列', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-cache-two-column',
          app: app(location: '/hub/cache'),
          size: const Size(1280, 900),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页单列宽窗', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-single-wide',
          app: app(),
          size: const Size(1150, 900),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面服务连不上', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-offline',
          app: app(backend: FakeDesktopBackend(statusCode: 503)),
          size: window,
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页全页', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-full',
          app: app(),
          size: const Size(1280, 1800),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    // Dialogs are where the densest forms live, and a page shot never shows them. Each one is
    // opened by the same tap a user makes, so the shot covers the real route into it.
    testWidgets('桌面重写规则弹窗', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-dialog-rewrite',
          app: app(location: '/hub/rewrite'),
          size: window,
          platform: TargetPlatform.windows,
          prepare: (tester) async {
            await tester.tap(find.text('添加重写规则').first);
          },
        ),
      );
    }, skip: skip);

    testWidgets('桌面规则订阅弹窗', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-dialog-filter-list',
          app: app(location: '/hub/filter-lists'),
          size: window,
          platform: TargetPlatform.windows,
          prepare: (tester) async {
            await tester.tap(find.byTooltip('添加规则库').first);
          },
        ),
      );
    }, skip: skip);

    testWidgets('桌面修改密码弹窗', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-dialog-password',
          app: app(location: '/hub/lan-web'),
          size: window,
          platform: TargetPlatform.windows,
          prepare: (tester) async {
            await tester.tap(find.text('修改管理员密码').first);
          },
        ),
      );
    }, skip: skip);

    testWidgets('桌面首页双列宽窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-two-column-wide',
          app: app(),
          size: const Size(1600, 900),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);

    // Every page at both sides of the two-column breakpoint. 1280 leaves a 1056-wide content
    // column after the sidebar, which is the tightest two-column board; 700 drops to one column.
    // This is the layout contract the screenshots exist to catch.
    const allPages = [
      '/',
      '/hub',
      '/about',
      '/hub/upstream',
      '/hub/cache',
      '/hub/rewrite',
      '/hub/dns64',
      '/hub/adapters',
      '/hub/lan-dns',
      '/hub/filter-lists',
      '/hub/filter-rules',
      '/hub/filter-config',
      '/hub/filter-schedule',
      '/hub/filter-services',
      '/hub/privacy',
      '/hub/encrypted-dns',
      '/home/client-groups',
      '/hub/client-access',
      '/hub/query-log',
      '/hub/rule-test',
      '/hub/appearance',
      '/hub/service',
      '/hub/lan-web',
    ];
    for (final location in allPages) {
      for (final (label, size) in [
        ('two-column', const Size(1280, 900)),
        ('single', const Size(700, 800)),
      ]) {
        testWidgets('桌面布局 ${_slug(location)} $label', (tester) async {
          await captureScreenshot(
            tester,
            ScreenshotSpec(
              name: 'desktop-all-${_slug(location)}-$label',
              app: app(location: location),
              size: size,
              platform: TargetPlatform.windows,
            ),
          );
          expect(tester.takeException(), isNull);
        }, skip: skip);
      }
    }
  });
}

/// `/` → `home`, `/logs` → `logs`: one stable file name per branch.
String _slug(String location) =>
    location == Routes.home ? 'home' : location.replaceAll('/', '');
