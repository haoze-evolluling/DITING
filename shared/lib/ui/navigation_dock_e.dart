// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'navigation_dock.dart';

/// Paints what lies under the lens in [color], magnified as it lifts, cut to the lens shape.
class _LensTint extends SingleChildRenderObjectWidget {
  const _LensTint({
    required this.part,
    this.active = true,
    required this.lens,
    required this.lensWidth,
    required this.jelly,
    required this.lift,
    required this.parallax,
    required this.index,
    required this.color,
    required this.textDirection,
    super.child,
  });

  final _LensPart part;

  /// Whether to tint by lens position; false when no page is in the dock, so item 0 stays grey.
  final bool active;
  final _Spring lens;
  final double lensWidth;
  final ValueListenable<double> jelly;
  final ValueListenable<double> lift;
  final ValueListenable<double> parallax;
  final int index;
  final Color color;
  final TextDirection textDirection;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLensTint(
      part: part,
      active: active,
      lens: lens,
      lensWidth: lensWidth,
      jelly: jelly,
      lift: lift,
      parallax: parallax,
      index: index,
      color: color,
      textDirection: textDirection,
    );
  }

  @override
  void updateRenderObject(BuildContext context, _RenderLensTint renderObject) {
    renderObject
      ..part = part
      ..active = active
      ..lens = lens
      ..lensWidth = lensWidth
      ..jelly = jelly
      ..lift = lift
      ..parallax = parallax
      ..index = index
      ..color = color
      ..textDirection = textDirection;
  }
}

class _RenderLensTint extends RenderProxyBox {
  _RenderLensTint({
    required _LensPart part,
    required bool active,
    required _Spring lens,
    required double lensWidth,
    required ValueListenable<double> jelly,
    required ValueListenable<double> lift,
    required ValueListenable<double> parallax,
    required int index,
    required Color color,
    required TextDirection textDirection,
  }) : _part = part,
       _active = active,
       _lens = lens,
       _lensWidth = lensWidth,
       _jelly = jelly,
       _lift = lift,
       _parallax = parallax,
       _index = index,
       _color = color,
       _textDirection = textDirection;

  final _outside = LayerHandle<ClipPathLayer>();
  final _inside = LayerHandle<ClipPathLayer>();
  final _tint = LayerHandle<ColorFilterLayer>();
  final _outsideMotion = LayerHandle<TransformLayer>();
  final _insideMotion = LayerHandle<TransformLayer>();

  _LensPart _part;
  set part(_LensPart value) {
    if (value == _part) {
      return;
    }
    _part = value;
    markNeedsPaint();
  }

  bool _active;
  set active(bool value) {
    if (value == _active) {
      return;
    }
    _active = value;
    markNeedsPaint();
  }

  _Spring _lens;
  set lens(_Spring value) {
    if (value == _lens) {
      return;
    }
    if (attached) {
      _lens.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lens = value;
    markNeedsPaint();
  }

  double _lensWidth;
  set lensWidth(double value) {
    if (value == _lensWidth) {
      return;
    }
    _lensWidth = value;
    markNeedsPaint();
  }

  ValueListenable<double> _jelly;
  set jelly(ValueListenable<double> value) {
    if (value == _jelly) {
      return;
    }
    if (attached) {
      _jelly.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _jelly = value;
    markNeedsPaint();
  }

  ValueListenable<double> _lift;
  set lift(ValueListenable<double> value) {
    if (value == _lift) {
      return;
    }
    if (attached) {
      _lift.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _lift = value;
    markNeedsPaint();
  }

  ValueListenable<double> _parallax;
  set parallax(ValueListenable<double> value) {
    if (value == _parallax) {
      return;
    }
    if (attached) {
      _parallax.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _parallax = value;
    markNeedsPaint();
  }

  int _index;
  set index(int value) {
    if (value == _index) {
      return;
    }
    _index = value;
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

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _lens.addListener(markNeedsPaint);
    _jelly.addListener(markNeedsPaint);
    _lift.addListener(markNeedsPaint);
    _parallax.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _lens.removeListener(markNeedsPaint);
    _jelly.removeListener(markNeedsPaint);
    _lift.removeListener(markNeedsPaint);
    _parallax.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _outside.layer = null;
    _inside.layer = null;
    _tint.layer = null;
    _outsideMotion.layer = null;
    _insideMotion.layer = null;
    super.dispose();
  }

  Rect get _lensBounds {
    final rect = _lensRect(
      position: _lens.value - _index,
      stretch: _jelly.value,
      pitch: size.width,
      width: _lensWidth,
      height: size.height,
      lift: _lift.value,
    );
    return _textDirection == TextDirection.ltr
        ? rect
        : Rect.fromLTRB(
            size.width - rect.right,
            rect.top,
            size.width - rect.left,
            rect.bottom,
          );
  }

  Matrix4? _motion(double scale) {
    final direction = _textDirection == TextDirection.ltr ? 1 : -1;
    final shift = _parallax.value * size.width * direction;
    if (scale == 1 && shift == 0) {
      return null;
    }
    final center = size.center(Offset.zero);
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      center.dx * (1 - scale) + shift,
      center.dy * (1 - scale),
      0,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final motion = _motion(1);
    if (motion != null) {
      transform.multiply(motion);
    }
  }

  void _paintMoved(
    PaintingContext context,
    Offset offset,
    Matrix4? motion,
    LayerHandle<TransformLayer> handle,
  ) {
    if (motion == null) {
      handle.layer = null;
      super.paint(context, offset);
      return;
    }
    handle.layer = context.pushTransform(
      needsCompositing,
      offset,
      motion,
      super.paint,
      oldLayer: handle.layer,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    // With no selection, skip the lens tint: the lens rests at index 0 and would read as selected.
    if (!_active) {
      _outside.layer = null;
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
      final rest = _motion(1);
      if (_part != _LensPart.inside) {
        _paintMoved(context, offset, rest, _outsideMotion);
      } else {
        _outsideMotion.layer = null;
      }
      return;
    }
    final rest = _motion(1);
    final magnified = _motion(1 + _lensMagnify * _lift.value);
    final bounds = Offset.zero & size;
    Rect moved(Matrix4? motion) =>
        motion == null ? bounds : MatrixUtils.transformRect(motion, bounds);
    final lensBounds = _lensBounds;
    // The lens rests [_barPadding] past its destination, over the edges of the neighbours.
    final reached = Rect.fromLTRB(
      lensBounds.left + _barPadding,
      lensBounds.top,
      lensBounds.right - _barPadding,
      lensBounds.bottom,
    );
    final outside = _part != _LensPart.inside;
    final inside = _part != _LensPart.outside;
    if (!reached.overlaps(moved(rest)) && !reached.overlaps(moved(magnified))) {
      _outside.layer = null;
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
      if (outside) {
        _paintMoved(context, offset, rest, _outsideMotion);
      } else {
        _outsideMotion.layer = null;
      }
      return;
    }
    final reach = moved(rest).expandToInclude(bounds).inflate(_labelInset);
    final lens = AppShape.full.getOuterPath(lensBounds);
    if (outside) {
      _outside.layer = context.pushClipPath(
        needsCompositing,
        offset,
        reach,
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(reach)
          ..addPath(lens, Offset.zero),
        (context, offset) => _paintMoved(context, offset, rest, _outsideMotion),
        oldLayer: _outside.layer,
      );
    } else {
      _outside.layer = null;
      _outsideMotion.layer = null;
    }
    if (inside) {
      _inside.layer = context.pushClipPath(
        needsCompositing,
        offset,
        lensBounds,
        lens,
        (context, offset) =>
            _paintTinted(context, offset, lensBounds, magnified),
        oldLayer: _inside.layer,
      );
    } else {
      _inside.layer = null;
      _tint.layer = null;
      _insideMotion.layer = null;
    }
  }

  void _paintTinted(
    PaintingContext context,
    Offset offset,
    Rect lensBounds,
    Matrix4? motion,
  ) {
    final filter = ColorFilter.mode(_color, BlendMode.srcIn);
    if (needsCompositing) {
      _tint.layer = context.pushColorFilter(
        offset,
        filter,
        (context, offset) =>
            _paintMoved(context, offset, motion, _insideMotion),
        oldLayer: _tint.layer,
      );
      return;
    }
    _tint.layer = null;
    final canvas = context.canvas
      ..saveLayer(lensBounds.shift(offset), Paint()..colorFilter = filter);
    _paintMoved(context, offset, motion, _insideMotion);
    canvas.restore();
  }
}
