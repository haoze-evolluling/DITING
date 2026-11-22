// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'null_status.dart';

class EmptyIllustration extends StatefulWidget {
  final NullStatusIllustration type;
  final double dimension;

  const EmptyIllustration({
    super.key,
    required this.type,
    required this.dimension,
  });

  @override
  State<EmptyIllustration> createState() => _EmptyIllustrationState();
}

class _EmptyIllustrationState extends State<EmptyIllustration>
    with SingleTickerProviderStateMixin {
  static final _random = math.Random();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );
  final _entrance = _Entrance.values[_random.nextInt(_Entrance.values.length)];
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    if (!_skipsEntrance(context)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final colorScheme = context.colorScheme;
    final (shape, glyph) = _artOf(type);
    return RepaintBoundary(
      child: CustomPaint(
        key: ValueKey(type),
        painter: _IllustrationPainter(
          shape: shape,
          glyph: glyph,
          palette: type == NullStatusIllustration.error
              ? _IllustrationPalette.error(colorScheme)
              : _IllustrationPalette(colorScheme),
          entrance: _entrance,
          progress: _controller,
        ),
        child: SizedBox.square(dimension: widget.dimension),
      ),
    );
  }

  static (RoundedPolygon, IconData) _artOf(
    NullStatusIllustration type,
  ) => switch (type) {
    NullStatusIllustration.data => (
      MaterialShapes.cookie12Sided,
      TablerIcons.server,
    ),
    NullStatusIllustration.logs => (
      MaterialShapes.cookie9Sided,
      TablerIcons.logs,
    ),
    NullStatusIllustration.proxies => (MaterialShapes.sunny, TablerIcons.world),
    NullStatusIllustration.profile => (
      MaterialShapes.cookie7Sided,
      TablerIcons.file_text,
    ),
    NullStatusIllustration.scripts => (
      MaterialShapes.cookie6Sided,
      TablerIcons.code,
    ),
    NullStatusIllustration.rules => (
      MaterialShapes.clover8Leaf,
      TablerIcons.list_details,
    ),
    NullStatusIllustration.connections => (
      MaterialShapes.cookie4Sided,
      TablerIcons.topology_star,
    ),
    NullStatusIllustration.requests => (
      MaterialShapes.softBurst,
      TablerIcons.clock,
    ),
    NullStatusIllustration.dns => (MaterialShapes.puffy, TablerIcons.server_2),
    NullStatusIllustration.ntp => (MaterialShapes.pentagon, TablerIcons.clock),
    NullStatusIllustration.sniffer => (MaterialShapes.gem, TablerIcons.eye),
    NullStatusIllustration.tun => (MaterialShapes.clamShell, TablerIcons.shield_lock),
    NullStatusIllustration.wifi => (
      MaterialShapes.cookie7Sided,
      TablerIcons.wifi,
    ),
    NullStatusIllustration.apps => (
      MaterialShapes.clover4Leaf,
      TablerIcons.list,
    ),
    NullStatusIllustration.icons => (
      MaterialShapes.verySunny,
      TablerIcons.photo,
    ),
    NullStatusIllustration.fonts => (
      MaterialShapes.puffyDiamond,
      TablerIcons.typography,
    ),
    NullStatusIllustration.permission => (MaterialShapes.sunny, TablerIcons.lock),
    NullStatusIllustration.camera => (
      MaterialShapes.cookie6Sided,
      TablerIcons.camera,
    ),
    NullStatusIllustration.error => (MaterialShapes.softBurst, TablerIcons.alert_circle),
    NullStatusIllustration.search => (MaterialShapes.flower, TablerIcons.search),
  };
}

class _IllustrationPalette {
  final Color shape;
  final Color ink;
  final Color highlight;
  final Color accent;
  final Color accentContainer;

  _IllustrationPalette(ColorScheme colorScheme)
    : shape = colorScheme.primaryContainer,
      ink = colorScheme.onPrimaryContainer,
      highlight = colorScheme.primary,
      accent = colorScheme.tertiary,
      accentContainer = colorScheme.tertiaryContainer;

  _IllustrationPalette.error(ColorScheme colorScheme)
    : shape = colorScheme.errorContainer,
      ink = colorScheme.onErrorContainer,
      highlight = colorScheme.error,
      accent = colorScheme.error,
      accentContainer = colorScheme.errorContainer;

  @override
  bool operator ==(Object other) =>
      other is _IllustrationPalette &&
      other.shape == shape &&
      other.ink == ink &&
      other.highlight == highlight &&
      other.accent == accent &&
      other.accentContainer == accentContainer;

  @override
  int get hashCode =>
      Object.hash(shape, ink, highlight, accent, accentContainer);
}

enum _Entrance { spin, morph, orbit }

enum _Accent { blob, dot, ring }

typedef _ShapePose = ({double scale, double turn, double morph, double alpha});
typedef _GlyphPose = ({double scale, double rise, double fill, double alpha});
typedef _AccentPose = ({double scale, double drift, double orbit, double turn});

class _IllustrationPainter extends CustomPainter {
  static const _shapeExtent = 0.72;
  static const _haloExtent = 0.84;
  static const _glyphExtent = 0.4;
  static const _accents = [
    (_Accent.blob, Offset(-0.32, 0.3), 0.14),
    (_Accent.dot, Offset(-0.4, -0.18), 0.05),
    (_Accent.ring, Offset(0.42, 0.15), 0.075),
  ];
  static final _paths = Expando<Path>();
  static final _morphs = Expando<Morph>();

  final RoundedPolygon shape;
  final IconData glyph;
  final _IllustrationPalette palette;
  final _Entrance entrance;
  final Animation<double> progress;

  _IllustrationPainter({
    required this.shape,
    required this.glyph,
    required this.palette,
    required this.entrance,
    required this.progress,
  }) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final side = size.shortestSide;
    final center = size.center(Offset.zero);
    final (halo, body, mark) = _poseAt(t);

    _paintShape(
      canvas,
      halo,
      center,
      side * _haloExtent,
      palette.highlight.withValues(
        alpha: palette.highlight.a * 0.14 * halo.alpha,
      ),
    );
    _paintShape(canvas, body, center, side * _shapeExtent, palette.shape);
    if (mark.scale > 0) {
      _paintGlyph(
        canvas,
        glyph,
        center + Offset(0, side * mark.rise),
        side * _glyphExtent * mark.scale,
        mark.fill,
        palette.ink.withValues(alpha: palette.ink.a * mark.alpha),
      );
    }

    for (final (index, (accent, offset, extent)) in _accents.indexed) {
      final pose = _accentAt(t, index);
      if (pose.scale <= 0) {
        continue;
      }
      final at =
          center +
          Offset.fromDirection(offset.direction + pose.orbit, offset.distance) *
              side *
              pose.drift;
      final diameter = side * extent * pose.scale;
      switch (accent) {
        case _Accent.blob:
          _paintPath(
            canvas,
            _paths[MaterialShapes.cookie4Sided] ??= MaterialShapes.cookie4Sided
                .toPath(),
            at,
            diameter,
            math.pi / 12 + pose.turn,
            palette.accentContainer,
          );
        case _Accent.dot:
          canvas.drawCircle(at, diameter / 2, Paint()..color = palette.accent);
        case _Accent.ring:
          final width = diameter * 0.28;
          canvas.drawCircle(
            at,
            (diameter - width) / 2,
            Paint()
              ..color = palette.highlight
              ..style = PaintingStyle.stroke
              ..strokeWidth = width,
          );
      }
    }
  }

  (_ShapePose, _ShapePose, _GlyphPose) _poseAt(double t) {
    switch (entrance) {
      case _Entrance.spin:
        _ShapePose spun(double settle) => (
          scale: lerpDouble(0.6, 1, settle)!,
          turn: -math.pi / 3 * (1 - settle),
          morph: 1,
          alpha: 1,
        );
        return (
          spun(_phase(t, 0.08, 0.75, Curves.easeOutBack)),
          spun(_phase(t, 0, 0.65, Curves.easeOutBack)),
          (
            scale:
                lerpDouble(0.5, 1, _phase(t, 0.1, 0.55, Curves.easeOutBack))! +
                math.sin(math.pi * _phase(t, 0.55, 0.85)) * 0.08,
            rise: 0,
            fill: _phase(t, 0.2, 0.6, Curves.easeInOutCubic),
            alpha: _phase(t, 0.1, 0.3),
          ),
        );
      case _Entrance.morph:
        _ShapePose morphed(double begin, double end) {
          final morph = _phase(t, begin, end, Curves.easeInOutCubic);
          return (
            scale: lerpDouble(
              0.5,
              1,
              _phase(t, begin, begin + 0.5, Curves.easeOutBack),
            )!,
            turn: math.pi / 2 * (1 - morph),
            morph: morph,
            alpha: 1,
          );
        }
        final rise = _phase(t, 0.2, 0.6, Curves.easeOutBack);
        return (
          morphed(0.15, 0.8),
          morphed(0.05, 0.65),
          (
            scale: lerpDouble(0.8, 1, rise)!,
            rise: 0.14 * (1 - rise),
            fill: _phase(t, 0.3, 0.7, Curves.easeInOutCubic),
            alpha: _phase(t, 0.2, 0.35),
          ),
        );
      case _Entrance.orbit:
        final ripple = _phase(t, 0.2, 0.75, Curves.easeOutCubic);
        return (
          (
            scale: lerpDouble(_shapeExtent / _haloExtent, 1, ripple)!,
            turn: 0,
            morph: 1,
            alpha: ripple,
          ),
          (
            scale: lerpDouble(
              0.3,
              1,
              _phase(t, 0, 0.6, const ElasticOutCurve(0.6)),
            )!,
            turn: 0,
            morph: 1,
            alpha: 1,
          ),
          (
            scale: _phase(t, 0.15, 0.7, const ElasticOutCurve(0.5)),
            rise: 0,
            fill: _phase(t, 0.3, 0.7, Curves.easeInOutCubic),
            alpha: _phase(t, 0.15, 0.25),
          ),
        );
    }
  }

  _AccentPose _accentAt(double t, int index) {
    switch (entrance) {
      case _Entrance.spin:
        final begin = 0.4 + index * 0.08;
        final enter = _phase(t, begin, begin + 0.35, Curves.easeOutBack);
        return (
          scale: enter,
          drift: lerpDouble(0.7, 1, enter)!,
          orbit: 0,
          turn: -math.pi / 4 * (1 - enter),
        );
      case _Entrance.morph:
        final begin = 0.45 + (_accents.length - 1 - index) * 0.07;
        final enter = _phase(t, begin, begin + 0.3, Curves.easeOutBack);
        return (
          scale: enter,
          drift: 1,
          orbit: 0,
          turn: -math.pi / 2 * (1 - enter),
        );
      case _Entrance.orbit:
        final begin = 0.3 + index * 0.1;
        final travel = _phase(t, begin, begin + 0.4, Curves.easeOutCubic);
        return (
          scale: _phase(t, begin, begin + 0.3, Curves.easeOutBack),
          drift: lerpDouble(0.55, 1, travel)!,
          orbit: -math.pi * 0.7 * (1 - travel),
          turn: -math.pi / 2 * (1 - travel),
        );
    }
  }

  static double _phase(
    double t,
    double begin,
    double end, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  void _paintShape(
    Canvas canvas,
    _ShapePose pose,
    Offset center,
    double extent,
    Color color,
  ) {
    final path = pose.morph >= 1
        ? _paths[shape] ??= shape.toPath()
        : (_morphs[shape] ??= Morph(
            MaterialShapes.circle,
            shape,
          )).toPath(progress: pose.morph);
    _paintPath(canvas, path, center, extent * pose.scale, pose.turn, color);
  }

  void _paintPath(
    Canvas canvas,
    Path path,
    Offset center,
    double extent,
    double rotation,
    Color color,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);
    canvas.scale(extent);
    canvas.translate(-0.5, -0.5);
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  void _paintGlyph(
    Canvas canvas,
    IconData glyph,
    Offset center,
    double extent,
    double fill,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(glyph.codePoint),
        style: iconGlyphStyle(glyph, size: extent, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter oldDelegate) =>
      oldDelegate.shape != shape ||
      oldDelegate.glyph != glyph ||
      oldDelegate.palette != palette ||
      oldDelegate.entrance != entrance ||
      oldDelegate.progress != progress;
}
