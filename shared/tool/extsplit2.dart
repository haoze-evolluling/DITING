import 'dart:io';

const hdr =
    '// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.';
void main(List<String> args) {
  final file = args[0];
  final cls = args[1];
  final pname = args[2];
  final start = int.parse(args[3]);
  final end = int.parse(args[4]);
  final lines = File(file).readAsLinesSync();
  final root = RegExp("part of '([^']+)'")
      .firstMatch(lines.join('\n'))!
      .group(1)!;
  final moved = lines.sublist(start - 1, end);
  final rest = [...lines.sublist(0, start - 1), ...lines.sublist(end)];
  File(file).writeAsStringSync(rest.join('\n').trimRight() + '\n');
  final dir = file.substring(0, file.lastIndexOf('/') + 1);
  final newFile = '$dir$pname';
  if (File(newFile).existsSync()) {
    stderr.writeln('REFUSING TO OVERWRITE $newFile');
    exitCode = 2;
    return;
  }
  final body = moved
      .map((l) => l.length >= 2 && l.startsWith('  ') ? l.substring(2) : l)
      .join('\n');
  File(newFile).writeAsStringSync(
    '$hdr\n\npart of \'$root\';\n\n'
    '// 按项目单文件 ≤550 行规范，从 $cls 拆出的构建方法（同库扩展，私有成员经库级可见性直接访问）。\n'
    'extension ${cls}Build on $cls {\n$body\n}\n',
  );
  // register after the last import/export/part/library directive of the root
  final rootPath = '$dir$root';
  final rlines = File(rootPath).readAsLinesSync();
  var at = 0;
  for (var i = 0; i < rlines.length; i++) {
    final t = rlines[i].trim();
    if (t.startsWith('import ') ||
        t.startsWith('export ') ||
        t.startsWith('part ') ||
        t.startsWith('library ')) {
      if (t.startsWith('part of')) continue;
      at = i + 1;
    }
  }
  rlines.insert(at, "part '$pname';");
  File(rootPath).writeAsStringSync(rlines.join('\n').trimRight() + '\n');
  print(
    '$file -> $pname (root $root) ; class-file=${rest.length} ext=${moved.length + 6}',
  );
}
