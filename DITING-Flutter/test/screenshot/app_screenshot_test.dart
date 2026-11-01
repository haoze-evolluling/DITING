// The app's own screenshot entry point. Run it, then look at `build/screenshots/*.png`:
//
//   DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
//
// Without the environment variable every case is skipped, so a plain `flutter test` stays clean.
//
// Desktop shots render `DesktopApp` as a Windows window (the real host platform for the Wails
// build), so the theme picks the Windows font fallbacks and page transitions the product uses.
// The Android shots are the reference the desktop UI must stay identical to.

import 'package:diting/app/app.dart';
import 'package:diting/data/prefs/legacy_prefs_store.dart';
import 'package:diting/data/prefs/legacy_settings_provider.dart';
import 'package:diting/data/vpn/vpn_bridge.dart';
import 'package:diting/desktop/app/desktop_app.dart';
import 'package:diting/desktop/data/api/desktop_api_providers.dart';
import 'package:diting/desktop/data/api/desktop_live_providers.dart';
import 'package:diting/routes/branches.dart';
import 'package:diting/state/work_mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/desktop_api_fakes.dart';
import '../support/fake_vpn_controller.dart';
import '../support/test_hooks.dart';
import 'screenshot_harness.dart';

void main() {
  installGlobalTestHooks();
  setUpAll(loadHostFonts);
  // `testWidgets` only takes a bool; the reason lives in the file header and the harness.
  final skip = !screenshotsEnabled;

  group('桌面', () {
    Widget app({String? location, Map<String, Object?>? settings}) {
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
            FakeDesktopBackend().client(),
          ),
        ],
        child: DesktopApp(initialLocation: location),
      );
    }

    const window = Size(1280, 800);

    for (final location in branchOrder) {
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

    testWidgets('桌面日志窄窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-logs-narrow',
          app: app(location: '/logs'),
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
          size: const Size(1000, 800),
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

    testWidgets('桌面首页双列宽窗口', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'desktop-home-two-column-wide',
          app: app(),
          size: const Size(1200, 800),
          platform: TargetPlatform.windows,
        ),
      );
    }, skip: skip);
  });

  group('安卓参照', () {
    Widget app({String? location}) {
      final vpn = FakeVpnController()
        ..statusValue = const VpnStatus(running: false, persisted: false);
      return ProviderScope(
        overrides: [
          ...appTestOverrides(),
          vpnControllerProvider.overrideWithValue(vpn),
          legacyPrefsStoreProvider.overrideWithValue(MemoryLegacyPrefsStore()),
        ],
        child: DitingApp(initialLocation: location),
      );
    }

    for (final location in [Routes.home, Routes.hub, Routes.settings]) {
      testWidgets('安卓 ${_slug(location)}', (tester) async {
        await captureScreenshot(
          tester,
          ScreenshotSpec(
            name: 'android-${_slug(location)}',
            app: app(location: location),
            size: const Size(390, 844),
            platform: TargetPlatform.android,
          ),
        );
      }, skip: skip);
    }
  });
}

/// `/` → `home`, `/logs` → `logs`: one stable file name per branch.
String _slug(String location) =>
    location == Routes.home ? 'home' : location.replaceAll('/', '');
