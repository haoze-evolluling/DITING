// The Flutter web bundle is built into the Go service's embedded assets. These guards keep the
// wiring from silently drifting: the script must point at the desktop entry and the service must
// still embed `frontend/dist`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final server = _serverDirectory();

  test('构建脚本把桌面入口输出到 frontend/dist', () {
    final file = File('${server.path}/build_frontend.py');
    expect(file.existsSync(), isTrue);
    final source = file.readAsStringSync();
    expect(source, contains('lib/main.dart'));
    expect(source, contains('"frontend" / "dist"'));
    expect(source, contains('flutter'));
  });

  test('Go 服务仍嵌入 frontend/dist', () {
    final embed = File('${server.path}/frontend/embed.go');
    expect(embed.existsSync(), isTrue);
    expect(embed.readAsStringSync(), contains('//go:embed all:dist'));
  });
}

/// Tests run with the Flutter app as the working directory, but `flutter test` may be launched from
/// the repository root too, so walk up until the Server project is found.
Directory _serverDirectory() {
  var directory = Directory.current;
  for (var depth = 0; depth < 4; depth++) {
    final candidate = Directory('${directory.path}/Server');
    if (File('${candidate.path}/frontend/embed.go').existsSync()) return candidate;
    final nested = Directory('${directory.path}/../Server');
    if (File('${nested.path}/frontend/embed.go').existsSync()) return nested;
    directory = directory.parent;
  }
  throw StateError('找不到 Server/frontend/embed.go');
}
