import 'package:diting_android/app/app.dart';
import 'package:diting_android/pages/system/unknown_route_page.dart';
import 'package:diting_android/state/settings_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/route_catalog.dart';
import '../support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  const keys = [
    '隐私套件',
    'DNS64',
    '连接限速',
    '订阅版本回滚',
    '连接监控',
    '按需连接',
    'User-Agent',
  ];

  testWidgets('简中 / 英文 / 繁中三种 locale 均无溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final locale in const [Locale('zh'), Locale('en'), Locale('zh', 'TW')]) {
      for (final key in keys) {
        final route = topLevelRoutes[key]!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...appTestOverrides(),
              appLocaleProvider.overrideWithValue(locale),
            ],
            child: DitingApp(initialLocation: route),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        expect(
          tester.takeException(),
          isNull,
          reason: '$key（$route）在 $locale 下溢出',
        );
        expect(find.byType(UnknownRoutePage), findsNothing, reason: '$key 未注册');
      }
    }
  });
}
