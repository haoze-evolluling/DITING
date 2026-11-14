// U8/U7: the phase-3 pages must render in English at a narrow width and a larger font without a
// layout overflow. Every route is pumped through the real app shell so the surrounding chrome is
// included; an overflow surfaces as a FlutterError from `takeException`.

import 'package:diting_android/app/app.dart';
import 'package:diting_android/pages/system/unknown_route_page.dart';
import 'package:diting_shared/state/settings_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/route_catalog.dart';
import 'support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  // The phase-3 surfaces, deliberately the densest ones (toggle rows, count steppers, history lists).
  const keys = [
    '本地 API',
    '隐私套件',
    'DNS64',
    'LAN 客户端限速',
    '订阅版本回滚',
    'Webhook 通知',
    '应用洞察',
    '实时连接',
  ];

  testWidgets('英语 + 320dp + 1.3 倍字号：阶段三页面无溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final key in keys) {
      final route = topLevelRoutes[key];
      expect(route, isNotNull, reason: 'route catalogue is missing $key');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...appTestOverrides(),
            appLocaleProvider.overrideWithValue(const Locale('en')),
          ],
          child: DitingApp(initialLocation: route!),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$key（$route）在英语窄屏下溢出');
      // The page must actually mount rather than fall back to the unknown-route page.
      expect(find.byType(UnknownRoutePage), findsNothing, reason: '$key 未注册');
    }
  });

  testWidgets('平板宽度：阶段三页面自适应双栏且不溢出', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final key in keys) {
      final route = topLevelRoutes[key]!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...appTestOverrides(),
            appLocaleProvider.overrideWithValue(const Locale('zh')),
          ],
          child: DitingApp(initialLocation: route),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$key（$route）在平板宽度下溢出');
      expect(find.byType(UnknownRoutePage), findsNothing, reason: '$key 未注册');
    }
  });
}
