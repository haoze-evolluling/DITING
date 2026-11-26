import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('生成文件只保留 // ignore 指令', () {
    final l10n = Directory('${_repoRoot().path}/android/app/lib/l10n');
    final generated = l10n
        .listSync()
        .whereType<File>()
        .where((file) => _isGenerated(file.uri.pathSegments.last))
        .toList();
    expect(generated, isNotEmpty);

    final violations = <String>[];
    for (final file in generated) {
      final name = file.uri.pathSegments.last;
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final text = lines[index].trimLeft();
        if (!text.startsWith('//') || text.startsWith('// ignore')) continue;
        violations.add('$name:${index + 1}  $text');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          '生成文件出现了注释，请运行 `python tool/i18n/gen_l10n.py` 重新生成，'
          '不要直接使用 flutter gen-l10n。\n${violations.join('\n')}',
    );
  });
}

bool _isGenerated(String name) =>
    name.startsWith('app_localizations') && name.endsWith('.dart');

Directory _repoRoot() {
  var directory = Directory.current;
  while (!Directory('${directory.path}/.git').existsSync()) {
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Repository root not found from ${Directory.current}');
    }
    directory = parent;
  }
  return directory;
}
