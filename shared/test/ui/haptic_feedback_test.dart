import 'package:diting_shared/ui/card.dart';
import 'package:diting_shared/ui/haptic_feedback.dart';
import 'package:diting_shared/ui/switch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      HapticFeedbackScope(
        enabled: enabled,
        child: AppHapticTapFeedback(
          child: MaterialApp(home: Scaffold(body: child)),
        ),
      ),
    );
  }

  testWidgets('点击语义控件产生一次 lightImpact', (tester) async {
    var taps = 0;
    await pump(
      tester,
      ListTile(onTap: () => taps++, title: const Text('tap target')),
    );

    await tester.tap(find.text('tap target'));
    await tester.pump();

    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('按住超过长按阈值但目标没有长按手势时仍产生反馈', (tester) async {
    var taps = 0;
    await pump(
      tester,
      ListTile(onTap: () => taps++, title: const Text('slow tap')),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('slow tap')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up(timeStamp: const Duration(milliseconds: 700));
    await tester.pump();

    expect(taps, 1);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('长按控件时松手不再补一次点击反馈', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await pump(
      tester,
      ListTile(
        onTap: () => taps++,
        onLongPress: () => longPresses++,
        title: const Text('long press target'),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('long press target')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up(timeStamp: const Duration(milliseconds: 700));
    await tester.pump();

    expect(taps, 0);
    expect(longPresses, 1);
    expect(haptics.where((event) => event.contains('lightImpact')), isEmpty);
  });

  testWidgets('点击卡片产生一次 lightImpact', (tester) async {
    var presses = 0;
    await pump(
      tester,
      Center(
        child: CommonCard(
          onPressed: () => presses++,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('card'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('card'));
    await tester.pump();

    expect(presses, 1);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('空白区域与列表滚动不产生反馈', (tester) async {
    await pump(
      tester,
      ListView(
        children: [
          const SizedBox(height: 160),
          ListTile(onTap: () {}, title: const Text('row')),
          const SizedBox(height: 2000),
        ],
      ),
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pump();

    expect(haptics, isEmpty);
  });

  testWidgets('关闭作用域后所有反馈静音', (tester) async {
    await pump(
      tester,
      ListTile(onTap: () {}, title: const Text('tap target')),
      enabled: false,
    );

    await tester.tap(find.text('tap target'));
    await tester.pump();

    expect(haptics, isEmpty);
  });

  testWidgets('开关点击与拖动切换各产生一次反馈', (tester) async {
    var value = false;
    await pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Center(
          child: CommonSwitch(
            value: value,
            onChanged: (next) => setState(() => value = next),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(CommonSwitch));
    await tester.pump(const Duration(milliseconds: 60));
    expect(value, isTrue);
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    // The repeat guard runs on a real-time stopwatch, so fake-time pumping does not expire it.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    haptics.clear();
    await tester.drag(find.byType(CommonSwitch), const Offset(-40, 0));
    await tester.pump();
    expect(value, isFalse);
    expect(haptics, isNotEmpty);
  });
}
