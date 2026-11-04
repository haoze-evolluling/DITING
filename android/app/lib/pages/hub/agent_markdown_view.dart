/// Renders a model report: the Markdown blocks from `markdown_block.dart` plus the inline styling
/// from `markdown_inline.dart`. Visually mirrors the 1.4.x `MarkdownViewer` so a report looks the
/// same as it did in the Kotlin app — a coloured bar on section headings, primary-coloured bullets,
/// framed code blocks and a card-wrapped table.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/agent/markdown/markdown_block.dart';
import 'package:diting_android/data/agent/markdown/markdown_inline.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

class AgentMarkdownView extends StatelessWidget {
  const AgentMarkdownView({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final colors = MarkdownColors(
      base: colorScheme.onSurface,
      primary: colorScheme.primary,
      codeBackground: colorScheme.surfaceContainerHighest,
      error: colorScheme.error,
      tertiary: colorScheme.tertiary,
    );
    final blocks = parseMarkdownBlocks(markdown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [for (final block in blocks) _blockOf(context, block, colors)],
    );
  }

  Widget _blockOf(
    BuildContext context,
    MarkdownBlock block,
    MarkdownColors colors,
  ) {
    final colorScheme = context.colorScheme;
    switch (block) {
      case MarkdownHeading(:final level, :final text):
        return _Heading(level: level, text: text, colors: colors);
      case MarkdownParagraph(:final text):
        return _Rich(
          text: text,
          colors: colors,
          style: AppTextStyle.body.of(context).copyWith(height: 1.45),
        );
      case MarkdownBulletItem(:final indent, :final text):
        return Padding(
          padding: EdgeInsets.only(left: indent * 14.0 + 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Padding(
                // Optically centres the 5dp dot on the first text line.
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(
                child: _Rich(
                  text: text,
                  colors: colors,
                  style: AppTextStyle.body.of(context).copyWith(height: 1.45),
                ),
              ),
            ],
          ),
        );
      case MarkdownNumberedItem(:final number, :final text):
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              number,
              style: AppTextStyle.body
                  .of(context)
                  .copyWith(color: colors.primary, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: _Rich(
                text: text,
                colors: colors,
                style: AppTextStyle.body.of(context).copyWith(height: 1.45),
              ),
            ),
          ],
        );
      case MarkdownCodeBlock(:final language, :final code):
        return _CodeBlock(language: language, code: code, colors: colors);
      case MarkdownBlockquote(:final text):
        return Container(
          padding: const EdgeInsets.only(left: 10),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.primary, width: 4)),
          ),
          child: _Rich(
            text: text,
            colors: colors,
            style: AppTextStyle.body
                .of(context)
                .copyWith(
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        );
      case MarkdownDivider():
        return Divider(height: 20, color: colorScheme.outlineVariant);
      case MarkdownTable(:final headers, :final rows):
        return _Table(headers: headers, rows: rows, colors: colors);
    }
  }
}

class _Rich extends StatelessWidget {
  const _Rich({required this.text, required this.colors, this.style});

  final String text;
  final MarkdownColors colors;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return SelectableText.rich(
      TextSpan(children: buildMarkdownInlineSpans(text, colors), style: style),
      style: style,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.level,
    required this.text,
    required this.colors,
  });

  final int level;
  final String text;
  final MarkdownColors colors;

  @override
  Widget build(BuildContext context) {
    final style = switch (level) {
      1 => AppTextStyle.title2.of(context, emphasized: true),
      2 => AppTextStyle.title3.of(context, emphasized: true),
      3 => AppTextStyle.headline.of(context),
      _ => AppTextStyle.callout.of(context, emphasized: true),
    }.copyWith(color: level <= 3 ? colors.primary : colors.base);

    final label = SelectableText.rich(
      TextSpan(children: buildMarkdownInlineSpans(text, colors), style: style),
      style: style,
    );

    return Padding(
      // Headings need air above them; the first one is already spaced by the Column.
      padding: EdgeInsets.only(top: level <= 2 ? 10 : 4),
      child: level == 2
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                // 3.5 x 18 bar, as in the Kotlin viewer.
                Container(
                  width: 3.5,
                  height: 18,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(child: label),
              ],
            )
          : label,
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({
    required this.language,
    required this.code,
    required this.colors,
  });

  final String language;
  final String code;
  final MarkdownColors colors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.codeBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'CODE' : language.toUpperCase(),
                    style: AppTextStyle.caption2
                        .of(context)
                        .copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.markdownCopyCode,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(SnackBar(content: Text(context.l10n.markdownCodeCopied)));
                  },
                  icon: const GlyphIcon(AppGlyphs.copy, size: 16),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(
                    fontFeatures: appTabularFigures,
                    height: 1.5,
                    color: colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.headers,
    required this.rows,
    required this.colors,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final MarkdownColors colors;

  static const _columnWidth = 90.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final cellStyle = AppTextStyle.footnote.of(context).copyWith(height: 1.35);
    final headerStyle = cellStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onPrimaryContainer,
    );

    TableRow rowOf(List<String> cells, {required bool header, int index = 0}) {
      return TableRow(
        decoration: header
            ? BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              )
            : index.isOdd
            ? BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
              )
            : null,
        children: [
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: header
                  ? Text(cell, style: headerStyle)
                  : Text(cell, style: cellStyle),
            ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: headers.length * _columnWidth),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              if (headers.isNotEmpty) rowOf(headers, header: true),
              for (final (index, row) in rows.indexed)
                rowOf(row, header: false, index: index),
            ],
          ),
        ),
      ),
    );
  }
}
