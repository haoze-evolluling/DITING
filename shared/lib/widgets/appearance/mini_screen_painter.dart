/// Painting for `mini_screen.dart`, split out to stay under the line cap.
part of 'mini_screen.dart';

class _MiniScreenPainter extends CustomPainter {
  const _MiniScreenPainter({
    required this.colorScheme,
    required this.floatingBar,
    required this.liquidGlass,
    required this.selected,
    required this.previous,
    required this.progress,
    required this.transition,
  });

  final ColorScheme colorScheme;
  final bool floatingBar;
  final bool liquidGlass;
  final int selected;
  final int? previous;
  final double progress;
  final TabTransition transition;

  bool get _glass => floatingBar && liquidGlass;

  static const _pages = MiniPage.values;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _MiniGeometry(size, floatingBar: floatingBar);
    _paintPages(canvas, geometry, 1);
    _paintBar(canvas, geometry);
    _paintDestinations(canvas, geometry.bar, geometry.unit);
  }

  void _paintPages(Canvas canvas, _MiniGeometry geometry, double opacity) {
    final size = geometry.size;
    canvas
      ..drawRect(
        Offset.zero & size,
        Paint()..color = _surface(SurfaceLevel.page, opacity),
      )
      ..save()
      ..clipRect(Offset.zero & size, doAntiAlias: false);
    final previous = this.previous;
    if (previous == null || progress >= 1) {
      _paintPage(canvas, geometry, selected, 0, opacity);
    } else {
      switch (transition) {
        case TabTransition.none:
          _paintPage(
            canvas,
            geometry,
            progress >= 0.5 ? selected : previous,
            0,
            opacity,
          );
        case TabTransition.fade:
          _paintPage(canvas, geometry, previous, 0, opacity * (1 - progress));
          _paintPage(canvas, geometry, selected, 0, opacity * progress);
        case TabTransition.slide:
          final direction = previous > selected ? -1 : 1;
          _paintPage(
            canvas,
            geometry,
            previous,
            -direction * size.width * progress,
            opacity,
          );
          _paintPage(
            canvas,
            geometry,
            selected,
            direction * size.width * (1 - progress),
            opacity,
          );
        case TabTransition.scale:
          _paintPage(
            canvas,
            geometry,
            previous,
            0,
            opacity * (1 - progress),
            scale: 1 - 0.12 * progress,
          );
          _paintPage(
            canvas,
            geometry,
            selected,
            0,
            opacity * progress,
            scale: 0.88 + 0.12 * progress,
          );
      }
    }
    canvas.restore();
  }

  void _paintPage(
    Canvas canvas,
    _MiniGeometry geometry,
    int index,
    double dx,
    double opacity, {
    double scale = 1,
  }) {
    if (opacity <= 0) {
      return;
    }
    final page = _pages[index % _pages.length];
    final size = geometry.size;
    final unit = geometry.unit;
    canvas.save();
    if (dx != 0) {
      canvas.translate(dx, 0);
    }
    if (scale != 1) {
      final center = Offset(size.width / 2, size.height / 2);
      canvas
        ..translate(center.dx, center.dy)
        ..scale(scale)
        ..translate(-center.dx, -center.dy);
    }
    final titleWidth = switch (page) {
      MiniPage.dashboard => unit * 6,
      MiniPage.rules => unit * 4.4,
      MiniPage.logs => unit * 5.2,
      MiniPage.tools => unit * 4,
    };
    _pill(
      canvas,
      unit * 1.5,
      unit * 1.5,
      titleWidth,
      unit * 1.1,
      _ink(0.5, opacity),
    );
    _dot(
      canvas,
      size.width - unit * 2.2,
      unit * 1.95,
      unit * 0.55,
      _ink(0.22, opacity),
    );
    switch (page) {
      case MiniPage.dashboard:
        _dashboard(canvas, geometry, opacity);
      case MiniPage.rules:
        _rows(canvas, geometry, 6, opacity);
      case MiniPage.logs:
        _cards(canvas, geometry, 3, opacity);
      case MiniPage.tools:
        _rows(canvas, geometry, 4, opacity);
    }
    canvas.restore();
  }

  void _dashboard(Canvas canvas, _MiniGeometry geometry, double opacity) {
    final unit = geometry.unit;
    final size = geometry.size;
    final center = Offset(size.width / 2, unit * 7.4);
    canvas
      ..drawCircle(
        center,
        unit * 2.1,
        Paint()..color = colorScheme.primary.withValues(alpha: opacity),
      )
      ..drawCircle(
        center,
        unit * 1.1,
        Paint()..color = colorScheme.onPrimary.withValues(alpha: opacity),
      );
    _block(
      canvas,
      Rect.fromLTWH(unit * 1.5, unit * 10.4, size.width - unit * 3, unit * 2.6),
      _card(opacity),
    );
    _block(
      canvas,
      Rect.fromLTWH(unit * 1.5, unit * 13.6, size.width - unit * 3, unit * 2.2),
      _card(opacity),
    );
  }

  void _rows(Canvas canvas, _MiniGeometry geometry, int count, double opacity) {
    final unit = geometry.unit;
    final width = geometry.size.width;
    var y = unit * 4.2;
    for (
      var i = 0;
      i < count && y < geometry.size.height - geometry.pageBottom;
      i++
    ) {
      _block(
        canvas,
        Rect.fromLTWH(unit * 1.5, y, width - unit * 3, unit * 2),
        _card(opacity),
      );
      _dot(canvas, unit * 2.4, y + unit * 1, unit * 0.42, _ink(0.22, opacity));
      _pill(
        canvas,
        unit * 3.4,
        y + unit * 0.7,
        unit * 4 + (i % 3) * unit,
        unit * 0.6,
        _ink(0.35, opacity),
      );
      y += unit * 2.5;
    }
  }

  void _cards(
    Canvas canvas,
    _MiniGeometry geometry,
    int count,
    double opacity,
  ) {
    final unit = geometry.unit;
    final width = geometry.size.width;
    var y = unit * 4.2;
    for (
      var i = 0;
      i < count && y < geometry.size.height - geometry.pageBottom;
      i++
    ) {
      final height = unit * (i == 0 ? 3.6 : 2.6);
      _block(
        canvas,
        Rect.fromLTWH(unit * 1.5, y, width - unit * 3, height),
        _card(opacity),
      );
      _pill(
        canvas,
        unit * 2.5,
        y + unit * 0.9,
        unit * 4.5,
        unit * 0.7,
        _ink(0.35, opacity),
      );
      for (var row = 1; row <= (i == 0 ? 2 : 1); row++) {
        _pill(
          canvas,
          unit * 2.5,
          y + unit * (0.9 + row * 0.9),
          unit * (3 + row),
          unit * 0.45,
          _ink(0.2, opacity),
        );
      }
      y += height + unit * 0.8;
    }
  }

  void _paintBar(Canvas canvas, _MiniGeometry geometry) {
    final bar = geometry.bar;
    final unit = geometry.unit;
    final fill = SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme);
    if (_glass) {
      _paintGlassBar(canvas, geometry);
      return;
    }
    if (floatingBar) {
      _fill(
        canvas,
        bar,
        fill,
        AppShape.full,
        shadows: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.12),
            blurRadius: unit,
            offset: Offset(0, unit * 0.3),
          ),
        ],
      );
      return;
    }
    canvas.drawRect(bar, Paint()..color = fill);
  }

  /// Glass floating bar: blur the page behind it, then layer glass and a highlight.
  void _paintGlassBar(Canvas canvas, _MiniGeometry geometry) {
    final bar = geometry.bar;
    final unit = geometry.unit;
    final path = AppShape.full.getOuterPath(bar);
    final rim = unit * 0.12;
    canvas
      ..save()
      ..clipPath(path)
      ..saveLayer(
        bar,
        Paint()
          ..imageFilter = ImageFilter.blur(
            sigmaX: unit * 0.35,
            sigmaY: unit * 0.35,
          ),
      );
    _paintPages(canvas, geometry, 1);
    canvas
      ..restore()
      ..restore()
      ..drawPath(
        path,
        Paint()
          ..color = colorScheme.surfaceContainerHighest.withValues(
            alpha: colorScheme.brightness == Brightness.dark ? 0.55 : 0.62,
          ),
      )
      ..drawPath(
        AppShape.full.getOuterPath(bar.deflate(rim / 2)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rim
          ..color = Colors.white.withValues(alpha: 0.55),
      );
  }

  void _paintDestinations(Canvas canvas, Rect bar, double unit) {
    final gap = bar.width / MiniScreen.destinationCount;
    for (var i = 0; i < MiniScreen.destinationCount; i++) {
      final center = Offset(bar.left + gap * (i + 0.5), bar.center.dy);
      final active = i == selected;
      canvas.drawCircle(
        center,
        unit * (active ? 0.62 : 0.48),
        Paint()
          ..color =
              (active ? colorScheme.primary : colorScheme.onSurfaceVariant)
                  .withValues(alpha: active ? 1 : 0.55),
      );
    }
  }

  Color _surface(SurfaceLevel level, double opacity) =>
      level.colorOf(colorScheme).withValues(alpha: opacity);

  Color _card(double opacity) => _surface(SurfaceLevel.card, opacity);

  Color _ink(double alpha, double opacity) =>
      colorScheme.onSurfaceVariant.withValues(alpha: alpha * opacity);

  void _fill(
    Canvas canvas,
    Rect rect,
    Color color,
    ShapeBorder shape, {
    List<BoxShadow>? shadows,
  }) {
    ShapeDecoration(color: color, shape: shape, shadows: shadows)
        .createBoxPainter(() {})
        .paint(canvas, rect.topLeft, ImageConfiguration(size: rect.size));
  }

  void _block(Canvas canvas, Rect rect, Color color) => _fill(
    canvas,
    rect,
    color,
    AppShape.all(math.min(rect.shortestSide / 2, rect.width / 9)),
  );

  void _pill(
    Canvas canvas,
    double x,
    double y,
    double width,
    double height,
    Color color,
  ) => _fill(canvas, Rect.fromLTWH(x, y, width, height), color, AppShape.full);

  void _dot(Canvas canvas, double x, double y, double radius, Color color) =>
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);

  @override
  bool shouldRepaint(_MiniScreenPainter old) =>
      old.colorScheme != colorScheme ||
      old.floatingBar != floatingBar ||
      old.liquidGlass != liquidGlass ||
      old.selected != selected ||
      old.previous != previous ||
      old.progress != progress ||
      old.transition != transition;
}
