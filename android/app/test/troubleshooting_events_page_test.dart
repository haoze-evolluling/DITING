import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/native/runtime_event.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/runtime_event_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_hooks.dart';

void main() {
  installGlobalTestHooks();

  testWidgets('运行事件页显示异常横幅，并按级别筛选', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final events = [
      RuntimeEvent.parse('2026-11-13 22:00:00.000 INFO startup begin ms=8')!,
      RuntimeEvent.parse('2026-11-13 22:00:03.000 ERROR service engine.stop')!,
      RuntimeEvent.parse('2026-11-13 22:00:04.000 WARN dns dial.fail')!,
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          runtimeEventsProvider.overrideWith((ref) async => events),
        ],
        child: const DitingApp(
          initialLocation: HubPaths.troubleshootingEvents,
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 1 条 ERROR 触发异常横幅。
    expect(find.text('检测到 1 条异常'), findsOneWidget);
    expect(find.text('INFO · startup'), findsOneWidget);
    expect(find.text('ERROR · service'), findsOneWidget);
    expect(find.text('WARN · dns'), findsOneWidget);

    // 切到“仅错误”后只剩 ERROR 行。
    await tester.tap(find.text('仅错误'));
    await tester.pumpAndSettle();
    expect(find.text('ERROR · service'), findsOneWidget);
    expect(find.text('INFO · startup'), findsNothing);
    expect(find.text('WARN · dns'), findsNothing);
  });
}
