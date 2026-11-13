// Guards the Dart side of the troubleshooting-log channel: list parsing, the read payload and
// that delete/share/clearAll forward the kind + name the native side resolves.

import 'package:diting_android/data/native/troubleshooting_log_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(troubleshootingLogChannelName);

  void mock(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('list 解析两种类型并跳过坏行', () async {
    mock((call) async {
      expect(call.method, 'list');
      return {
        'items': [
          {
            'kind': 'runtime',
            'name': 'runtime-20261113-213000.log',
            'sizeBytes': 2048,
            'modifiedMs': 1000,
          },
          {
            'kind': 'crash',
            'name': 'crash-1.log',
            'sizeBytes': 10,
            'modifiedMs': 2000,
          },
          {'kind': 'bogus', 'name': 'x', 'sizeBytes': 1, 'modifiedMs': 0},
          {'kind': 'runtime', 'name': '', 'sizeBytes': 1, 'modifiedMs': 0},
        ],
      };
    });

    final entries = await TroubleshootingLogBridge().list();
    expect(entries.map((entry) => entry.kind), [
      TroubleshootLogKind.runtime,
      TroubleshootLogKind.crash,
    ]);
    expect(entries.first.sizeLabel, '2.0 KB');
    expect(entries.last.modifiedAt.millisecondsSinceEpoch, 2000);
  });

  test('read 保留正文与截断标记', () async {
    mock((call) async {
      expect(call.method, 'read');
      expect(call.arguments, {'kind': 'crash', 'name': 'crash-1.log'});
      return {'content': 'stack trace', 'truncated': true};
    });

    final result = await TroubleshootingLogBridge().read(_crashEntry);
    expect(result.content, 'stack trace');
    expect(result.truncated, isTrue);
  });

  test('delete 与 share 转发 kind 和 name', () async {
    final calls = <String>[];
    mock((call) async {
      calls.add(call.method);
      expect(call.arguments, {'kind': 'runtime', 'name': 'runtime.log'});
      return true;
    });

    final bridge = TroubleshootingLogBridge();
    expect(await bridge.delete(_runtimeEntry), isTrue);
    expect(await bridge.share(_runtimeEntry), isTrue);
    expect(calls, ['delete', 'share']);
  });

  test('shareAll 返回原生结果', () async {
    mock((call) async {
      expect(call.method, 'shareAll');
      return false;
    });
    expect(await TroubleshootingLogBridge().shareAll(), isFalse);
  });

  test('clearAll 读取两类计数', () async {
    mock((call) async {
      expect(call.method, 'clearAll');
      return {'runtime': 3, 'crash': 2};
    });

    final result = await TroubleshootingLogBridge().clearAll();
    expect(result.runtime, 3);
    expect(result.crash, 2);
    expect(result.total, 5);
  });

  test('没有原生实现时安全降级', () async {
    final bridge = TroubleshootingLogBridge();
    expect(await bridge.list(), isEmpty);
    expect((await bridge.read(_crashEntry)).content, isNull);
    expect(await bridge.delete(_runtimeEntry), isFalse);
    expect(await bridge.shareAll(), isFalse);
    expect((await bridge.clearAll()).total, 0);
  });
}

final _runtimeEntry = TroubleshootLogEntry(
  kind: TroubleshootLogKind.runtime,
  name: 'runtime.log',
  sizeBytes: 1,
  modifiedAt: DateTime(2026),
);

final _crashEntry = TroubleshootLogEntry(
  kind: TroubleshootLogKind.crash,
  name: 'crash-1.log',
  sizeBytes: 1,
  modifiedAt: DateTime(2026),
);
