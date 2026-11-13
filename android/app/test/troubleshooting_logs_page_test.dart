import 'package:diting_android/app/app.dart';
import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:diting_android/routes/hub_routes.dart';
import 'package:diting_android/state/troubleshooting_log_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_hooks.dart';

class _FakeBridge extends TroubleshootingLogBridge {
  @override
  Future<List<TroubleshootLogEntry>> list() async => [
    TroubleshootLogEntry(
      kind: TroubleshootLogKind.runtime,
      name: 'runtime-20261113-213000.log',
      sizeBytes: 2048,
      modifiedAt: DateTime(2026, 11, 13, 21, 30),
    ),
  ];

  @override
  Future<TroubleshootLogRead> readByName({
    required TroubleshootLogKind kind,
    required String name,
  }) async => const TroubleshootLogRead(
    content: 'hello log content',
    truncated: false,
  );
}

void main() {
  installGlobalTestHooks();

  testWidgets('日志管理分两级查看：信息卡片后进入正文', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appTestOverrides(),
          troubleshootingLogBridgeProvider.overrideWithValue(_FakeBridge()),
        ],
        child: const DitingApp(initialLocation: HubPaths.troubleshootingLogs),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('2026-11-13 21:30:00'), findsOneWidget);
    await tester.tap(find.text('2026-11-13 21:30:00'));
    await tester.pumpAndSettle();

    expect(find.text('日志信息'), findsOneWidget);
    expect(find.text('文件名'), findsOneWidget);
    expect(find.text('查看日志内容'), findsOneWidget);

    await tester.tap(find.text('查看日志内容'));
    await tester.pumpAndSettle();

    expect(find.text('hello log content'), findsOneWidget);
  });
}
