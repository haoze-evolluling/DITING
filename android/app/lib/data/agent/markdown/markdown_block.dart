library;

sealed class MarkdownBlock {
  const MarkdownBlock();
}

class MarkdownHeading extends MarkdownBlock {
  const MarkdownHeading(this.level, this.text);

  final int level;
  final String text;
}

class MarkdownParagraph extends MarkdownBlock {
  const MarkdownParagraph(this.text);

  final String text;
}

class MarkdownBulletItem extends MarkdownBlock {
  const MarkdownBulletItem(this.indent, this.text);

  final int indent;
  final String text;
}

class MarkdownNumberedItem extends MarkdownBlock {
  const MarkdownNumberedItem(this.number, this.text);

  final String number;
  final String text;
}

class MarkdownCodeBlock extends MarkdownBlock {
  const MarkdownCodeBlock(this.language, this.code);

  final String language;
  final String code;
}

class MarkdownBlockquote extends MarkdownBlock {
  const MarkdownBlockquote(this.text);

  final String text;
}

class MarkdownDivider extends MarkdownBlock {
  const MarkdownDivider();
}

class MarkdownTable extends MarkdownBlock {
  const MarkdownTable(this.headers, this.rows);

  final List<String> headers;
  final List<List<String>> rows;
}

final _hrRegex = RegExp(r'^(?:-{3,}|\*{3,}|_{3,})$');
final _headingRegex = RegExp(r'^(#{1,6})\s+(.+)$');
final _bulletRegex = RegExp(r'^(\s*)([-*+])\s+(.+)$');
final _numberedRegex = RegExp(r'^(\s*)(\d+)\.\s+(.+)$');
final _tableSeparatorCellRegex = RegExp(r'^:?-+:?$');

bool _isTableStart(List<String> lines, int index) {
  if (index + 1 >= lines.length) return false;
  final current = lines[index].trim();
  final next = lines[index + 1].trim();
  if (!current.startsWith('|') || !current.endsWith('|')) return false;
  if (!next.startsWith('|') || !next.endsWith('|')) return false;
  final cells = next
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty);
  return cells.isNotEmpty && cells.every(_tableSeparatorCellRegex.hasMatch);
}

bool _startsBlock(List<String> lines, int index) {
  final line = lines[index];
  final trimmed = line.trim();
  return trimmed.isEmpty ||
      trimmed.startsWith('```') ||
      trimmed.startsWith('~~~') ||
      _hrRegex.hasMatch(trimmed) ||
      _headingRegex.hasMatch(trimmed) ||
      trimmed.startsWith('>') ||
      _bulletRegex.hasMatch(line) ||
      _numberedRegex.hasMatch(line) ||
      _isTableStart(lines, index);
}

List<MarkdownBlock> parseMarkdownBlocks(String rawText) {
  final lines = rawText.split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;
  final n = lines.length;

  while (i < n) {
    final line = lines[i];
    final trimmed = line.trim();

    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      final delimiter = trimmed.startsWith('```') ? '```' : '~~~';
      final language = trimmed.replaceFirst(delimiter, '').trim();
      final codeLines = <String>[];
      i++;
      while (i < n && !lines[i].trim().startsWith(delimiter)) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < n) i++;
      blocks.add(MarkdownCodeBlock(language, codeLines.join('\n')));
      continue;
    }

    if (_hrRegex.hasMatch(trimmed)) {
      blocks.add(const MarkdownDivider());
      i++;
      continue;
    }

    final heading = _headingRegex.firstMatch(trimmed);
    if (heading != null) {
      blocks.add(
        MarkdownHeading(heading.group(1)!.length, heading.group(2)!.trim()),
      );
      i++;
      continue;
    }

    if (trimmed.startsWith('>')) {
      final quoteLines = <String>[];
      while (i < n && lines[i].trim().startsWith('>')) {
        quoteLines.add(lines[i].trim().replaceFirst('>', '').trim());
        i++;
      }
      blocks.add(MarkdownBlockquote(quoteLines.join('\n')));
      continue;
    }

    if (_isTableStart(lines, i)) {
      final headers = _tableCells(trimmed);
      i += 2;
      final rows = <List<String>>[];
      while (i < n &&
          lines[i].trim().startsWith('|') &&
          lines[i].trim().endsWith('|')) {
        rows.add(_tableCells(lines[i].trim()));
        i++;
      }
      blocks.add(MarkdownTable(headers, rows));
      continue;
    }

    final bullet = _bulletRegex.firstMatch(line);
    if (bullet != null) {
      final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 4);
      blocks.add(MarkdownBulletItem(indent, bullet.group(3)!.trim()));
      i++;
      continue;
    }

    final numbered = _numberedRegex.firstMatch(line);
    if (numbered != null) {
      blocks.add(
        MarkdownNumberedItem(
          '${numbered.group(2)}.',
          numbered.group(3)!.trim(),
        ),
      );
      i++;
      continue;
    }

    final paragraphLines = <String>[];
    while (i < n && !_startsBlock(lines, i)) {
      paragraphLines.add(lines[i].trim());
      i++;
    }
    if (paragraphLines.isNotEmpty) {
      blocks.add(MarkdownParagraph(paragraphLines.join('\n')));
    } else {
      i++;
    }
  }
  return blocks;
}

List<String> _tableCells(String row) {
  final cells = row.split('|').map((cell) => cell.trim()).toList();
  if (cells.length < 2) return cells;
  return cells.sublist(1, cells.length - 1);
}
