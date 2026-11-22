import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.glyph,
    required this.color,
    this.foregroundColor,
    this.size = 44,
    this.glyphSize = 22,
    this.shape = AppShape.standard,
  });

  final IconData glyph;

  final Color color;

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
      child: Icon(glyph, size: glyphSize, color: foregroundColor),
    );
  }
}
