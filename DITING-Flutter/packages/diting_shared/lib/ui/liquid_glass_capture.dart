// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
part of 'liquid_glass.dart';

// A capture shrinks while a sigma of its frost spans two pixels; smaller shows blocks under glass.
const double _captureFrost = 2;
const int _maxDivisor = 8;
const double _maxCaptureSide = 2048;
// The blur of a downscaled capture read linearly, in its own pixels.
const double _captureSoftness = 0.5;
// How far content may paint past the bounds its layer was recorded for.
const double _overflow = 64;
// Impeller caches layer and blur targets by size for a few frames, so resizing misses them.
const double _atlasStep = 32;
// Past this many sigmas a pane takes under 1% of what it reads, so one painted there adds a level.
const double _levelReach = 2.5;
const double _heldFrostShare = 0.9;
// Offsets into a pane's mapping, in the order of the shader's uniforms.
const _hazeSample = 10;
const _hazeShare = 18;
const _veilColor = 19;
const _noHaze = <double>[0, 0, 1, 1, 0, 0, 0, 0];

typedef LiquidGlassCapture = ({
  int snapshots,
  int keptBands,
  List<
    ({
      Rect pane,
      Rect slot,
      Rect place,
      double scale,
      int level,
      ui.Image atlas,
    })
  >
  panes,
});

/// Draws the panes below from one capture of what lies behind them (.agents/architecture.md).
class LiquidGlassHost extends StatelessWidget {
  const LiquidGlassHost({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @visibleForTesting
  static LiquidGlassCapture? debugLastCapture;

  @visibleForTesting
  static bool? debugCarryBandsOverride;

  /// How many panes hold a capture, under a host or not.
  @visibleForTesting
  static int get debugHeldCaptures => _LiquidGlassLayer._capturesHeld;

  @override
  Widget build(BuildContext context) {
    return _LiquidGlassHostBox(
      enabled: enabled,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      quality: LiquidGlassScope.qualityOf(context),
      child: child,
    );
  }
}

/// Fades [child] as Core Animation fades a layer: the panes within still bend and fade with it.
class LiquidGlassFade extends SingleChildRenderObjectWidget {
  const LiquidGlassFade({super.key, required this.opacity, super.child});

  final Animation<double> opacity;

  static void push(
    PaintingContext context,
    Offset offset,
    int alpha,
    PaintingContextCallback painter,
  ) {
    context.pushLayer(
      _LiquidGlassFadeLayer()
        ..alpha = alpha
        ..offset = offset,
      painter,
      Offset.zero,
    );
  }

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassFade(opacity);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLiquidGlassFade).opacity = opacity;
  }
}

class _RenderLiquidGlassFade extends RenderProxyBox {
  _RenderLiquidGlassFade(this._opacity);

  final _layer = LayerHandle<_LiquidGlassFadeLayer>();

  Animation<double> _opacity;
  set opacity(Animation<double> value) {
    if (value == _opacity) {
      return;
    }
    if (attached) {
      _opacity.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _opacity = value;
    markNeedsPaint();
  }

  int get _alpha =>
      ui.Color.getAlphaFromOpacity(_opacity.value.clamp(0.0, 1.0));

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _opacity.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _opacity.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final alpha = _alpha;
    if (child == null || alpha == 0) {
      _layer.layer = null;
      return;
    }
    final layer = _layer.layer ??= _LiquidGlassFadeLayer();
    layer
      ..alpha = alpha
      ..offset = offset;
    context.pushLayer(layer, super.paint, Offset.zero);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_alpha != 0) {
      super.visitChildrenForSemantics(visitor);
    }
  }
}

class _LiquidGlassFadeLayer extends OpacityLayer {}

/// Dims what it covers by [color], under [child], as a modal barrier does. An
/// even scrim blurs to itself, so a pane above takes it from the shader rather
/// than its capture, and a scrim fading renews none.
class LiquidGlassVeil extends SingleChildRenderObjectWidget {
  const LiquidGlassVeil({super.key, required this.color, super.child});

  final Animation<Color?> color;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassVeil(color);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderLiquidGlassVeil).color = color;
  }
}

class _RenderLiquidGlassVeil extends RenderProxyBox {
  _RenderLiquidGlassVeil(this._color);

  final _layer = LayerHandle<_LiquidGlassVeilLayer>();

  Animation<Color?> _color;
  set color(Animation<Color?> value) {
    if (value == _color) {
      return;
    }
    if (attached) {
      _color.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _color = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _color.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _color.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final color = _color.value;
    if (color == null || color.a == 0) {
      _layer.layer = null;
    } else {
      final layer = _layer.layer ??= _LiquidGlassVeilLayer();
      layer
        ..color = color
        ..rect = offset & size;
      context.pushLayer(
        layer,
        (context, _) =>
            context.canvas.drawRect(layer.rect, Paint()..color = color),
        Offset.zero,
      );
    }
    super.paint(context, offset);
  }
}

class _LiquidGlassVeilLayer extends ContainerLayer {
  Color color = const Color(0x00000000);
  Rect rect = Rect.zero;
}

class _LiquidGlassHostBox extends SingleChildRenderObjectWidget {
  const _LiquidGlassHostBox({
    required this.enabled,
    required this.devicePixelRatio,
    required this.quality,
    super.child,
  });

  final bool enabled;
  final double devicePixelRatio;
  final LiquidGlassQuality quality;

  @override
  _RenderLiquidGlassHost createRenderObject(BuildContext context) {
    return _RenderLiquidGlassHost(
      enabled: enabled,
      devicePixelRatio: devicePixelRatio,
      quality: quality,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlassHost renderObject,
  ) {
    renderObject
      ..enabled = enabled
      ..devicePixelRatio = devicePixelRatio
      ..quality = quality;
  }
}

class _RenderLiquidGlassHost extends RenderProxyBox {
  _RenderLiquidGlassHost({
    required bool enabled,
    required double devicePixelRatio,
    required LiquidGlassQuality quality,
  }) : _enabled = enabled,
       _devicePixelRatio = devicePixelRatio,
       _quality = quality;

  final _layer = LayerHandle<_LiquidGlassHostLayer>();

  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  LiquidGlassQuality _quality;
  set quality(LiquidGlassQuality value) {
    if (value == _quality) {
      return;
    }
    _quality = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _enabled;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled) {
      _release();
      super.paint(context, offset);
      return;
    }
    final layer = _layer.layer ??= _LiquidGlassHostLayer();
    layer
      ..devicePixelRatio = _devicePixelRatio
      ..quality = _quality
      ..bounds = offset & size;
    context.pushLayer(layer, super.paint, offset);
  }

  // A pane captured on a pass still current would keep drawing from it.
  void _release() {
    if (_layer.layer != null) {
      _layer.layer = null;
      _LiquidGlassHostLayer._pass++;
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }
}
