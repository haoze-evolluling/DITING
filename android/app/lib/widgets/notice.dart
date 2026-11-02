import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A tinted inline notice: a glyph and a paragraph on a rounded warning or error fill.
///
/// Used where a card would be too heavy — inside another card, or right under a switch that needs a
/// caveat. The 10-inset / 8-gap / `AppShape.md` geometry was copy-pasted between the developer page
/// and the disclaimer, so it lives here now.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.glyph = AppGlyphs.warning,
    this.color,
    this.foregroundColor,
    this.glyphSize = 16,
    this.padding = const EdgeInsets.all(10),
  });

  final String message;
  final Glyph glyph;

  /// `warningContainer` when omitted, the caveat tone this widget exists for.
  final Color? color;
  final Color? foregroundColor;
  final double glyphSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final background = color ?? colorScheme.warningContainer;
    final foreground = foregroundColor ?? colorScheme.onWarningContainer;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(shape: AppShape.md, color: background),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          GlyphIcon(glyph, size: glyphSize, color: foreground),
          Expanded(
            child: Text(
              message,
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single-line confirmation in a card: what just happened, in the page's own surface.
///
/// Distinct from [InlineNotice], which shouts a caveat; this one stays quiet and carries a
/// successful outcome. The mark doubles as the state: a check for done, an info glyph otherwise.
class CardNoticeRow extends StatelessWidget {
  const CardNoticeRow({
    super.key,
    required this.message,
    this.glyph = AppGlyphs.checkCircle,
    this.color,
    this.glyphSize = 16,
  });

  final String message;
  final Glyph glyph;

  /// Glyph colour; `primary` when omitted.
  final Color? color;
  final double glyphSize;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(
            glyph,
            size: glyphSize,
            color: color ?? context.colorScheme.primary,
          ),
          Expanded(child: Text(message, style: context.listSubtitleStyle)),
        ],
      ),
    );
  }
}
