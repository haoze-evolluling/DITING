// The temporary-pause page drives the R4 bridge. This guards the redesign that replaced the
// 15/30/60 preset buttons with a single pop-up duration menu plus a custom-minutes dialog.

import 'package:diting_android/data/native/block_pause_bridge.dart';
import 'package:diting_android/pages/rules/block_pause_page.dart';
import 'package:diting_android/state/block_pause_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support/app_host.dart';

/// Records the calls the page makes, so the test can assert the chosen duration reached the bridge.
class _FakeBridge extends BlockPauseBridge {
  int pausedUntilMs = 0;
  bool allowlistOnly = false;
  final pauses = <int>[];

  BlockPauseState _state() => BlockPauseState(
    pausedUntilMs: pausedUntilMs,
    allowlistOnly: allowlistOnly,
  );

  @override
  Future<BlockPauseState> read() async => _state();

  @override
  Future<BlockPauseState> pause(int minutes) async {
    pauses.add(minutes);
    pausedUntilMs = DateTime.now()
        .add(Duration(minutes: minutes))
        .millisecondsSinceEpoch;
    return _state();
  }

  @override
  Future<BlockPauseState> clear() async {
    pausedUntilMs = 0;
    return _state();
  }

  @override
  Future<BlockPauseState> setAllowlistOnly(bool enabled) async {
    allowlistOnly = enabled;
    return _state();
  }
}

void main() {
  Future<_FakeBridge> pump(WidgetTester tester) async {
    const dpr = 3.0;
    tester.view.physicalSize = const Size(411, 891) * dpr;
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    final fake = _FakeBridge();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [blockPauseBridgeProvider.overrideWithValue(fake)],
        child: const AppHost(child: BlockPausePage()),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('暂停时长以弹出菜单呈现预设，点击即暂停', (tester) async {
    final fake = await pump(tester);
    expect(find.text('暂停时长'), findsOneWidget);
    // The picker shows a concrete value, not only an arrow.
    expect(find.text('15 分钟'), findsOneWidget);
    expect(find.text('暂停 15 分钟'), findsNothing);

    await tester.tap(find.text('暂停时长'));
    await tester.pumpAndSettle();
    expect(find.text('暂停 15 分钟'), findsOneWidget);
    expect(find.text('暂停 30 分钟'), findsOneWidget);
    expect(find.text('暂停 60 分钟'), findsOneWidget);
    expect(find.text('自定义时长…'), findsOneWidget);

    await tester.tap(find.text('暂停 30 分钟'));
    await tester.pumpAndSettle();
    expect(fake.pauses, [30]);
    // The row's value follows the picked length.
    expect(find.text('30 分钟'), findsOneWidget);
  });

  testWidgets('自定义时长先校验范围，再以输入的分钟数暂停', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.text('暂停时长'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义时长…'));
    await tester.pumpAndSettle();
    expect(find.text('自定义暂停时长'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '99999');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–1440 之间的分钟数'), findsOneWidget);
    expect(fake.pauses, isEmpty);

    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(fake.pauses, [7]);
  });
}
