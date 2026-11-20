import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const screenshotDirectory = '../../build/screenshots';

bool get screenshotsEnabled =>
    Platform.environment['DITING_SCREENSHOTS'] == '1';

Future<void> loadHostFonts() async {
  const wanted = <String, List<String>>{
    'Segoe UI': [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\msyh.ttf',
      r'C:\Windows\Fonts\simhei.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ],
    'Roboto': [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\simhei.ttf',
      '/System/Library/Fonts/PingFang.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
    ],
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

class ScreenshotSpec {
  const ScreenshotSpec({
    required this.name,
    required this.app,
    this.size = const Size(1280, 800),
    this.platform,
    this.prepare,
  });

  final String name;
  final Widget app;
  final Size size;

  final Future<void> Function(WidgetTester tester)? prepare;

  final TargetPlatform? platform;
}

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
    await tester.pumpAndSettle();

    if (spec.prepare case final prepare?) {
      await prepare(tester);
      await tester.pumpAndSettle();
    }

    await expectLater(
      find.byKey(boundary),
      matchesGoldenFile('$screenshotDirectory/${spec.name}.png'),
    );
  } finally {
    debugDefaultTargetPlatformOverride = previousPlatform;
  }
}
