// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/measure.dart';
import 'package:material_ui/material_ui.dart';

class TooltipText extends StatelessWidget {
  final Text text;

  const TooltipText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isOverflow = MeasureScope.of(context)
            .computeTextIsOverflow(text, maxWidth: maxWidth);
        if (isOverflow) {
          return Tooltip(
            triggerMode: TooltipTriggerMode.longPress,
            preferBelow: false,
            message: text.data,
            child: text,
          );
        }
        return text;
      },
    );
  }
}

class TooltipLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int maxLines;

  const TooltipLabel(this.text, {super.key, this.style, this.maxLines = 2});

  @override
  Widget build(BuildContext context) {
    return TooltipText(
      text: Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
    );
  }
}

class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const EmojiText(
    this.text, {
    super.key,
    this.maxLines,
    this.overflow,
    this.style,
  });

  /// Emoji need no family of their own any more: the app bundles no fonts, so they resolve through
  /// the platform's colour-emoji fallback like any other glyph. The class stays because the popup
  /// measures labels through [widthOf] before laying them out.
  static TextSpan spanOf(String text, TextStyle? style) =>
      TextSpan(text: text, style: style);

  static double widthOf(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: MediaQuery.boldTextOf(context)
            ? style.merge(const TextStyle(fontWeight: FontWeight.bold))
            : style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    try {
      return painter.maxIntrinsicWidth;
    } finally {
      painter.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
