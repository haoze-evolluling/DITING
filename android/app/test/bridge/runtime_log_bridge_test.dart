// Guards the Dart side of the runtime-log channel: the status map (including the always-on event
// black box fields), the standard/detailed start argument, readEvents and the appendEvent forward.

import 'package:diting_android/data/native/runtime_log_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(runtimeLogChannelName);

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('status 解析事件黑匣子字段', () async {
    mock((call) async {
      expect(call.method, 'status');
      return {
        'capturing': true,
        'fileCount': 2,
        'sizeBytes': 2048,
        'detailed': true,
        'eventFiles': 2,
        'eventBytes': 1024,
      };
    });

    final status = await RuntimeLogBridge().status();
    expect(status.capturing, isTrue);
    expect(status.fileCount, 2);
    expect(status.detailed, isTrue);
    expect(status.eventFiles, 2);
    expect(status.eventBytes, 1024);
    expect(status.hasLogs, isTrue);
    expect(status.eventSizeLabel, '1.0 KB');
  });

  test('start 转发 detailed 档位', () async {
    mock((call) async {
      expect(call.method, 'start');
      expect(call.arguments, {'detailed': true});
      return true;
    });
    expect(await RuntimeLogBridge().start(detailed: true), isTrue);
  });

  test('readEvents 读取最近事件', () async {
    mock((call) async {
      expect(call.method, 'readEvents');
      expect(call.arguments, {'limit': 40});
      return 'a\nb';
    });
    expect(await RuntimeLogBridge().readEvents(limit: 40), 'a\nb');
  });

  test('appendEvent 转发级别与字段', () async {
    mock((call) async {
      expect(call.method, 'appendEvent');
      expect(call.arguments['module'], 'startup');
      expect(call.arguments['event'], 'prefs');
      expect(call.arguments['level'], RuntimeEventLevel.warn);
      expect((call.arguments['fields'] as Map)['ms'], 3);
      return true;
    });
    await RuntimeLogBridge().appendEvent(
      module: 'startup',
      event: 'prefs',
      level: RuntimeEventLevel.warn,
      fields: {'ms': 3},
    );
  });

  test('setMode 回读状态', () async {
    mock((call) async {
      expect(call.method, 'setMode');
      expect(call.arguments, {'detailed': false});
      return {'capturing': false, 'detailed': false, 'fileCount': 0};
    });
    expect((await RuntimeLogBridge().setMode(detailed: false)).detailed, isFalse);
  });

  test('没有原生实现时安全降级', () async {
    final bridge = RuntimeLogBridge();
    expect((await bridge.status()).capturing, isFalse);
    expect(await bridge.start(), isFalse);
    expect(await bridge.readEvents(), '');
    expect(await bridge.clear(), 0);
  });
}
