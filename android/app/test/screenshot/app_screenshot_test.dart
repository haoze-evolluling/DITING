// The Android reference shots. Run them, then look at
// `android/app/build/screenshots/*.png`:
//
//   DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
//
// Without the environment variable every case is skipped, so a plain `flutter test` stays clean.
// These shots are the reference the desktop UI must stay identical to.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/vpn/vpn_bridge.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/widgets/glyph_lookup.dart';
import 'package:diting_shared/data/prefs/legacy_prefs_store.dart';
import 'package:diting_shared/data/prefs/legacy_settings_provider.dart';
import 'package:diting_shared/routes/branches.dart';
import 'package:diting_shared/ui/icons/icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_vpn_controller.dart';
import '../support/test_hooks.dart';
import 'screenshot_harness.dart';

void main() {
  installGlobalTestHooks();
  setUpAll(loadHostFonts);
  // `testWidgets` only takes a bool; the reason lives in the file header and the harness.
  final skip = !screenshotsEnabled;

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

    // Design review for a new icon batch: stroke and filled side by side, on the app's own theme.
    testWidgets('安卓 图标总览', (tester) async {
      await captureScreenshot(
        tester,
        ScreenshotSpec(
          name: 'android-glyphs',
          size: const Size(750, 420),
          platform: TargetPlatform.android,
          app: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              scaffoldBackgroundColor: const Color(0xFFF7F7F9),
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(18),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in _reviewGlyphs)
                      SizedBox(
                        width: 116,
                        height: 112,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                GlyphIcon(glyphByName(name), size: 40),
                                const SizedBox(width: 10),
                                GlyphIcon(glyphByName(name), size: 40, fill: 1),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(name, style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }, skip: skip);
  });
}

/// The batch under review, in `AppGlyphs` name form so the sheet and the app resolve the same glyph.
const _reviewGlyphs = <String>[
  'automation',
  'notification',
  'vibrate',
  'temperature',
  'shieldBolt',
  'battery',
  'music',
  'video',
  'shoppingBag',
  'gamepad',
  'bug',
  'database',
  'heart',
  'signal',
  'trophy',
];

/// `/` → `home`, `/logs` → `logs`: one stable file name per branch.
String _slug(String location) =>
    location == Routes.home ? 'home' : location.replaceAll('/', '');
