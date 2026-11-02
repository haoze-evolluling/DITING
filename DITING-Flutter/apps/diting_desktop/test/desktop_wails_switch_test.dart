// The Windows window now embeds the Flutter rebuild instead of the Vue console. These guards keep
// the build wiring from silently drifting back: Wails must call the Flutter script, the script must
// point at the desktop entry, and the host must still embed `frontend/dist`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final desktop = _desktopDirectory();

  test('wails.json 的前端构建指向 Flutter 脚本', () {
    final file = File('${desktop.path}/wails.json');
    expect(file.existsSync(), isTrue);
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    // Wails runs frontend commands with `Desktop/frontend` as the working directory.
    expect(json['frontend:build'], 'python ../build_frontend.py');
    expect('${json['frontend:install']}', contains('--deps-only'));
    expect(json.containsKey('frontend:dev:watcher'), isFalse);
  });

  test('构建脚本把桌面入口输出到 frontend/dist', () {
    final file = File('${desktop.path}/build_frontend.py');
    expect(file.existsSync(), isTrue);
    final source = file.readAsStringSync();
    expect(source, contains('lib/main.dart'));
    expect(source, contains('"frontend" / "dist"'));
    expect(source, contains('flutter'));
  });

  test('Wails 宿主仍嵌入 frontend/dist', () {
    final embed = File('${desktop.path}/frontend/embed.go');
    expect(embed.existsSync(), isTrue);
    expect(embed.readAsStringSync(), contains('//go:embed all:dist'));
  });
}

/// Tests run with the Flutter app as the working directory, but `flutter test` may be launched from
/// the repository root too, so walk up until the Wails project is found.
Directory _desktopDirectory() {
  var directory = Directory.current;
  for (var depth = 0; depth < 4; depth++) {
    final candidate = Directory('${directory.path}/Desktop');
    if (File('${candidate.path}/wails.json').existsSync()) return candidate;
    final nested = Directory('${directory.path}/../Desktop');
    if (File('${nested.path}/wails.json').existsSync()) return nested;
    directory = directory.parent;
  }
  throw StateError('找不到 Desktop/wails.json');
}
