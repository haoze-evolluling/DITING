/// A miniature of this window, painted from a [ColorScheme] instead of rendered from widgets.
///
/// The appearance page previews palettes: a phone screenshot cannot show what a desktop window will
/// look like, so the preview is the window itself — caption bar with its window controls, the
/// navigation sidebar with the current branch marked, the toolbar and the card board. Only shapes
/// are painted: nine previews built out of real cards would cost a full layout each every time a
/// palette is tapped, and at thumbnail size no text would be legible anyway.
library;

import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class DesktopWindowPreview extends StatelessWidget {
  const DesktopWindowPreview({super.key, required this.colorScheme});

  /// Logical width everything is painted against; the height follows this ratio, so the preview
  /// keeps the shape of a window at any size instead of the phone shape the mobile previews use.
  static const double logicalWidth = 320;
  static const double logicalHeight = 200;

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: logicalWidth / logicalHeight,
      child: SizedBox.expand(
        child: CustomPaint(painter: _DesktopWindowPainter(colorScheme)),
      ),
    );
  }
}

class _DesktopWindowPainter extends CustomPainter {
  const _DesktopWindowPainter(this.colorScheme);

  final ColorScheme colorScheme;

  /// Paints against a 320x200 logical window and scales with its width, so one geometry serves
  /// both the 150-wide palette tile and the wide preview card.
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / DesktopWindowPreview.logicalWidth;
    final page = SurfaceLevel.page.colorOf(colorScheme);
    final card = SurfaceLevel.card.colorOf(colorScheme);
    final inset = SurfaceLevel.inset.colorOf(colorScheme);
    final chrome = colorScheme.chromeSurface;
    final ink = colorScheme.onSurface;
    final primary = colorScheme.primary;
    final outline = colorScheme.outlineVariant.withValues(alpha: 0.6);

    // The window itself: a page-colored body, a caption bar and a hairline outline so a light
    // preview still reads as a window standing on the card instead of melting into it.
    final window = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(11 * u),
    );
    canvas.save();
    canvas.clipRRect(window);
    canvas.drawRect(Offset.zero & size, Paint()..color = page);

    const captionHeight = 15.0;
    final sidebarWidth = 58 * u;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, captionHeight * u),
      Paint()..color = chrome,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, captionHeight * u, sidebarWidth, size.height),
      Paint()..color = chrome,
    );
    _line(
      canvas,
      Offset(sidebarWidth, captionHeight * u),
      Offset(sidebarWidth, size.height),
      outline,
    );
    _line(
      canvas,
      Offset(0, captionHeight * u),
      Offset(size.width, captionHeight * u),
      outline,
    );
    _windowControls(canvas, size, u, ink);

    _sidebar(canvas, u, sidebarWidth, captionHeight, ink, primary);
    _content(
      canvas,
      size,
      u,
      sidebarWidth,
      captionHeight,
      card,
      inset,
      ink,
      primary,
    );

    canvas.restore();
    canvas.drawRRect(
      window,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );
  }

  /// The minimize / maximize / close marks at the caption's end. Drawn rather than painted as
  /// glyphs: they are two strokes wide at thumbnail size.
  void _windowControls(Canvas canvas, Size size, double u, Color ink) {
    final paint = Paint()
      ..color = ink.withValues(alpha: 0.55)
      ..strokeWidth = 1.2 * u
      ..strokeCap = StrokeCap.round;
    final y = 7.5 * u;
    final closeX = size.width - 12 * u;
    final maxX = closeX - 14 * u;
    final minX = maxX - 14 * u;
    canvas.drawLine(Offset(minX - 3 * u, y), Offset(minX + 3 * u, y), paint);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(maxX, y), width: 6 * u, height: 6 * u),
      paint..style = PaintingStyle.stroke,
    );
    paint.style = PaintingStyle.fill;
    canvas.drawLine(
      Offset(closeX - 3 * u, y - 3 * u),
      Offset(closeX + 3 * u, y + 3 * u),
      paint,
    );
    canvas.drawLine(
      Offset(closeX + 3 * u, y - 3 * u),
      Offset(closeX - 3 * u, y + 3 * u),
      paint,
    );
  }

  void _sidebar(
    Canvas canvas,
    double u,
    double width,
    double captionHeight,
    Color ink,
    Color primary,
  ) {
    // The collapse toggle, then the three branches. The middle one is this app's feature hub and
    // is drawn the way the real sidebar marks it: a tinted row plus the primary indicator.
    final toggle = Rect.fromLTWH(
      10 * u,
      (captionHeight + 8) * u,
      10 * u,
      10 * u,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(toggle, Radius.circular(3 * u)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * u
        ..color = ink.withValues(alpha: 0.45),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(
        toggle.left + 1.8 * u,
        toggle.top + 1.8 * u,
        2.8 * u,
        toggle.height - 3.6 * u,
      ),
      1.1 * u,
      ink.withValues(alpha: 0.3),
    );
    for (var i = 0; i < 3; i++) {
      final selected = i == 1;
      final top = (captionHeight + 24 + i * 20) * u;
      final row = Rect.fromLTWH(4 * u, top, width - 8 * u, 16 * u);
      if (selected) {
        _rrect(canvas, row, 5 * u, ink.withValues(alpha: 0.09));
        _rrect(
          canvas,
          Rect.fromLTWH(6.5 * u, top + 4.5 * u, 2.4 * u, 7 * u),
          1.2 * u,
          primary,
        );
      }
      _navGlyph(canvas, 12 * u, top + 4.5 * u, u, ink, i, selected);
      _rrect(
        canvas,
        Rect.fromLTWH(23 * u, top + 6.5 * u, 21 * u, 3 * u),
        1.5 * u,
        ink.withValues(alpha: selected ? 0.7 : 0.42),
      );
    }
  }

  /// The three branch marks: a dashboard grid, the hub tile and the about ring. Three identical
  /// squares read as a bulleted list; one shape per branch reads as navigation.
  void _navGlyph(
    Canvas canvas,
    double left,
    double top,
    double u,
    Color ink,
    int index,
    bool selected,
  ) {
    final color = ink.withValues(alpha: selected ? 0.62 : 0.34);
    switch (index) {
      case 0:
        for (final dx in const [0.0, 3.6]) {
          for (final dy in const [0.0, 3.6]) {
            _rrect(
              canvas,
              Rect.fromLTWH(left + dx * u, top + dy * u, 2.9 * u, 2.9 * u),
              1 * u,
              color,
            );
          }
        }
      case 1:
        _rrect(
          canvas,
          Rect.fromLTWH(left, top + 0.5 * u, 7 * u, 6 * u),
          2 * u,
          color,
        );
      default:
        canvas.drawCircle(
          Offset(left + 3.5 * u, top + 3.5 * u),
          3 * u,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3 * u
            ..color = color,
        );
    }
  }

  void _content(
    Canvas canvas,
    Size size,
    double u,
    double sidebarWidth,
    double captionHeight,
    Color card,
    Color inset,
    Color ink,
    Color primary,
  ) {
    final left = sidebarWidth + 12 * u;
    final right = size.width - 12 * u;
    final width = right - left;
    final toolbarTop = (captionHeight + 8) * u;

    // Toolbar: the back button, the page title and the page's one primary action.
    canvas.drawCircle(
      Offset(left + 8 * u, toolbarTop + 8 * u),
      8.5 * u,
      Paint()..color = card,
    );
    final chevron = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..strokeWidth = 1.4 * u
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final backCenter = Offset(left + 8 * u, toolbarTop + 8 * u);
    canvas.drawLine(
      Offset(backCenter.dx + 2 * u, backCenter.dy - 3.5 * u),
      Offset(backCenter.dx - 1.5 * u, backCenter.dy),
      chevron,
    );
    canvas.drawLine(
      Offset(backCenter.dx - 1.5 * u, backCenter.dy),
      Offset(backCenter.dx + 2 * u, backCenter.dy + 3.5 * u),
      chevron,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(left + 21 * u, toolbarTop + 5 * u, 46 * u, 6 * u),
      3 * u,
      ink.withValues(alpha: 0.82),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(right - 28 * u, toolbarTop + 3 * u, 28 * u, 10 * u),
      5 * u,
      primary,
    );

    // The card board: one wide card with a title, two notes and a progress track, then two
    // smaller cards — a bar chart and a switch — so every scheme shows its primary where the
    // desktop actually uses it.
    final boardTop = toolbarTop + 22 * u;
    final wide = Rect.fromLTWH(left, boardTop, width, 74 * u);
    _rrect(canvas, wide, 9 * u, card);
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, boardTop + 10 * u, 42 * u, 5 * u),
      2.5 * u,
      ink.withValues(alpha: 0.8),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(right - 40 * u, boardTop + 9 * u, 30 * u, 8 * u),
      4 * u,
      inset,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, boardTop + 23 * u, 118 * u, 3 * u),
      1.5 * u,
      ink.withValues(alpha: 0.3),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, boardTop + 31 * u, 88 * u, 3 * u),
      1.5 * u,
      ink.withValues(alpha: 0.22),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, boardTop + 39 * u, 64 * u, 3 * u),
      1.5 * u,
      ink.withValues(alpha: 0.16),
    );
    final trackTop = boardTop + 54 * u;
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, trackTop, width - 20 * u, 6 * u),
      3 * u,
      primary.withValues(alpha: 0.16),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(left + 10 * u, trackTop, (width - 20 * u) * 0.62, 6 * u),
      3 * u,
      primary,
    );

    final rowTop = boardTop + 84 * u;
    final half = (width - 10 * u) / 2;
    final charts = Rect.fromLTWH(left, rowTop, half, 58 * u);
    final toggles = Rect.fromLTWH(left + half + 10 * u, rowTop, half, 58 * u);
    for (final tile in [charts, toggles]) {
      _rrect(canvas, tile, 9 * u, card);
      _rrect(
        canvas,
        Rect.fromLTWH(tile.left + 10 * u, tile.top + 9 * u, 30 * u, 3.5 * u),
        1.75 * u,
        ink.withValues(alpha: 0.42),
      );
    }

    // Chart bars, tallest last, so the primary reads as a trend rather than a solid block. The
    // group is centered in its card: left-aligned bars left most of the card empty next to the
    // switch card's fuller column.
    const heights = [10.0, 17.0, 13.0, 22.0, 16.0, 26.0];
    const barWidth = 6.0;
    const barPitch = 11.0;
    final base = charts.bottom - 11 * u;
    final barsWidth = (heights.length - 1) * barPitch * u + barWidth * u;
    final barsLeft = charts.left + (charts.width - barsWidth) / 2;
    for (var i = 0; i < heights.length; i++) {
      _rrect(
        canvas,
        Rect.fromLTWH(
          barsLeft + i * barPitch * u,
          base - heights[i] * u,
          barWidth * u,
          heights[i] * u,
        ),
        2.5 * u,
        i.isEven ? primary.withValues(alpha: 0.45) : primary,
      );
    }

    // The switch card: a primary track with its knob, and the two notes that lead up to it.
    _rrect(
      canvas,
      Rect.fromLTWH(toggles.right - 26 * u, toggles.top + 8 * u, 16 * u, 9 * u),
      4.5 * u,
      primary,
    );
    canvas.drawCircle(
      Offset(toggles.right - 14.5 * u, toggles.top + 12.5 * u),
      3.5 * u,
      Paint()..color = colorScheme.onPrimary,
    );
    _rrect(
      canvas,
      Rect.fromLTWH(toggles.left + 10 * u, toggles.top + 22 * u, 70 * u, 3 * u),
      1.5 * u,
      ink.withValues(alpha: 0.26),
    );
    _rrect(
      canvas,
      Rect.fromLTWH(toggles.left + 10 * u, toggles.top + 30 * u, 50 * u, 3 * u),
      1.5 * u,
      ink.withValues(alpha: 0.2),
    );
  }

  void _rrect(Canvas canvas, Rect rect, double radius, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = color,
    );
  }

  void _line(Canvas canvas, Offset from, Offset to, Color color) {
    canvas.drawLine(
      from,
      to,
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_DesktopWindowPainter oldDelegate) =>
      oldDelegate.colorScheme != colorScheme;
}
