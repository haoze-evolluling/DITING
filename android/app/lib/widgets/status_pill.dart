import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A short status label in a pill: tinted fill, emphasized caption, one line.
///
/// Five page-local copies (`_StatusPill`, `_LatencyBadge`, `_Pill`, the IP-quality level badge and
/// its type badge) drew this by hand and disagreed on the padding — 10/4, 10/5, 10/6, 12/4 — so the
/// same-looking label sat at four different heights. The padding and type size stay parameters
/// because each page still has its own density, but the shape, the one-line ellipsis and the
/// colour pairing are settled here.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.foregroundColor,
    this.alpha,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.style = AppTextStyle.caption1,
    this.emphasized = true,
    this.monospace = false,
    this.leading,
    this.leadingSize = 14,
  });

  final String label;

  /// Fill colour; with [alpha] it is the tint, otherwise the pill is drawn solid.
  final Color color;

  /// Text colour; defaults to [color], which only reads well on a tint.
  final Color? foregroundColor;

  /// Tint strength, e.g. 0.12 for a status word. `null` fills with [color] at full opacity.
  final double? alpha;

  final EdgeInsets padding;
  final AppTextStyle style;
  final bool emphasized;

  /// Numerals read better monospaced, e.g. a latency figure.
  final bool monospace;

  /// An optional glyph before the label, e.g. a record type.
  final Glyph? leading;
  final double leadingSize;

  @override
  Widget build(BuildContext context) {
    final fore = foregroundColor ?? color;
    final alpha = this.alpha;
    final label = Text(
      this.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style
          .of(context, emphasized: emphasized)
          .copyWith(
            color: fore,
            fontFamily: monospace ? appMonospaceFontFamily : null,
          ),
    );
    final leading = this.leading;
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: alpha == null ? color : color.withValues(alpha: alpha),
        shape: AppShape.full,
      ),
      child: leading == null
          ? label
          : Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                GlyphIcon(leading, size: leadingSize, color: fore),
                label,
              ],
            ),
    );
  }
}
