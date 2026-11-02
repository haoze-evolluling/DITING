import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A glyph on a rounded tile: the leading mark of a hero card, a mode option or a dashboard stat.
///
/// The callers differ in side, corner and fill, not in structure, so those are parameters. [shape]
/// takes [AppShape.circle] for the round variant; the square one is [AppShape.md] at [size] 44,
/// which is the size most pages use.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.glyph,
    required this.color,
    this.foregroundColor,
    this.size = 44,
    this.glyphSize = 22,
    this.shape = AppShape.md,
  });

  final Glyph glyph;

  /// Tile fill.
  final Color color;

  /// Glyph colour; `null` keeps the ambient `IconTheme`, which is what a card's leading mark wants.
  final Color? foregroundColor;

  final double size;
  final double glyphSize;
  final OutlinedBorder shape;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: color, shape: shape),
      child: GlyphIcon(glyph, size: glyphSize, color: foregroundColor),
    );
  }
}
