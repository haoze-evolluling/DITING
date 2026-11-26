library;

import 'package:diting_android/ui/font.dart';
import 'package:material_ui/material_ui.dart';

class MarkdownColors {
  const MarkdownColors({
    required this.base,
    required this.primary,
    required this.codeBackground,
    required this.error,
    required this.tertiary,
  });

  final Color base;
  final Color primary;
  final Color codeBackground;
  final Color error;
  final Color tertiary;
}

final _inlineTokenRegex = RegExp(
  r'(\*\*\*[\s\S]+?\*\*\*|___[\s\S]+?___|\*\*[\s\S]+?\*\*|__[\s\S]+?__|~~[\s\S]+?~~|'
  r'`[^`\n]+`|\[([^\]]+)\]\(([^)]+)\)|'
  r'(?<!\*)\*(?!\*)[\s\S]+?(?<!\*)\*(?!\*)|'
  r'(?<![\p{L}\p{N}_])_(?![\s_])[\s\S]+?(?<![\s_])_(?![\p{L}\p{N}_])|'
  r'【(?:高危|高风险可疑|中风险|存在一般隐患|低风险|安全|健康良好|建议正常放行|'
  r'建议加入白名单|建议加入屏蔽规则|建议旁路直连)】)',
  unicode: true,
);

Color? badgeColorOf(String text, MarkdownColors colors) {
  if (text.contains('高危') || text.contains('高风险') || text.contains('屏蔽规则')) {
    return colors.error;
  }
  if (text.contains('中风险') || text.contains('存在一般隐患')) {
    return const Color(0xFFE65100);
  }
  if (text.contains('低风险')) {
    return const Color(0xFFF57F17);
  }
  if (text.contains('安全') || text.contains('健康良好') || text.contains('白名单')) {
    return const Color(0xFF2E7D32);
  }
  if (text.contains('正常放行')) {
    return const Color(0xFF1976D2);
  }
  if (text.contains('旁路直连')) return colors.tertiary;
  return null;
}

List<InlineSpan> buildMarkdownInlineSpans(
  String source,
  MarkdownColors colors,
) {
  final spans = <InlineSpan>[];
  var cursor = 0;

  for (final match in _inlineTokenRegex.allMatches(source)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(
          text: source.substring(cursor, match.start),
          style: TextStyle(color: colors.base),
        ),
      );
    }

    final token = match[0]!;
    spans.add(_spanForToken(token, match, colors));
    cursor = match.end;
  }

  if (cursor < source.length) {
    spans.add(
      TextSpan(
        text: source.substring(cursor),
        style: TextStyle(color: colors.base),
      ),
    );
  }
  return spans;
}

InlineSpan _spanForToken(
  String token,
  RegExpMatch match,
  MarkdownColors colors,
) {
  bool wrapped(String mark, int minLength) =>
      token.startsWith(mark) &&
      token.endsWith(mark) &&
      token.length >= minLength;

  if (wrapped('***', 6) || wrapped('___', 6)) {
    return TextSpan(
      text: token.substring(3, token.length - 3),
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  if (wrapped('**', 4) || wrapped('__', 4)) {
    final inner = token.substring(2, token.length - 2);
    return TextSpan(
      text: inner,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: badgeColorOf(inner, colors) ?? colors.base,
      ),
    );
  }

  if (wrapped('~~', 4)) {
    return TextSpan(
      text: token.substring(2, token.length - 2),
      style: const TextStyle(decoration: TextDecoration.lineThrough),
    );
  }

  if (wrapped('`', 2)) {
    return TextSpan(
      text: ' ${token.substring(1, token.length - 1)} ',
      style: TextStyle(
        fontFeatures: appTabularFigures,
        backgroundColor: colors.codeBackground,
        color: colors.primary,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  final linkLabel = match.group(2);
  if (linkLabel != null) {
    return TextSpan(
      text: linkLabel,
      style: TextStyle(
        color: colors.primary,
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  if (wrapped('*', 2) || wrapped('_', 2)) {
    return TextSpan(
      text: token.substring(1, token.length - 1),
      style: const TextStyle(fontStyle: FontStyle.italic),
    );
  }

  if (token.startsWith('【') && token.endsWith('】')) {
    return TextSpan(
      text: token,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: badgeColorOf(token, colors) ?? colors.primary,
      ),
    );
  }

  return TextSpan(
    text: token,
    style: TextStyle(color: colors.base),
  );
}
