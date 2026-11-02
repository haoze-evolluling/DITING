// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

typedef _Placement = ({
  Rect slot,
  Size texels,
  double texelsPerDp,
  double heldFrost,
  double blurSigma,
});

typedef _Band = ({Rect rect, double sigma, List<Object?> drawn});

bool _encloses(Rect outer, Rect inner) =>
    outer.left <= inner.left &&
    outer.top <= inner.top &&
    outer.right >= inner.right &&
    outer.bottom >= inner.bottom;

class _Behind {
  _Behind(
    this.pane,
    this.style,
    this.toHost,
    this.root,
    this.rootToHost,
    this.ancestors,
  ) : hazed = false;

  _Behind.hazeOf(_Behind owner)
    : pane = owner.pane,
      style = owner.style,
      toHost = owner.toHost,
      root = owner.root,
      rootToHost = owner.rootToHost,
      ancestors = owner.ancestors,
      hazed = true;

  final _LiquidGlassLayer pane;
  final LiquidGlassStyle style;
  final Matrix4 toHost;

  /// The host, else the nearest offscreen layer: a backdrop filter there reads only its texture.
  final ContainerLayer root;
  final Matrix4 rootToHost;
  final Set<ContainerLayer> ancestors;

  final bool hazed;

  late final Rect device = MatrixUtils.transformRect(toHost, pane.rect);

  Rect reach = Rect.zero;
  Rect slot = Rect.zero;
  double texelsPerDp = 1;
  double heldFrost = 0;
  double blurSigma = 0;
  Size texels = Size.zero;
  Rect place = Rect.zero;
  int level = 0;
  ui.Image? atlas;
  _Behind? haze;
  Color veil = const Color(0x00000000);
}

/// The transform a layer gives its children now; [Layer.applyTransform] may answer from last frame.
Matrix4? _geometry(ContainerLayer layer) {
  Matrix4 applied(Layer child) {
    final matrix = Matrix4.identity();
    layer.applyTransform(child, matrix);
    return matrix;
  }

  return switch (layer) {
    TransformLayer(:final transform?, :final offset) =>
      offset == Offset.zero
          ? transform
          : (Matrix4.translationValues(offset.dx, offset.dy, 0)
              ..multiply(transform)),
    OffsetLayer(:final offset) || LeaderLayer(:final offset) =>
      offset == Offset.zero
          ? null
          : Matrix4.translationValues(offset.dx, offset.dy, 0),
    FollowerLayer(:final firstChild?) => applied(firstChild),
    _ => null,
  };
}

Matrix4 _within(ContainerLayer layer, Matrix4 toHost) {
  final geometry = _geometry(layer);
  return geometry == null ? toHost : (toHost.clone()..multiply(geometry));
}

bool _drawsOffscreen(Layer layer) {
  return switch (layer) {
    _LiquidGlassFadeLayer() => false,
    ClipRectLayer(:final clipBehavior) ||
    ClipRRectLayer(:final clipBehavior) ||
    ClipRSuperellipseLayer(:final clipBehavior) ||
    ClipPathLayer(
      :final clipBehavior,
    ) => clipBehavior == Clip.antiAliasWithSaveLayer,
    OpacityLayer(:final alpha) => alpha != null && alpha < 255,
    ColorFilterLayer() ||
    ImageFilterLayer() ||
    ShaderMaskLayer() ||
    BackdropFilterLayer() => true,
    _ => false,
  };
}
