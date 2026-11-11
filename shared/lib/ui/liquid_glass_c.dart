// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

class _LiquidGlassPane extends SingleChildRenderObjectWidget {
  const _LiquidGlassPane({
    required this.group,
    required this.style,
    required this.clipper,
    required this.shadows,
    required this.press,
    required this.fading,
    required this.glow,
    super.child,
  });

  final Object? group;
  final LiquidGlassStyle style;
  final CustomClipper<Path>? clipper;
  final List<BoxShadow> shadows;
  final double press;
  final bool fading;
  final LiquidGlassGlow? glow;

  @override
  _RenderLiquidGlass createRenderObject(BuildContext context) {
    return _RenderLiquidGlass(
      group: group,
      style: style,
      clipper: clipper,
      shadows: shadows,
      press: press,
      fading: fading,
      glow: glow,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlass renderObject,
  ) {
    renderObject
      ..group = group
      ..style = style
      ..clipper = clipper
      ..shadows = shadows
      ..press = press
      ..fading = fading
      ..glow = glow;
  }
}

class _RenderLiquidGlass extends RenderProxyBox {
  _RenderLiquidGlass({
    required Object? group,
    required LiquidGlassStyle style,
    required CustomClipper<Path>? clipper,
    required List<BoxShadow> shadows,
    required double press,
    required bool fading,
    required LiquidGlassGlow? glow,
  }) : _group = group,
       _style = style,
       _clipper = clipper,
       _shadows = shadows,
       _press = press,
       _fading = fading,
       _glow = glow;

  late final _pane = LiquidGlassPane(markNeedsPaint);

  Object? _group;
  set group(Object? value) {
    if (identical(value, _group)) {
      return;
    }
    _group = value;
    markNeedsPaint();
  }

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
    if (value == _style) {
      return;
    }
    _style = value;
    markNeedsPaint();
  }

  CustomClipper<Path>? _clipper;
  set clipper(CustomClipper<Path>? value) {
    final old = _clipper;
    if (value == old) {
      return;
    }
    if (attached) {
      old?.removeListener(_reclip);
      value?.addListener(_reclip);
    }
    _clipper = value;
    if (value == null ||
        old == null ||
        value.runtimeType != old.runtimeType ||
        value.shouldReclip(old)) {
      _reclip();
    }
  }

  Path? _outline;
  Size? _outlineSize;

  void _reclip() {
    _outline = null;
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

  double _press;
  set press(double value) {
    if (value == _press) {
      return;
    }
    _press = value;
    if (value == 0) {
      _touch = null;
    }
    markNeedsPaint();
  }

  bool _fading;
  set fading(bool value) {
    if (value == _fading) {
      return;
    }
    _fading = value;
    markNeedsPaint();
  }

  // The pane wraps the glass it is, so it hears presses and lights from the finger, as iOS does.
  Offset? _touch;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      _touch = event.localPosition;
      if (_press > 0) {
        markNeedsPaint();
      }
    } else if (_press == 0) {
      _touch = null;
    }
  }

  LiquidGlassGlow? _glow;
  set glow(LiquidGlassGlow? value) {
    if (value == _glow) {
      return;
    }
    _glow = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _clipper?.addListener(_reclip);
  }

  @override
  void detach() {
    _clipper?.removeListener(_reclip);
    super.detach();
  }

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  Path? get _currentOutline {
    final clipper = _clipper;
    if (clipper == null) {
      return null;
    }
    if (_outline == null || _outlineSize != size) {
      _outline = clipper.getClip(size);
      _outlineSize = size;
    }
    return _outline;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) {
      _pane.clear();
    } else {
      final outline = _currentOutline;
      _pane.paint(
        context,
        offset & size,
        shape: outline != null
            ? LiquidGlassOutline(outline)
            : LiquidGlassCorners(BorderRadius.circular(size.shortestSide / 2)),
        style: _style,
        shadows: _shadows,
        glow:
            _glow ??
            LiquidGlassGlow(
              center: _touch ?? size.center(Offset.zero),
              reach:
                  size.height /
                  math.sqrt2 *
                  (1 + (_fading ? _glowSpread * (1 - _press) : 0)),
              strength: _press * 0.16,
            ),
        group: _group,
      );
    }
    super.paint(context, offset);
  }
}
