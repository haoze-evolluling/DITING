// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

class _MenuRow {
  const _MenuRow(this.index, this.onTap, {required this.togglesSubMenu});

  final int index;
  final VoidCallback? onTap;
  final bool togglesSubMenu;
}

/// Follows a press across the rows and picks the one it is let go on, as iOS menus do.
class _RowPressRecognizer extends OneSequenceGestureRecognizer {
  _RowPressRecognizer({super.debugOwner});

  bool Function(Offset position)? onStart;
  ValueSetter<Offset>? onUpdate;
  ValueSetter<Offset>? onEnd;
  VoidCallback? onCancel;

  int? _pointer;
  Offset? _release;
  bool _accepted = false;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      _pointer == null &&
      event.buttons == kPrimaryButton &&
      super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!(onStart?.call(event.position) ?? false)) {
      return;
    }
    _pointer = event.pointer;
    _release = null;
    _accepted = false;
    startTrackingPointer(event.pointer, event.transform);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.position);
    } else if (event is PointerUpEvent) {
      _release = event.position;
      stopTrackingPointer(event.pointer);
      if (_accepted) {
        _finish();
      } else {
        resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerCancelEvent) {
      resolve(GestureDisposition.rejected);
    }
  }

  @override
  void acceptGesture(int pointer) {
    _accepted = true;
    if (pointer == _pointer && _release != null) {
      _finish();
    }
  }

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
    if (pointer != _pointer) {
      return;
    }
    _pointer = null;
    _release = null;
    onCancel?.call();
  }

  void _finish() {
    final release = _release!;
    _pointer = null;
    _release = null;
    onEnd?.call(release);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'menu row press';
}

/// A menu card a sub menu grows out of the item that opens it, at [grow] 0 to 1.
@visibleForTesting
class PopupMenuCard extends SingleChildRenderObjectWidget {
  const PopupMenuCard({
    super.key,
    required this.grow,
    required this.origin,
    required this.shadows,
    required this.fill,
    required this.dim,
    required this.glass,
    this.rim,
    required this.bare,
    super.child,
  });

  final double grow;

  final ({double top, double height})? origin;

  final List<BoxShadow> shadows;
  final Color fill;

  final Color dim;

  final LiquidGlassStyle? glass;
  final LiquidGlassRim? rim;

  final bool bare;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPopupMenuCard(
      grow: grow,
      origin: origin,
      shadows: shadows,
      fill: fill,
      dim: dim,
      glass: glass,
      rim: rim,
      bare: bare,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPopupMenuCard)
      ..grow = grow
      ..origin = origin
      ..shadows = shadows
      ..fill = fill
      ..dim = dim
      ..glass = glass
      ..rim = rim
      ..bare = bare;
  }
}

class _RenderPopupMenuCard extends RenderProxyBox {
  _RenderPopupMenuCard({
    required double grow,
    required ({double top, double height})? origin,
    required List<BoxShadow> shadows,
    required Color fill,
    required Color dim,
    required LiquidGlassStyle? glass,
    required LiquidGlassRim? rim,
    required bool bare,
  }) : _grow = grow,
       _origin = origin,
       _shadows = shadows,
       _fill = fill,
       _dim = dim,
       _glass = glass,
       _rim = rim,
       _bare = bare;

  late final _pane = LiquidGlassPane(markNeedsPaint);
  final _clip = LayerHandle<ClipPathLayer>();

  double _grow;
  set grow(double value) {
    if (value == _grow) {
      return;
    }
    _grow = value;
    markNeedsPaint();
  }

  ({double top, double height})? _origin;
  set origin(({double top, double height})? value) {
    if (value == _origin) {
      return;
    }
    _origin = value;
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

  Color _fill;
  set fill(Color value) {
    if (value == _fill) {
      return;
    }
    _fill = value;
    markNeedsPaint();
  }

  Color _dim;
  set dim(Color value) {
    if (value == _dim) {
      return;
    }
    _dim = value;
    markNeedsPaint();
  }

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

  LiquidGlassRim? _rim;
  set rim(LiquidGlassRim? value) {
    if (value == _rim) {
      return;
    }
    _rim = value;
    markNeedsPaint();
  }

  bool _bare;
  set bare(bool value) {
    if (value == _bare) {
      return;
    }
    _bare = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _glass != null;

  Rect get _rect {
    final bounds = Offset.zero & size;
    final origin = _origin;
    if (origin == null) {
      return bounds;
    }
    final item = Rect.fromLTRB(
      _cardInset,
      origin.top,
      size.width - _cardInset,
      origin.top + origin.height,
    );
    return Rect.lerp(item, bounds, _grow)!;
  }

  double get _radius => _origin == null
      ? _cardRadius
      : math.max(0.0, lerpDouble(_itemRadius, _cardRadius, _grow)!);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_rect.contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void dispose() {
    _pane.dispose();
    _clip.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    final rect = _rect;
    if (child == null || rect.isEmpty) {
      _pane.clear();
      _clip.layer = null;
      return;
    }
    final radius = _radius;
    final shape = AppShape.all(radius).getOuterPath(rect);
    final glass = _glass;
    if (glass == null) {
      final canvas = context.canvas;
      final surface = shape.shift(offset);
      final corners = AppRadius.all(radius);
      for (final shadow in _shadows) {
        canvas.drawRSuperellipse(
          corners.toRSuperellipse(rect.shift(offset + shadow.offset)),
          shadow.toPaint(),
        );
      }
      canvas.drawPath(surface, Paint()..color = _fill);
    } else if (_bare) {
      _pane.clear();
    } else {
      _pane.paint(
        context,
        rect.shift(offset),
        shape: LiquidGlassCorners.circular(radius),
        style: glass,
        shadows: _shadows,
        hold: (Offset.zero & size).shift(offset),
        rim: _rim,
      );
      _rim?.paintLine(context.canvas, rect.shift(offset), radius);
    }
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      shape,
      (context, offset) {
        context.paintChild(child, offset);
        if (_dim.a > 0) {
          context.canvas.drawPath(shape.shift(offset), Paint()..color = _dim);
        }
      },
      oldLayer: _clip.layer,
    );
  }
}
