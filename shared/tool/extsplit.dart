import 'dart:io';

const hdr =
    '// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.';

// Moves [start,end] (1-based, inclusive, method-level ranges inside a class
// body) out of `file` into a new part file as an extension on `cls`.
void extract(String file, String cls, String pname, int start, int end) {
  final lines = File(file).readAsLinesSync();
  final moved = lines.sublist(start - 1, end);
  final rest = [...lines.sublist(0, start - 1), ...lines.sublist(end)];
  // register the part after existing part directives
  var at = 0;
  for (var i = 0; i < rest.length; i++) {
    final t = rest[i].trim();
    if (t.startsWith('import ') ||
        t.startsWith('part ') ||
        t.startsWith('export ')) {
      at = i + 1;
    }
  }
  rest.insert(at, "part '$pname';");
  File(file).writeAsStringSync(rest.join('\n').trimRight() + '\n');
  final body = moved
      .map((l) => l.length >= 2 && l.startsWith('  ') ? l.substring(2) : l)
      .join('\n');
  File('${file.substring(0, file.lastIndexOf('/'))}/$pname').writeAsStringSync(
    '$hdr\n\npart of \'${file.split('/').last}\';\n\n'
    '// 按项目单文件 ≤550 行规范，从 $cls 拆出的构建方法（同库扩展，\n'
    '// 私有成员经库级可见性直接访问，语义与类内方法完全一致）。\n'
    'extension ${cls}Build on $cls {\n$body\n}\n',
  );
  print('$file -> $pname ; main=${rest.length} part=${moved.length + 5}');
}

void main() {
  extract(
    'lib/ui/scaffold_a.dart',
    'CommonScaffoldState',
    'scaffold_d.dart',
    203,
    616,
  );
  extract(
    'lib/ui/popup_f.dart',
    '_CommonPopupMenuState',
    'popup_g.dart',
    408,
    685,
  );
}
