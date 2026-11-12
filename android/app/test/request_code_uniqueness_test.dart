// Guard: every ActivityResult request code must be unique. The custom-background picker once
// reused PlatformBridge's text-file code (0x5703); because MainActivity dispatches PlatformBridge
// before BackgroundBridge, it claimed the image result and BackgroundBridge's request hung forever.
// This scans the Android bridges that launch activity results and fails if any two share a code.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locates the Kotlin main source directory relative to the Flutter package working directory.
Directory _kotlinDir() {
  for (final candidate in <String>[
    'android/app/src/main/kotlin',
    '../android/app/src/main/kotlin',
  ]) {
    final dir = Directory(candidate);
    if (dir.existsSync()) {
      return dir;
    }
  }
  fail('找不到 android/app/src/main/kotlin（当前目录：${Directory.current.path}）');
}

final _requestCode = RegExp(r'REQUEST_[A-Z0-9_]+\s*=\s*(0x[0-9A-Fa-f]+)');

void main() {
  test('ActivityResult 请求码在各桥之间唯一', () {
    final root = _kotlinDir();
    final byValue = <int, List<String>>{};
    var found = 0;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.kt')) {
        continue;
      }
      final source = entity.readAsStringSync();
      // Only bridges that actually launch an activity-result round trip own such codes.
      if (!source.contains('startActivityForResult(')) {
        continue;
      }
      final fileName = entity.path.split(Platform.pathSeparator).last;
      for (final line in source.split('\n')) {
        final match = _requestCode.firstMatch(line);
        if (match == null) {
          continue;
        }
        final value = int.parse(match.group(1)!.substring(2), radix: 16);
        byValue.putIfAbsent(value, () => <String>[]).add('$fileName: ${line.trim()}');
        found++;
      }
    }
    expect(
      found,
      greaterThanOrEqualTo(10),
      reason: '没有解析到足够的请求码，正则或目录可能失配',
    );
    final duplicates = byValue.entries.where((entry) => entry.value.length > 1);
    expect(
      duplicates,
      isEmpty,
      reason: '请求码重复会互相吞掉 onActivityResult：\n'
          '${duplicates.map((e) => '0x${e.key.toRadixString(16)} → ${e.value.join(' | ')}').join('\n')}',
    );
  });
}
