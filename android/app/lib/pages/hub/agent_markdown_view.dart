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
    final bodyStyle = AppTextRole.bodyReading.of(context);
    switch (block) {
      case MarkdownHeading(:final level, :final text):
        return _Heading(level: level, text: text, colors: colors);
      case MarkdownParagraph(:final text):
        return _Rich(text: text, colors: colors, style: bodyStyle);
      case MarkdownBulletItem(:final indent, :final text):
        return Padding(
          padding: EdgeInsets.only(left: indent * 14.0 + 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Padding(
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
                child: _Rich(text: text, colors: colors, style: bodyStyle),
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
              style: AppTextRole.body
                  .of(context)
                  .copyWith(color: colors.primary, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: _Rich(text: text, colors: colors, style: bodyStyle),
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
            style: bodyStyle.copyWith(
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
  const _Rich({required this.text, required this.colors, required this.style});

  final String text;
  final MarkdownColors colors;
  final TextStyle style;

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
      1 => AppTextRole.sectionTitle.of(context),
      2 => AppTextRole.sectionTitle.of(context),
      3 => AppTextRole.cardTitle.of(context),
      _ => AppTextRole.bodyStrong.of(context),
    }.copyWith(color: level <= 3 ? colors.primary : colors.base);

    final label = SelectableText.rich(
      TextSpan(children: buildMarkdownInlineSpans(text, colors), style: style),
      style: style,
    );

    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 10 : 4),
      child: level == 2
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Container(
                  width: 3.5,
                  height: 18,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: AppRadius.standard,
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
        borderRadius: AppRadius.standard,
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
                    style: AppTextRole.micro
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.markdownCopyCode,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(content: Text(context.l10n.markdownCodeCopied)),
                    );
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
              style: AppTextRole.code
                  .of(context)
                  .copyWith(color: colorScheme.onSurface),
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
    final cellStyle = AppTextRole.legalText.of(context);
    final headerStyle = cellStyle.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onPrimaryContainer,
    );

    TableRow rowOf(List<String> cells, {required bool header, int index = 0}) {
      BoxDecoration? decoration;
      if (header) {
        decoration = BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        );
      } else if (index.isOdd) {
        decoration = BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        );
      }
      return TableRow(
        decoration: decoration,
        children: [
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(cell, style: header ? headerStyle : cellStyle),
            ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.standard,
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
