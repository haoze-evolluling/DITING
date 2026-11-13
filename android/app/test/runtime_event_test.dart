import 'package:diting_android/data/native/runtime_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('解析一行运行事件的时间、级别、模块、事件与明细', () {
    final event = RuntimeEvent.parse(
      '2026-11-13 22:00:00.123 WARN service engine.stop reason=user',
    )!;
    expect(event.timeText, '2026-11-13 22:00:00.123');
    expect(event.levelTag, 2);
    expect(event.levelName, 'WARN');
    expect(event.module, 'service');
    expect(event.code, 'engine.stop');
    expect(event.detail, 'reason=user');
    expect(event.isWarnOrAbove, isTrue);
    expect(event.isError, isFalse);
  });

  test('空白或字段不足的行返回 null', () {
    expect(RuntimeEvent.parse(''), isNull);
    expect(RuntimeEvent.parse('   '), isNull);
    expect(RuntimeEvent.parse('only three tokens'), isNull);
  });

  test('级别映射未知值回落到 INFO', () {
    final event = RuntimeEvent.parse(
      '2026-11-13 22:00:00.000 TRACE mod code',
    )!;
    expect(event.levelTag, 1);
  });

  test('startup 行的 ms 字段可被读取', () {
    final event = RuntimeEvent.parse(
      '2026-11-13 22:00:00.000 INFO startup first_frame ms=2400',
    )!;
    expect(event.elapsedMs, 2400);
  });

  test('汇总统计错误数与慢启动异常', () {
    final events = [
      RuntimeEvent.parse('2026-11-13 22:00:00.000 INFO startup begin ms=10')!,
      RuntimeEvent.parse('2026-11-13 22:00:02.000 INFO startup first_frame ms=2400')!,
      RuntimeEvent.parse('2026-11-13 22:00:03.000 ERROR service engine.stop')!,
      RuntimeEvent.parse('2026-11-13 22:00:04.000 WARN dns dial.fail')!,
    ];
    final summary = RuntimeEventSummary(events);
    expect(summary.count, 4);
    expect(summary.errors, 1);
    expect(summary.warnOrAbove, 2);
    expect(summary.hasSlowStartup, isTrue);
    // One error plus the slow startup stage.
    expect(summary.anomalyCount, 2);
    expect(summary.hasAnomaly, isTrue);
  });

  test('只有 INFO 且启动正常时无异常', () {
    final events = [
      RuntimeEvent.parse('2026-11-13 22:00:00.000 INFO startup begin ms=5')!,
    ];
    expect(RuntimeEventSummary(events).hasAnomaly, isFalse);
  });

  test('窗口内三次崩溃判定为崩溃循环', () {
    final events = [
      for (var index = 0; index < 3; index++)
        RuntimeEvent.parse(
          '2026-11-13 22:00:0$index.000 FATAL crash uncaught thread=main',
        )!,
    ];
    final summary = RuntimeEventSummary(events);
    expect(summary.crashes, 3);
    expect(summary.hasCrashLoop, isTrue);
    expect(summary.hasAnomaly, isTrue);
  });
}
