// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

part 'liquid_glass_capture.dart';
part 'liquid_glass_capture_b.dart';
part 'liquid_glass_capture_c.dart';
part 'liquid_glass_b.dart';
part 'liquid_glass_c.dart';
part 'liquid_glass_d.dart';
part 'liquid_glass_capture_d.dart';
part 'liquid_glass_e.dart';

const _shaderAsset = 'packages/diting_shared/shaders/liquid_glass.frag';
const _glowIn = Duration(milliseconds: 120);
const _glowOut = Duration(milliseconds: 360);
const double _glowSpread = 3;
const _profileTurns = 64;
// kLine in shaders/liquid_glass.frag.
const double _hairlineWidth = 0.67;
// In corner radii from the corner of the bounds.
const _shineAround = [
  (along: 1.53, down: 0.0, lit: 0.68),
  (along: 1.0, down: 0.0, lit: 0.48),
  (along: 0.3, down: 0.3, lit: 0.38),
  (along: 0.0, down: 1.0, lit: 0.17),
  (along: 0.0, down: 1.5, lit: 0.07),
  (along: 0.0, down: 2.0, lit: 0.03),
];
const _shineBands = [
  (depth: 0.0, width: 1 / 3, lit: 1.0),
  (depth: 1 / 3, width: 1 / 3, lit: 0.7),
  (depth: 2 / 3, width: 1 / 3, lit: 0.47),
  (depth: 1.0, width: 2 / 3, lit: 0.18),
  (depth: 5 / 3, width: 2 / 3, lit: 0.12),
  (depth: 7 / 3, width: 2 / 3, lit: 0.085),
  (depth: 3.0, width: 2 / 3, lit: 0.065),
  (depth: 11 / 3, width: 2 / 3, lit: 0.045),
  (depth: 13 / 3, width: 2 / 3, lit: 0.035),
];
// The size of uShineEnds in shaders/liquid_glass.frag.
const _shineSlots = 12;
final _noShine = List<double>.unmodifiable(
  List<double>.filled(2 * (_shineAround.length + 2) + 2 * _shineSlots, 0),
);
final _flatProfile = List<double>.unmodifiable(
  List<double>.filled(_profileTurns, 0),
);
// The size of uPills in shaders/liquid_glass.frag.
const _gooPills = 6;
final _noGoo = List<double>.unmodifiable(
  List<double>.filled(10 * _gooPills + 8, 0),
);

/// How much of iOS's glass the panes draw (.agents/architecture.md).
enum LiquidGlassQuality { standard, ultra }

class LiquidGlassScope extends InheritedWidget {
  const LiquidGlassScope({
    super.key,
    required this.enabled,
    this.quality = LiquidGlassQuality.ultra,
    required super.child,
  });

  final bool enabled;
  final LiquidGlassQuality quality;

  static bool of(BuildContext context) => _of(context)?.enabled ?? false;

  static LiquidGlassQuality qualityOf(BuildContext context) =>
      _of(context)?.quality ?? LiquidGlassQuality.ultra;

  static LiquidGlassScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LiquidGlassScope>();

  @override
  bool updateShouldNotify(LiquidGlassScope oldWidget) =>
      enabled != oldWidget.enabled || quality != oldWidget.quality;
}

/// Keeps the panes below on one level, as iOS's GlassEffectContainer does.
class LiquidGlassGroup extends InheritedWidget {
  const LiquidGlassGroup({super.key, required super.child});

  static Object? _of(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<LiquidGlassGroup>();

  @override
  bool updateShouldNotify(LiquidGlassGroup oldWidget) => false;
}

/// Lengths are dp. The shader shrinks [bevel] and [refraction] to fit a small pane.
@immutable
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.style,
    this.clipper,
    this.shadows = const [],
    this.pressed = false,
    this.glow,
    this.child,
  });

  final LiquidGlassStyle style;

  /// Shapes the pane to its path instead of the pill; the path must meet every ray once.
  final CustomClipper<Path>? clipper;

  final List<BoxShadow> shadows;

  final bool pressed;

  final LiquidGlassGlow? glow;

  final Widget? child;

  /// Builds the scenes of [capture] without panes, for a snapshot: offscreen a pane only tints.
  static T withoutPanes<T>(T Function() capture) {
    _LiquidGlassLayer._skipped++;
    try {
      return capture();
    } finally {
      _LiquidGlassLayer._skipped--;
    }
  }

  static ButtonStyle buttonStyle(
    LiquidGlassStyle Function(Set<WidgetState> states) styleOf,
  ) {
    return ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      backgroundBuilder: (context, states, child) => LiquidGlass(
        style: styleOf(states),
        pressed: states.contains(WidgetState.pressed),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = LiquidGlassGroup._of(context);
    if (glow case final glow?) {
      return _LiquidGlassPane(
        group: group,
        style: style,
        clipper: clipper,
        shadows: shadows,
        press: 0,
        fading: false,
        glow: glow,
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: pressed ? 1 : 0),
      duration: context.motionDuration(pressed ? _glowIn : _glowOut),
      curve: Curves.easeOut,
      builder: (context, press, child) => _LiquidGlassPane(
        group: group,
        style: style,
        clipper: clipper,
        shadows: shadows,
        press: press,
        fading: !pressed,
        glow: null,
        child: child,
      ),
      child: child,
    );
  }
}

sealed class LiquidGlassShape {
  const LiquidGlassShape();
}

/// A rounded rectangle, no corner rounder than half the pane's short side.
final class LiquidGlassCorners extends LiquidGlassShape {
  const LiquidGlassCorners(this.radius);

  LiquidGlassCorners.circular(double radius)
    : radius = BorderRadius.circular(radius);

  final BorderRadius radius;
}

final class LiquidGlassOutline extends LiquidGlassShape {
  const LiquidGlassOutline(this.path);

  final Path path;
}

/// `GooSurface`'s pills, outlined by [path], each blending into the one before.
/// With [firstRadius] the first is a rectangle rounded so, not a pill.
final class LiquidGlassGoo extends LiquidGlassShape {
  const LiquidGlassGoo(this.path, this.pills, this.blends, {this.firstRadius})
    : assert(pills.length <= _gooPills);

  final Path path;
  final List<Rect> pills;
  final List<double> blends;
  final double? firstRadius;

  List<double> get _uniforms {
    final octants = [
      for (var index = 0; index < _gooPills; index++)
        index < pills.length
            ? _superellipseOctant(
                pills[index].longestSide / 2,
                pills[index].shortestSide / 2,
              )
            : _noOctant,
    ];
    return [
      for (var index = 0; index < _gooPills; index++)
        if (index < pills.length) ...[
          pills[index].center.dx,
          pills[index].center.dy,
          pills[index].width / 2,
          pills[index].height / 2,
        ] else ...const [0.0, 0.0, 0.0, 0.0],
      pills.length.toDouble(),
      for (var index = 1; index < _gooPills; index++)
        index < pills.length ? blends[index - 1] : 0.0,
      firstRadius ?? 0.0,
      0.0,
      for (final (:n, :joint, :radius, center: _) in octants) ...[
        n,
        joint.dx,
        joint.dy,
        radius,
      ],
      for (final octant in octants) ...[octant.center.dx, octant.center.dy],
    ];
  }
}

/// A pane for a render object that shapes the glass itself, as a morph does.
class LiquidGlassPane {
  LiquidGlassPane(this.onReady);

  final VoidCallback onReady;

  final _layer = LayerHandle<_LiquidGlassLayer>();
  Path? _profiled;
  List<double> _profile = _flatProfile;

  /// A pane moving within [hold] keeps one capture, taken at [holdFrost] where
  /// the shader frosts past it. A [steadyFrost] pane frosts by [style]'s blur
  /// in the host's dp however it is scaled, so it keeps that capture as it
  /// grows or shrinks.
  void paint(
    PaintingContext context,
    Rect rect, {
    required LiquidGlassShape shape,
    required LiquidGlassStyle style,
    List<BoxShadow> shadows = const [],
    LiquidGlassGlow glow = LiquidGlassGlow.none,
    Rect? hold,
    double? holdFrost,
    bool steadyFrost = false,
    LiquidGlassRim? rim,
    Object? group,
  }) {
    final pane = _layer.layer ??= _LiquidGlassLayer();
    assert(rim == null || shape is LiquidGlassCorners);
    switch (shape) {
      case LiquidGlassCorners(:final radius):
        final limit = Radius.circular(rect.shortestSide / 2);
        final corners = BorderRadius.only(
          topLeft: radius.topLeft.clamp(maximum: limit),
          topRight: radius.topRight.clamp(maximum: limit),
          bottomLeft: radius.bottomLeft.clamp(maximum: limit),
          bottomRight: radius.bottomRight.clamp(maximum: limit),
        );
        _profiled = null;
        if (hold == null) {
          _paintShadows(context.canvas, rect, corners, shadows);
        }
        pane
          ..corners = corners
          ..outline = null
          ..profile = _flatProfile
          ..goo = _noGoo;
      case LiquidGlassOutline(:final path):
        assert(shadows.isEmpty, 'An outlined pane casts none');
        if (!identical(path, _profiled)) {
          _profiled = path;
          _profile = liquidGlassProfile(path, rect.size.center(Offset.zero));
        }
        pane
          ..corners = BorderRadius.zero
          ..outline = path.shift(rect.topLeft)
          ..profile = _profile
          ..goo = _noGoo;
      case final LiquidGlassGoo goo:
        assert(shadows.isEmpty, 'A pane of goo casts none');
        _profiled = null;
        pane
          ..corners = BorderRadius.zero
          ..outline = goo.path.shift(rect.topLeft)
          ..profile = _flatProfile
          ..goo = goo._uniforms;
    }
    pane
      ..program = _GlassProgram.request(onReady)
      ..rect = rect
      ..style = style
      ..glow = glow
      ..hold = hold
      ..holdFrost = holdFrost
      ..steadyFrost = steadyFrost
      ..rim = rim
      ..group = group;
    context.addLayer(pane);
    if (hold != null) {
      _paintShadows(context.canvas, rect, pane.corners, shadows);
    }
  }

  void clear() => _layer.layer = null;

  void dispose() {
    _GlassProgram.forget(onReady);
    clear();
  }

  static void _paintShadows(
    Canvas canvas,
    Rect rect,
    BorderRadius corners,
    List<BoxShadow> shadows,
  ) {
    if (shadows.isEmpty) {
      return;
    }
    final shape = AppShape.of(corners);
    final reach = shadows.fold(
      0.0,
      (reach, shadow) => math.max(
        reach,
        shadow.offset.distance + shadow.spreadRadius + shadow.blurRadius * 2,
      ),
    );
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(reach))
          ..addPath(shape.getOuterPath(rect), Offset.zero),
      );
    for (final shadow in shadows) {
      canvas.drawRSuperellipse(
        corners.toRSuperellipse(
          rect.shift(shadow.offset).inflate(shadow.spreadRadius),
        ),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }
}

abstract final class _GlassProgram {
  static ui.FragmentProgram? _program;
  static Future<void>? _loading;

  /// Final: a shader that failed once fails again, and every attempt loads on the UI isolate.
  static var _failed = false;
  static final _waiting = <VoidCallback>{};

  static ui.FragmentProgram? request(VoidCallback onLoaded) {
    if (_program != null ||
        _failed ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return _program;
    }
    _waiting.add(onLoaded);
    _loading ??= _load().then(
      (program) {
        _program = program;
        final waiting = _waiting.toList();
        _waiting.clear();
        for (final callback in waiting) {
          callback();
        }
      },
      onError: (Object error, StackTrace stack) {
        _failed = true;
        _waiting.clear();
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'liquid glass',
          ),
        );
      },
    );
    return null;
  }

  static void forget(VoidCallback onLoaded) => _waiting.remove(onLoaded);

  static Future<ui.FragmentProgram> _load() =>
      ui.FragmentProgram.fromAsset(_shaderAsset);
}
