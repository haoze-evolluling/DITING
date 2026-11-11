import 'dart:io';

const hdr =
    '// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.';

class Member {
  Member(
    this.name,
    this.isPublic,
    this.isFn,
    this.ret,
    this.params,
    this.declAt,
    this.lines,
  );
  final String name;
  final bool isPublic;
  final bool isFn;
  final String ret;
  final String params;
  final int declAt;
  List<String> lines;
}

final reStatic = RegExp(r'^  static ');
final reFn = RegExp(
  r'^  static ([A-Za-z<>?,\[\] ]+ )([a-zA-Z_][a-zA-Z0-9_]*)\(',
);
final reConst = RegExp(r'^  static (const|final) ([a-zA-Z_][a-zA-Z0-9_]*) =');
final reTailIdent = RegExp(r'([a-zA-Z_][a-zA-Z0-9_]*)$');

void main() {
  final src = File('lib/ui/icons/app_glyphs.dart').readAsLinesSync();
  final clsOpen = src.indexWhere(
    (l) => l.startsWith('abstract final class AppGlyphs'),
  );
  final clsClose = src.lastIndexWhere((l) => l == '}');

  final starts = <int>[];
  for (var i = clsOpen + 1; i < clsClose; i++) {
    if (!reStatic.hasMatch(src[i])) continue;
    var b = i;
    while (b - 1 > clsOpen) {
      final p = src[b - 1];
      if (p.trimLeft().startsWith('///')) {
        b--;
        continue;
      }
      if (p.trim().isEmpty &&
          b - 2 > clsOpen &&
          src[b - 2].trimLeft().startsWith('///')) {
        b--;
        continue;
      }
      break;
    }
    starts.add(b);
  }

  final members = <Member>[];
  for (var i = 0; i < starts.length; i++) {
    final beg = starts[i];
    final end = i + 1 < starts.length ? starts[i + 1] - 1 : clsClose - 1;
    final block = src.sublist(beg, end + 1);
    final di = block.indexWhere((l) => reStatic.hasMatch(l));
    final decl = block[di];
    final mFn = reFn.firstMatch(decl);
    final mC = reConst.firstMatch(decl);
    if (mFn != null) {
      final name = mFn.group(2)!;
      final open = decl.indexOf('(', decl.indexOf(name) + name.length);
      final close = _matchParen(decl, open);
      members.add(
        Member(
          name,
          !name.startsWith('_'),
          true,
          mFn.group(1)!.trim(),
          decl.substring(open + 1, close),
          di,
          block,
        ),
      );
    } else if (mC != null) {
      final name = mC.group(2)!;
      members.add(
        Member(name, !name.startsWith('_'), false, '', '', di, block),
      );
    } else {
      stderr.writeln('UNCLASSIFIED: $decl');
      exitCode = 3;
      return;
    }
  }

  final allNames = members.map((m) => m.name).toSet().toList()
    ..sort((a, b) => b.length - a.length);
  final renamePat = RegExp(r'\b(' + allNames.join('|') + r')\b');
  String gname(String n) => '_g_${n}_';

  for (final m in members) {
    final out = <String>[];
    for (var k = 0; k < m.lines.length; k++) {
      final l = m.lines[k];
      final String text;
      if (k == m.declAt) {
        if (m.isFn) {
          final open = l.indexOf('(', l.indexOf(m.name) + m.name.length);
          final close = _matchParen(l, open);
          text =
              '${m.ret} ${gname(m.name)}${l.substring(open, close + 1)}'
              '${l.substring(close + 1)}';
        } else {
          text = 'const ${gname(m.name)} =${l.substring(l.indexOf('=') + 1)}';
        }
      } else {
        text = l.length >= 2 && l.startsWith('  ') ? l.substring(2) : l;
      }
      out.add(text.replaceAllMapped(renamePat, (mm) => gname(mm[1]!)));
    }
    m.lines = out;
  }

  final buckets = <List<Member>>[[]];
  var acc = 0;
  for (final m in members) {
    if (acc + m.lines.length > 500 && buckets.last.isNotEmpty) {
      buckets.add([]);
      acc = 0;
    }
    buckets.last.add(m);
    acc += m.lines.length + 1;
  }
  final partNames = <String>[];
  for (var bi = 0; bi < buckets.length; bi++) {
    final pname = 'app_glyphs_${String.fromCharCode(0x62 + bi)}.dart';
    partNames.add(pname);
    final sb = StringBuffer("$hdr\n\npart of 'app_glyphs.dart';\n\n");
    for (final m in buckets[bi]) {
      sb.writeln(m.lines.join('\n'));
      sb.writeln();
    }
    File('lib/ui/icons/$pname')
        .writeAsStringSync(sb.toString().trimRight() + '\n');
  }

  final main = StringBuffer();
  main.writeln(src.sublist(0, clsOpen).join('\n'));
  for (final p in partNames) {
    main.writeln("part '$p';");
  }
  main.writeln();
  main.writeln(src[clsOpen]);
  main.writeln('  // 按项目单文件 ≤550 行规范，字形数据定义拆分至下方各 part 文件');
  main.writeln('  // （顶层私有常量/函数）；以下转发保持 `AppGlyphs.xxx` 调用点不变。');
  for (final m in members.where((m) => m.isPublic)) {
    if (m.isFn) {
      main.writeln(
        '  static ${m.ret} ${m.name}(${m.params}) '
        '=> ${gname(m.name)}(${_args(m.params)});',
      );
    } else {
      main.writeln('  static const ${m.name} = ${gname(m.name)};');
    }
  }
  main.writeln('}');
  File('lib/ui/icons/app_glyphs.dart').writeAsStringSync(main.toString());
  print(
    'main=${main.toString().split('\n').length} lines, parts='
    '${partNames.map((p) => File('lib/ui/icons/$p').readAsLinesSync().length).toList()}',
  );
}

int _matchParen(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == '(') depth++;
    if (s[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return s.length - 1;
}

String _args(String params) {
  if (params.trim().isEmpty) return '';
  final chunks = <String>[];
  var depth = 0;
  var buf = '';
  for (final ch in params.split('')) {
    if (ch == '(' || ch == '[') depth++;
    if (ch == ')' || ch == ']') depth--;
    if (ch == ',' && depth == 0) {
      chunks.add(buf);
      buf = '';
    } else {
      buf += ch;
    }
  }
  if (buf.trim().isNotEmpty) chunks.add(buf);
  return chunks
      .map((p) {
        var t = p.trim();
        final eq = t.indexOf('=');
        if (eq > 0) t = t.substring(0, eq);
        t = t
            .replaceAll('required', '')
            .replaceAll('{', '')
            .replaceAll('}', '')
            .trim();
        return reTailIdent.firstMatch(t)!.group(1)!;
      })
      .join(', ');
}
