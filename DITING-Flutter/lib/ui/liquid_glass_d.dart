// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

class _LiquidGlassLayer extends Layer {
  static int _skipped = 0;
  static int _capturesHeld = 0;

  ui.FragmentProgram? program;
  Rect rect = Rect.zero;
  BorderRadius corners = BorderRadius.zero;
  Path? outline;
  List<double> profile = _flatProfile;
  List<double> goo = _noGoo;
  LiquidGlassStyle style = const LiquidGlassStyle(tint: Colors.transparent);
  LiquidGlassGlow glow = LiquidGlassGlow.none;
  Rect? hold;
  double? holdFrost;
  bool steadyFrost = false;
  LiquidGlassRim? rim;
  Object? group;
  _Placement? _held;

  ui.Picture? _frost;
  (Rect, BorderRadius, Path?, LiquidGlassStyle, LiquidGlassRim?)? _frostKey;

  int _capturedPass = -1;
  ui.Picture? _captured;
  ui.FragmentShader? _captureShader;
  (ui.Image, Path?, BlendMode, ui.FragmentProgram?, List<double>)? _captureKey;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void dispose() {
    _frost?.dispose();
    _dropCaptured();
    super.dispose();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_skipped > 0) {
      return;
    }
    if (_capturedPass == _LiquidGlassHostLayer._pass) {
      if (_captured case final picture?) {
        builder.addPicture(Offset.zero, picture);
      }
      return;
    }
    _dropCaptured();
    _addFrost(builder);
  }

  /// The uniforms from the pane's shape on, after where it and its texture lie.
  List<double> _look(LiquidGlassStyle style) => [
    rect.width,
    rect.height,
    style.bevel,
    style.blur,
    corners.topLeft.x,
    corners.topRight.x,
    corners.bottomRight.x,
    corners.bottomLeft.x,
    ...liquidGlassCornerCurves(rect.size, corners),
    style.refraction,
    style.saturation,
    style.brightness,
    style.tint.r,
    style.tint.g,
    style.tint.b,
    style.tint.a,
    style.rim,
    style.rimWidth,
    style.endShade,
    glow.center.dx,
    glow.center.dy,
    glow.strength,
    style.contrast,
    glow.reach,
    glow.wash,
    style.hairline,
    style.dispersion,
    style.rimBlur,
    style.rimTail,
    style.rimFocus,
    style.rimAdded,
    style._hairlineSide,
    outline == null
        ? 0.0
        : identical(goo, _noGoo)
        ? 1.0
        : 2.0,
    ...profile,
    ...rim?._uniforms(rect.size, corners.topLeft.x) ?? _noShine,
    ...goo,
  ];

  void _addFrost(ui.SceneBuilder builder) {
    final key = (rect, corners, outline, style, rim);
    if (_frost == null || key != _frostKey) {
      _frost?.dispose();
      _frost = _paintFrost();
      _frostKey = key;
    }
    if (outline case final outline?) {
      builder.pushClipPath(outline);
    } else {
      builder.pushClipRSuperellipse(
        corners.toRSuperellipse(rect),
        clipBehavior: ui.Clip.antiAlias,
      );
    }
    builder.addPicture(Offset.zero, _frost!);
    builder.pop();
  }

  /// Draws the pane from [atlas] until its next pass; [mapping] places the slot.
  void _captureFrom(
    int pass,
    ui.Image atlas,
    List<double> mapping,
    BlendMode blendMode,
    LiquidGlassStyle style,
  ) {
    _capturedPass = pass;
    final program = this.program;
    final uniforms = <double>[
      atlas.width.toDouble(),
      atlas.height.toDouble(),
      -rect.left,
      -rect.top,
      1,
      1,
      ...mapping,
      ..._look(style),
    ];
    if (_captureKey
        case (final image, final path, final mode, final shaded, final values)?
        when _captured != null &&
            identical(image, atlas) &&
            identical(path, outline) &&
            mode == blendMode &&
            identical(shaded, program) &&
            listEquals(values, uniforms)) {
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (program == null) {
      _frostFrom(canvas, atlas, mapping, blendMode, style);
    } else {
      final shader = _captureShader ??= program.fragmentShader();
      shader.setImageSampler(0, atlas, filterQuality: FilterQuality.low);
      for (final (index, value) in uniforms.indexed) {
        shader.setFloat(index, value);
      }
      final paint = Paint()
        ..shader = shader
        ..blendMode = blendMode;
      if (outline case final outline?) {
        canvas.drawPath(outline, paint);
      } else {
        canvas.drawRSuperellipse(corners.toRSuperellipse(rect), paint);
      }
    }
    _hold(recorder.endRecording());
    _captureKey = (atlas, outline, blendMode, program, uniforms);
  }

  /// Frosts the pane without bending it, from the part of [atlas] behind it, which holds its blur.
  void _frostFrom(
    Canvas canvas,
    ui.Image atlas,
    List<double> mapping,
    BlendMode blendMode,
    LiquidGlassStyle style,
  ) {
    canvas.save();
    if (outline case final outline?) {
      canvas.clipPath(outline);
    } else {
      canvas.clipRSuperellipse(corners.toRSuperellipse(rect));
    }
    final saturate = ColorFilter.matrix(
      _optics(style.saturation, style.brightness),
    );
    void drawSlot(int from, Paint paint) => canvas.drawImageRect(
      atlas,
      Rect.fromLTWH(
        -mapping[from] / mapping[from + 2],
        -mapping[from + 1] / mapping[from + 3],
        rect.width / mapping[from + 2],
        rect.height / mapping[from + 3],
      ),
      rect,
      paint
        ..filterQuality = FilterQuality.low
        ..colorFilter = saturate,
    );
    drawSlot(0, Paint()..blendMode = blendMode);
    final haze = mapping[_hazeShare];
    if (haze > 0) {
      drawSlot(_hazeSample, Paint()..color = Color.fromRGBO(0, 0, 0, haze));
    }
    final veil = Color.from(
      alpha: mapping[_veilColor + 3],
      red: mapping[_veilColor],
      green: mapping[_veilColor + 1],
      blue: mapping[_veilColor + 2],
    );
    if (veil.a > 0) {
      canvas.drawPaint(Paint()..color = veil);
    }
    _drawFrost(canvas, overCapture: true);
    canvas.restore();
  }

  /// Draws nothing until the host's next pass, as nothing of the pane shows.
  void _captureNothing(int pass) {
    _capturedPass = pass;
    _dropCaptured();
  }

  void _dropCaptured() {
    _hold(null);
    _captureKey = null;
    _captureShader?.dispose();
    _captureShader = null;
  }

  void _hold(ui.Picture? captured) {
    if ((captured == null) != (_captured == null)) {
      _capturesHeld += captured == null ? -1 : 1;
    }
    _captured?.dispose();
    _captured = captured;
  }

  ui.Picture _paintFrost() {
    final recorder = ui.PictureRecorder();
    _drawFrost(Canvas(recorder));
    return recorder.endRecording();
  }

  /// Thickens the tint to stand in for the frost unless the pane lies [overCapture].
  void _drawFrost(Canvas canvas, {bool overCapture = false}) {
    final tint = style.tint;
    final fill = Paint()
      ..color = overCapture
          ? tint
          : tint.withValues(alpha: math.min(1, tint.a + 0.2));
    final rim = style.rim;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.rimWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: rim),
          Colors.white.withValues(alpha: rim * 0.15),
          Colors.white.withValues(alpha: rim * 0.5),
        ],
      ).createShader(rect);
    final hairline = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.black.withValues(
        alpha: (style.hairline + style._hairlineSide) / 2 * 0.3,
      );
    if (outline case final outline?) {
      // The clip keeps the inner half of a stroke twice as wide.
      canvas
        ..drawPath(outline, fill)
        ..drawPath(outline, stroke..strokeWidth = style.rimWidth * 2)
        ..drawPath(outline, hairline..strokeWidth = _hairlineWidth * 2);
    } else {
      final shape = corners.toRSuperellipse(rect);
      canvas
        ..drawRSuperellipse(shape, fill)
        ..drawRSuperellipse(shape.deflate(style.rimWidth / 2), stroke)
        ..drawRSuperellipse(
          shape.deflate(_hairlineWidth / 2),
          hairline..strokeWidth = _hairlineWidth,
        );
      this.rim?._paintShine(canvas, rect, corners.topLeft.x);
    }
  }
}

/// How far [outline] reaches from [center] on the even turns the shader reads, first toward +x.
@visibleForTesting
List<double> liquidGlassProfile(Path outline, Offset center) {
  const step = 2 * math.pi / _profileTurns;
  final profile = List<double>.filled(_profileTurns, 0);
  void cross(Offset from, Offset to) {
    final start = from.direction;
    var span = to.direction - start;
    if (span > math.pi) {
      span -= 2 * math.pi;
    } else if (span <= -math.pi) {
      span += 2 * math.pi;
    }
    final edge = to - from;
    final first = (math.min(start, start + span) / step).ceil();
    final last = (math.max(start, start + span) / step).floor();
    for (var turn = first; turn <= last; turn++) {
      final ray = Offset.fromDirection(turn * step);
      final facing = ray.dx * edge.dy - ray.dy * edge.dx;
      profile[turn % _profileTurns] = facing.abs() < 1e-9
          ? math.max(from.distance, to.distance)
          : (from.dx * edge.dy - from.dy * edge.dx) / facing;
    }
  }

  for (final metric in outline.computeMetrics()) {
    final samples = math.max(_profileTurns * 4, metric.length.ceil());
    Offset pointAt(int index) =>
        metric.getTangentForOffset(metric.length * index / samples)!.position -
        center;
    var previous = pointAt(0);
    for (var index = 1; index <= samples; index++) {
      final next = pointAt(index);
      cross(previous, next);
      previous = next;
    }
  }
  return profile;
}

@visibleForTesting
List<double> liquidGlassCornerCurves(Size size, BorderRadius corners) => [
  for (final radius in [
    corners.topLeft.x,
    corners.topRight.x,
    corners.bottomRight.x,
    corners.bottomLeft.x,
  ])
    ..._cornerCurve(size.width / 2, size.height / 2, radius),
];

List<double> _cornerCurve(double halfWidth, double halfHeight, double radius) {
  final along = _superellipseOctant(halfWidth, radius);
  final across = _superellipseOctant(halfHeight, radius);
  return [
    along.n,
    along.joint.dx,
    along.joint.dy,
    along.radius,
    across.n,
    across.joint.dx,
    across.joint.dy,
    across.radius,
    along.center.dx,
    along.center.dy,
    across.center.dx,
    across.center.dy,
  ];
}

typedef _Octant = ({double n, Offset joint, Offset center, double radius});

const _Octant _noOctant = (
  n: 0,
  joint: Offset.zero,
  center: Offset.zero,
  radius: 0,
);

/// ComputeOctant in impeller/geometry/round_superellipse_param.cc, which cornerInset follows.
_Octant _superellipseOctant(double a, double radius) {
  if (radius <= 1e-3) {
    return _noOctant;
  }
  final (n, jointAt) = _octantFit(a * 2 / radius);
  final joint = Offset(
    jointAt * a,
    math.pow(1 - math.pow(jointAt, n), 1 / n) * a,
  );
  final tangent = math.pow(joint.dx / joint.dy, n - 1);
  final diagonal = (joint.dx - tangent * joint.dy) / (1 - tangent);
  final meet = a - _octantGap * radius;
  final arc = (meet - diagonal) * math.sqrt2;
  final chord = Offset(meet, meet) - joint;
  final reach = math.sqrt(math.max(0, arc * arc - chord.distanceSquared / 4));
  final center =
      (joint + Offset(meet, meet)) / 2 +
      Offset(chord.dy, -chord.dx) / chord.distance * reach;
  return (n: n, joint: joint, center: center, radius: arc);
}

const _octantGap = 1 - math.sqrt1_2;

/// By the ratio of an octant's side to its radius: n, and 1 / (1 - xJ / a).
const _octantFits = [
  (2.0, 2.00000000, 1.13276676),
  (2.1, 2.18349805, 1.20311921),
  (2.2, 2.33888662, 1.28698796),
  (2.3, 2.48660575, 1.36351941),
  (2.4, 2.62226596, 1.44717976),
  (2.5, 2.75148990, 1.53385819),
  (3.0, 3.36298265, 1.98288283),
  (3.5, 4.08649929, 2.23811846),
  (4.0, 4.85481134, 2.47563463),
  (4.5, 5.62945551, 2.72948597),
  (5.0, 6.43023796, 2.98020421),
];

(double, double) _octantFit(double ratio) {
  final (lastRatio, lastN, lastK) = _octantFits.last;
  final past = ratio - lastRatio;
  if (past > 0) {
    return (lastN + 1.559599389 * past, 1 - 1 / (lastK + 0.522807185 * past));
  }
  var index = 0;
  while (index < _octantFits.length - 2 && ratio > _octantFits[index + 1].$1) {
    index++;
  }
  final (r0, n0, k0) = _octantFits[index];
  final (r1, n1, k1) = _octantFits[index + 1];
  final t = math.max(0.0, (ratio - r0) / (r1 - r0));
  return (ui.lerpDouble(n0, n1, t)!, 1 - 1 / ui.lerpDouble(k0, k1, t)!);
}

List<double> _optics(double saturation, double brightness) {
  final red = 0.2126 * brightness;
  final green = 0.7152 * brightness;
  final blue = 0.0722 * brightness;
  final rest = 1 - saturation;
  final kept = saturation * brightness;
  return [
    red * rest + kept, green * rest, blue * rest, 0, 0, //
    red * rest, green * rest + kept, blue * rest, 0, 0,
    red * rest, green * rest, blue * rest + kept, 0, 0,
    0, 0, 0, 1, 0,
  ];
}
