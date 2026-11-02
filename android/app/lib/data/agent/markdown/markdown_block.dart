/// Minimal Markdown block parser for model output. Ported from the 1.4.x Kotlin `MarkdownBlock`:
/// same regexes and same order, so a report renders the same in both apps. A full Markdown package
/// would be a new dependency for one screen; the reports only ever use these eight shapes.
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

  /// Nesting level, 0-4; the renderer turns it into a left inset.
  final int indent;
  final String text;
}

class MarkdownNumberedItem extends MarkdownBlock {
  const MarkdownNumberedItem(this.number, this.text);

  /// Includes the trailing dot, e.g. `3.`.
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
  // Trim first: the separator regex is anchored, so ` --- ` would otherwise not match.
  final cells = next
      .split('|')
      .map((cell) => cell.trim())
      .where((cell) => cell.isNotEmpty);
  return cells.isNotEmpty && cells.every(_tableSeparatorCellRegex.hasMatch);
}

/// Splits raw model output into blocks. Never throws: anything unrecognised becomes a paragraph.
List<MarkdownBlock> parseMarkdownBlocks(String rawText) {
  final lines = rawText.split('\n');
  final blocks = <MarkdownBlock>[];
  var i = 0;
  final n = lines.length;

  while (i < n) {
    final line = lines[i];
    final trimmed = line.trim();

    // 1. Blank line: no block, just advance.
    if (trimmed.isEmpty) {
      i++;
      continue;
    }

    // 2. Fenced code block (``` or ~~~), closed by the same delimiter.
    if (trimmed.startsWith('```') || trimmed.startsWith('~~~')) {
      final delimiter = trimmed.startsWith('```') ? '```' : '~~~';
      final language = trimmed.replaceFirst(delimiter, '').trim();
      final codeLines = <String>[];
      i++;
      while (i < n && !lines[i].trim().startsWith(delimiter)) {
        codeLines.add(lines[i]);
        i++;
      }
      if (i < n) i++; // Skip the closing delimiter.
      blocks.add(MarkdownCodeBlock(language, codeLines.join('\n')));
      continue;
    }

    // 3. Horizontal rule.
    if (_hrRegex.hasMatch(trimmed)) {
      blocks.add(const MarkdownDivider());
      i++;
      continue;
    }

    // 4. Heading.
    final heading = _headingRegex.firstMatch(trimmed);
    if (heading != null) {
      blocks.add(
        MarkdownHeading(heading.group(1)!.length, heading.group(2)!.trim()),
      );
      i++;
      continue;
    }

    // 5. Blockquote: consecutive `>` lines become one block.
    if (trimmed.startsWith('>')) {
      final quoteLines = <String>[];
      while (i < n && lines[i].trim().startsWith('>')) {
        quoteLines.add(lines[i].trim().replaceFirst('>', '').trim());
        i++;
      }
      blocks.add(MarkdownBlockquote(quoteLines.join('\n')));
      continue;
    }

    // 6. Table: only when the next line is a separator row, otherwise `a | b` stays a paragraph.
    if (_isTableStart(lines, i)) {
      final headers = _tableCells(trimmed);
      i += 2; // Header and separator.
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

    // 7. Unordered list item.
    final bullet = _bulletRegex.firstMatch(line);
    if (bullet != null) {
      final indent = (bullet.group(1)!.length ~/ 2).clamp(0, 4);
      blocks.add(MarkdownBulletItem(indent, bullet.group(3)!.trim()));
      i++;
      continue;
    }

    // 8. Ordered list item.
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

    // 9. Paragraph: swallow everything up to the next block boundary.
    final paragraphLines = <String>[];
    while (i < n) {
      final currentLine = lines[i];
      final currentTrimmed = currentLine.trim();
      if (currentTrimmed.isEmpty) break;
      if (currentTrimmed.startsWith('```') ||
          currentTrimmed.startsWith('~~~')) {
        break;
      }
      if (_hrRegex.hasMatch(currentTrimmed)) break;
      if (_headingRegex.hasMatch(currentTrimmed)) break;
      if (currentTrimmed.startsWith('>')) break;
      if (_bulletRegex.hasMatch(currentLine)) break;
      if (_numberedRegex.hasMatch(currentLine)) break;
      if (_isTableStart(lines, i)) break;

      paragraphLines.add(currentTrimmed);
      i++;
    }
    if (paragraphLines.isNotEmpty) {
      blocks.add(MarkdownParagraph(paragraphLines.join('\n')));
    } else {
      // Nothing consumed: step forward so an unexpected line cannot loop forever.
      i++;
    }
  }
  return blocks;
}

/// `| a | b |` → `[a, b]`: drop the empty strings the leading and trailing pipes produce.
List<String> _tableCells(String row) {
  final cells = row.split('|').map((cell) => cell.trim()).toList();
  if (cells.length < 2) return cells;
  return cells.sublist(1, cells.length - 1);
}
