// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
// The last hand-drawn icons: brand marks that Tabler Icons does not ship.
//
// Everything else in the app uses `package:flutter_tabler_icons`. These paths
// are solid 24x24 SVG shapes, parsed once and painted with a single fill.
import 'package:material_ui/material_ui.dart';
import 'package:path_parsing/path_parsing.dart';

const brandGlyphSize = 24.0;

class BrandGlyph {
  const BrandGlyph(this.data, {this.fillType = PathFillType.nonZero});

  final String data;
  final PathFillType fillType;

  static final _built = Expando<Path>();

  Path get path => _built[this] ??= (_parse(data)..fillType = fillType);

  static Path _parse(String data) {
    final writer = _PathWriter();
    writeSvgPathDataToPath(data, writer);
    return writer.path;
  }
}

class _PathWriter implements PathProxy {
  final path = Path();

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void close() => path.close();
}

class BrandGlyphIcon extends StatelessWidget {
  const BrandGlyphIcon(this.glyph, {super.key, this.size, this.color});

  final BrandGlyph glyph;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = this.color ?? iconTheme.color!;
    final opacity = iconTheme.opacity ?? 1;
    final side = size ?? iconTheme.size ?? brandGlyphSize;
    return SizedBox.square(
      dimension: side,
      child: Center(
        child: CustomPaint(
          size: Size.square(side),
          painter: _BrandGlyphPainter(
            glyph: glyph,
            color: color.withValues(alpha: color.a * opacity),
          ),
        ),
      ),
    );
  }
}

class _BrandGlyphPainter extends CustomPainter {
  const _BrandGlyphPainter({required this.glyph, required this.color});

  final BrandGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.shortestSide / brandGlyphSize);
    canvas.drawPath(glyph.path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandGlyphPainter oldDelegate) =>
      glyph != oldDelegate.glyph || color != oldDelegate.color;
}
