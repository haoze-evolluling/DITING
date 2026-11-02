// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'liquid_glass.dart';
import 'navigation_dock.dart';

part 'goo_a.dart';

// At rest no closer than buttons stand in a bar, so none bulges toward its
// neighbor until a press swells it, as iOS 27 merges a search field it swells
// with its cancel button.
const double _restBlend = 8;
const double _pressBlend = 8;
const double _neckStep = 0.5;

/// Draws the [GooPane]s below, pills in rows, as one surface that flows
/// together where two neighbors in a row come close, as iOS 27 draws controls
/// whose glass shares a container. `TonalButtonTheme` and `TonalButtonGroup`
/// below put their buttons on panes.
class GooSurface extends StatelessWidget {
  const GooSurface({
    super.key,
    this.glass,
    required this.color,
    this.shadows = const [],
    required this.child,
  });

  final LiquidGlassStyle? glass;
  final Color color;

  /// Cast only outside the surface, as one under glass would show through.
  final List<BoxShadow> shadows;
  final Widget child;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_GooScope>() != null;

  static const buttonStyle = ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    backgroundBuilder: _paneBehind,
  );

  static Widget _paneBehind(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => GooPane(child: child);

  @override
  Widget build(BuildContext context) {
    return _GooScope(
      child: _GooSurfaceBox(
        glass: glass,
        color: color,
        shadows: shadows,
        child: child,
      ),
    );
  }
}

class _GooScope extends InheritedWidget {
  const _GooScope({required super.child});

  @override
  bool updateShouldNotify(_GooScope oldWidget) => false;
}

/// A pill of the [GooSurface] above, swelling with the presses around it.
class GooPane extends SingleChildRenderObjectWidget {
  const GooPane({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGooPane();
}

class _RenderGooPane extends RenderProxyBox {
  _RenderGooSurface? _surface;
  VoidCallback? _unfollow;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderGooSurface) {
        _surface = node.._panes.add(this);
        _unfollow = ElasticPress.followPresses(this, node.markNeedsPaint);
        node.markNeedsPaint();
        return;
      }
    }
  }

  @override
  void detach() {
    _unfollow?.call();
    _unfollow = null;
    _surface
      ?.._panes.remove(this)
      ..markNeedsPaint();
    _surface = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    _surface?.markNeedsPaint();
  }
}

class _GooSurfaceBox extends SingleChildRenderObjectWidget {
  const _GooSurfaceBox({
    required this.glass,
    required this.color,
    required this.shadows,
    super.child,
  });

  final LiquidGlassStyle? glass;
  final Color color;
  final List<BoxShadow> shadows;

  @override
  _RenderGooSurface createRenderObject(BuildContext context) =>
      _RenderGooSurface(glass: glass, color: color, shadows: shadows);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderGooSurface renderObject,
  ) {
    renderObject
      ..glass = glass
      ..color = color
      ..shadows = shadows;
  }
}

typedef _Placed = ({Rect rect, double lift});

class _RenderGooSurface extends RenderProxyBox {
  _RenderGooSurface({
    required LiquidGlassStyle? glass,
    required Color color,
    required List<BoxShadow> shadows,
  }) : _glass = glass,
       _color = color,
       _shadows = shadows;

  final _panes = <_RenderGooPane>{};
  late final _pane = LiquidGlassPane(markNeedsPaint);
  Offset? _touch;
  ({List<Rect> pills, List<double> blends, Path path})? _outline;

  LiquidGlassStyle? _glass;
  set glass(LiquidGlassStyle? value) {
    if (value == _glass) {
      return;
    }
    if ((value == null) != (_glass == null)) {
      markNeedsCompositingBitsUpdate();
    }
    _glass = value;
    markNeedsPaint();
  }

  Color _color;
  set color(Color value) {
    if (value == _color) {
      return;
    }
    _color = value;
    markNeedsPaint();
  }

  List<BoxShadow> _shadows;
  set shadows(List<BoxShadow> value) {
    if (listEquals(value, _shadows)) {
      return;
    }
    _shadows = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _glass != null;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _touch = event.localPosition;
    }
  }

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final panes = _rows([
      for (final pane in _panes)
        if (pane.attached && pane.hasSize && !pane.size.isEmpty)
          (
            rect: MatrixUtils.transformRect(
              pane.getTransformTo(this),
              ElasticPress.paintBoundsOf(pane),
            ),
            lift: ElasticPress.liftOf(pane),
          ),
    ]);
    final pills = [for (final pane in panes) pane.rect];
    if (pills.isEmpty) {
      _pane.clear();
      super.paint(context, offset);
      return;
    }
    final blends = [
      for (var index = 1; index < panes.length; index++)
        _inRow(panes[index - 1].rect, panes[index].rect)
            ? _restBlend +
                  _pressBlend *
                      math.max(panes[index - 1].lift, panes[index].lift)
            : 0.0,
    ];
    final bounds = pills.reduce((a, b) => a.expandToInclude(b));
    final path = _outlineOf(pills, blends);
    final canvas = context.canvas;
    _paintShadows(canvas, path.shift(offset), bounds.shift(offset));
    final glass = _glass;
    if (glass == null) {
      _pane.clear();
      canvas.drawPath(path.shift(offset), Paint()..color = _color);
    } else {
      final pressed = panes.reduce((a, b) => b.lift > a.lift ? b : a);
      final touch = _touch;
      _pane.paint(
        context,
        bounds.shift(offset),
        shape: LiquidGlassGoo(path.shift(-bounds.topLeft), [
          for (final pill in pills) pill.shift(-bounds.topLeft),
        ], blends),
        style: glass,
        glow: LiquidGlassGlow(
          center:
              (touch != null && pressed.rect.contains(touch)
                  ? touch
                  : pressed.rect.center) -
              bounds.topLeft,
          reach: pressed.rect.height / math.sqrt2,
          strength: pressed.lift * 0.16,
        ),
      );
    }
    super.paint(context, offset);
  }

  static bool _inRow(Rect a, Rect b) =>
      (a.center.dy - b.center.dy).abs() < math.min(a.height, b.height) / 2;

  /// [panes] in rows from the top, each from the left.
  static List<_Placed> _rows(List<_Placed> panes) {
    final rows = <List<_Placed>>[];
    for (final pane
        in panes
          ..removeWhere((pane) => pane.rect.isEmpty)
          ..sort((a, b) => a.rect.center.dy.compareTo(b.rect.center.dy))) {
      if (rows.isNotEmpty && _inRow(rows.last.first.rect, pane.rect)) {
        rows.last.add(pane);
      } else {
        rows.add([pane]);
      }
    }
    return [
      for (final row in rows)
        ...row..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx)),
    ];
  }

  Path _outlineOf(List<Rect> pills, List<double> blends) {
    final outline = _outline;
    if (outline != null &&
        listEquals(outline.pills, pills) &&
        listEquals(outline.blends, blends)) {
      return outline.path;
    }
    final path = gooOutline(pills, blends);
    _outline = (pills: pills, blends: blends, path: path);
    return path;
  }

  void _paintShadows(Canvas canvas, Path path, Rect bounds) {
    if (_shadows.isEmpty) {
      return;
    }
    final reach = _shadows.fold(
      0.0,
      (reach, shadow) =>
          math.max(reach, shadow.offset.distance + shadow.blurRadius * 2),
    );
    canvas
      ..save()
      ..clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(bounds.inflate(reach))
          ..addPath(path, Offset.zero),
      );
    for (final shadow in _shadows) {
      canvas.drawPath(path.shift(shadow.offset), shadow.toPaint());
    }
    canvas.restore();
  }
}

/// The outline of [pills], as gooGeometry in shaders/liquid_glass.frag blends
/// their distances.
@visibleForTesting
Path gooOutline(List<Rect> pills, List<double> blends) {
  var outline = Path();
  for (final pill in pills) {
    outline.addRSuperellipse(
      RSuperellipse.fromRectAndRadius(
        pill,
        Radius.circular(pill.shortestSide / 2),
      ),
    );
  }
  for (var index = 1; index < pills.length; index++) {
    final neck = _neck(pills[index - 1], pills[index], blends[index - 1]);
    if (neck != null) {
      outline = Path.combine(PathOperation.union, outline, neck);
    }
  }
  return outline;
}

/// [a], rounded by [radius], and the pill [b] flowing together either way
/// they lie, as gooGeometry blends a first pill given that radius.
Path gooPairOutline(
  Rect a,
  double radius,
  Rect b,
  double blend, {
  bool coarse = false,
}) {
  final platter = Path()
    ..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(a, Radius.circular(radius)),
    );
  final pillRadius = b.shortestSide / 2;
  final pill = Path()
    ..addRSuperellipse(
      RSuperellipse.fromRectAndRadius(b, Radius.circular(pillRadius)),
    );
  if (gooPairDepth(a, radius, b, blend) >= 0) {
    return platter;
  }
  if (gooPairDepth(b, pillRadius, a, blend) >= 0) {
    return pill;
  }
  final bridge = coarse
      ? _bridge(a, radius, b, blend, turns: 64, tolerance: 0.15)
      : _bridge(a, radius, b, blend, turns: 128, tolerance: 0.05);
  return bridge == null
      ? Path.combine(PathOperation.union, platter, pill)
      : Path.combine(
          PathOperation.union,
          platter..addPath(pill, Offset.zero),
          bridge,
        );
}

/// How far inside [a], rounded by [radius], all of [b] lies past where
/// [blend] still swells [a]'s outline toward it; negative while it does.
double gooPairDepth(Rect a, double radius, Rect b, double blend) {
  final outermost = [
    b.topLeft,
    b.topRight,
    b.bottomLeft,
    b.bottomRight,
  ].map((corner) => _roundedDistance(a, radius, corner)).reduce(math.max);
  return -outermost - blend;
}
