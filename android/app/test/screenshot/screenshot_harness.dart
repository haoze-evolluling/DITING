// App self-screenshot harness: renders the real app at a fixed window size and writes PNGs to
// `build/screenshots/`, so a UI review works from pixels instead of from the widget tree.
//
//   DITING_SCREENSHOTS=1 flutter test test/screenshot/app_screenshot_test.dart --update-goldens
//
// The capture goes through `matchesGoldenFile` because it is the only image path the test binding
// finishes cleanly (`RenderRepaintBoundary.toImage` leaves the tester hanging after the bytes are
// read). With `--update-goldens` it writes files instead of comparing them, and the files land in
// `build/`, so no binary goldens are committed and a plain `flutter test` never compares against
// them.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the PNGs land, relative to the test file. `build/` is ignored by git.
const screenshotDirectory = '../../build/screenshots';

/// True when the screenshots were explicitly requested.
bool get screenshotsEnabled =>
    Platform.environment['DITING_SCREENSHOTS'] == '1';

/// `flutter test` draws text with the built-in test font, which renders every glyph as a box, and
/// the theme asks for platform families by name. Register the host's real faces under those names so
/// the screenshots show the same text a user sees.
///
/// Family names must match `appFontFamilyFallback` for Windows plus the Material default family, so
/// Latin text and Han text both resolve. Missing files are skipped: a screenshot with box glyphs is
/// still useful for layout, and the harness must not fail on a machine without these fonts.
Future<void> loadHostFonts() async {
  const wanted = <String, List<String>>{
    // Material 2021 typography on Windows.
    'Segoe UI': [
      r'C:\Windows\Fonts\segoeui.ttf',
      '/System/Library/Fonts/SFNS.ttf',
      '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    ],
    // Material 2021 typography on Android; the CJK face also carries Latin glyphs, which is what
    // the reference shots need because Android has no Han fallback family in `appFontFamilyFallback`.
    'Roboto': [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\simhei.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ],
    // Han fallback for a simplified-Chinese UI locale.
    'Microsoft YaHei UI': [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\msyh.ttf',
      r'C:\Windows\Fonts\simhei.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ],
  };
  for (final entry in wanted.entries) {
    for (final path in entry.value) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(entry.key)
        ..addFont(Future.value(bytes.buffer.asByteData()));
      await loader.load();
      break;
    }
  }
}

/// One screenshot: a file name, the widget to mount, and the logical window size.
class ScreenshotSpec {
  const ScreenshotSpec({
    required this.name,
    required this.app,
    this.size = const Size(1280, 800),
    this.platform,
  });

  final String name;
  final Widget app;
  final Size size;

  /// Host platform the app should think it is running on: it drives the theme's font fallbacks and
  /// the page transition. Restored before the test ends, because the framework asserts that no
  /// foundation debug variable survives a test.
  final TargetPlatform? platform;
}

/// Mounts [spec] at [ScreenshotSpec.size] and writes `build/screenshots/<name>.png`.
///
/// [devicePixelRatio] 2 keeps text legible when the image is inspected at full size; the widget
/// tree still lays out at the logical size.
Future<void> captureScreenshot(
  WidgetTester tester,
  ScreenshotSpec spec, {
  double devicePixelRatio = 2,
}) async {
  tester.view.physicalSize = spec.size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  final previousPlatform = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = spec.platform;
  try {
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: boundary, child: spec.app));
    // A first frame settles the route transition, the card entrance animation and the dock springs.
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('$screenshotDirectory/${spec.name}.png'),
    );
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatform;
  }
}
