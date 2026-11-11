import 'dart:io';

const hdr =
    '// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.';

// Re-splits a library root file into part files by explicit 1-based top-level
// chunk ranges (everything not covered stays in the root). Doc comments
// directly above a chunk start move with the chunk.
void main(List<String> args) {
  final file = args[0]; // e.g. lib/ui/popup.dart
  final chunks = <List<int>>[];
  for (var i = 1; i < args.length; i += 2) {
    chunks.add([int.parse(args[i]), int.parse(args[i + 1])]);
  }
  final lines = File(file).readAsLinesSync();
  final base = file.substring(file.lastIndexOf('/') + 1);
  final dir = file.substring(0, file.lastIndexOf('/'));
  final stem = base.substring(0, base.length - 5);

  // doc-comment pull-up
  final adj = chunks.map((c) {
    var start = c[0];
    while (start > 2) {
      final prev = lines[start - 2];
      if (prev.trimLeft().startsWith('///') ||
          prev.trimLeft().startsWith('//')) {
        start--;
      } else {
        break;
      }
    }
    return [start, c[1]];
  }).toList();

  final names = <String>[];
  for (var i = 0; i < adj.length; i++) {
    final name = '${stem}_${String.fromCharCode(0x61 + i)}.dart';
    names.add(name);
    final body = lines.sublist(adj[i][0] - 1, adj[i][1]).join('\n').trimRight();
    File('$dir/$name').writeAsStringSync("$hdr\n\npart of '$base';\n\n$body\n");
  }

  final covered = List<bool>.filled(lines.length + 2, false);
  for (final c in adj) {
    for (var i = c[0]; i <= c[1]; i++) covered[i] = true;
  }
  final kept = <String>[];
  for (var i = 1; i <= lines.length; i++) {
    if (!covered[i]) kept.add(lines[i - 1]);
  }
  var insertAt = 0;
  for (var i = 0; i < kept.length; i++) {
    final t = kept[i].trim();
    if (t.startsWith('import ') ||
        t.startsWith('export ') ||
        t.startsWith('part ') ||
        t.startsWith('library ')) {
      insertAt = i + 1;
    }
  }
  final rel = names.map((n) => "part '$n';");
  File(file).writeAsStringSync(
    [
          ...kept.sublist(0, insertAt),
          ...rel,
          ...kept.sublist(insertAt),
        ].join('\n').trimRight() +
        '\n',
  );
  print(
    '$base root=${kept.length} parts='
    '${names.map((n) => File('$dir/$n').readAsLinesSync().length).toList()}',
  );
}
