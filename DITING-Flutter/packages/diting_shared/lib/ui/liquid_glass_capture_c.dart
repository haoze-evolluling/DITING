// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'liquid_glass.dart';

/// Redraws onto a capture what a pane's root holds below it, for the root's own effect too.
class _Replay {
  _Replay(this.canvas, this.drawn, this.entry) : _toHost = [entry.rootToHost];

  final Canvas canvas;
  final List<Object?> drawn;
  final _Behind entry;
  final List<Matrix4> _toHost;

  // A layer's effects apply only once something under it draws.
  final _entered = <(ContainerLayer, Matrix4?, bool)>[];
  final _saves = <int>[];

  Color? _veil;

  /// Replays the slot, answering the veil left for the shader to lay over it.
  Color run() {
    _walk(entry.root, root: true);
    return _veil ?? const Color(0x00000000);
  }

  bool _walk(ContainerLayer layer, {required bool root}) {
    if (!root && !entry.ancestors.contains(layer) && !_mayShow(layer)) {
      return false;
    }
    final geometry = _geometry(layer);
    final outer = _toHost.last;
    _toHost.add(geometry == null ? outer : (outer.clone()..multiply(geometry)));
    _entered.add((layer, geometry, root));
    var reached = false;
    for (Layer? child = layer.firstChild; child != null && !reached;) {
      switch (child) {
        case _ when identical(child, entry.pane):
          reached = true;
        case final _LiquidGlassLayer pane
            when pane._capturedPass == _LiquidGlassHostLayer._pass:
          if (pane._captured case final picture? when _shows(pane.rect)) {
            _draw(picture);
          }
        case final PictureLayer recorded:
          if (recorded.picture case final picture?
              when _shows(recorded.canvasBounds.inflate(_overflow))) {
            _draw(picture);
          }
        case final _LiquidGlassVeilLayer veil when _liesEvenly(veil):
          final under = _veil;
          _veil = under == null
              ? veil.color
              : Color.alphaBlend(veil.color, under);
        case final ContainerLayer container:
          reached = _walk(container, root: false);
      }
      child = child.nextSibling;
    }
    _leave();
    _toHost.removeLast();
    return reached;
  }

  bool _mayShow(ContainerLayer layer) {
    if (layer is OpacityLayer && layer.alpha == 0) {
      return false;
    }
    final clip = layer.describeClipBounds();
    return clip == null || _shows(clip);
  }

  bool _shows(Rect bounds) =>
      MatrixUtils.transformRect(_toHost.last, bounds).overlaps(entry.slot);

  bool _liesEvenly(_LiquidGlassVeilLayer veil) {
    final toHost = _toHost.last;
    final m = toHost.storage;
    if (m[1] != 0 ||
        m[4] != 0 ||
        m[3] != 0 ||
        m[7] != 0 ||
        !_encloses(MatrixUtils.transformRect(toHost, veil.rect), entry.slot)) {
      return false;
    }
    for (final (index, (layer, _, root)) in _entered.indexed) {
      final clip = layer.describeClipBounds();
      if (!root && _effectOf(layer) != null ||
          clip != null &&
              !_encloses(
                MatrixUtils.transformRect(_toHost[index + 1], clip),
                entry.slot,
              )) {
        return false;
      }
    }
    return true;
  }

  void _draw(ui.Picture picture) {
    // What the canvas has applied so far lay over the veil too, and neither
    // tints nor cuts it.
    if (_veil case final veil?) {
      canvas.drawPaint(Paint()..color = veil);
      drawn.add(veil);
      _veil = null;
    }
    while (_saves.length < _entered.length) {
      _saves.add(_apply(_entered[_saves.length]));
    }
    final shift = _wholeTexelShift();
    canvas
      ..save()
      ..translate(shift.dx, shift.dy)
      ..drawPicture(picture)
      ..restore();
    drawn.add(picture);
  }

  Offset _wholeTexelShift() {
    final m = _toHost.last.storage;
    if (m[1] != 0 || m[4] != 0 || m[3] != 0 || m[7] != 0) {
      return Offset.zero;
    }
    final scale = entry.texelsPerDp;
    double by(double translation, double stretch) {
      final texels = translation * scale;
      return stretch == 0
          ? 0
          : (texels.roundToDouble() - texels) / (scale * stretch);
    }

    return Offset(by(m[12], m[0]), by(m[13], m[5]));
  }

  int _apply((ContainerLayer, Matrix4?, bool) entered) {
    final (layer, geometry, root) = entered;
    var saves = 0;
    if (geometry != null) {
      canvas
        ..save()
        ..transform(geometry.storage);
      drawn.addAll(geometry.storage);
      saves++;
    }
    final effect = root ? null : _effectOf(layer);
    if (effect case (final paint, final key)?) {
      canvas.saveLayer(null, paint);
      drawn
        ..add(layer.runtimeType)
        ..add(key);
      saves++;
    }
    if (_clip(layer)) {
      saves++;
    }
    return saves;
  }

  static (Paint, Object?)? _effectOf(ContainerLayer layer) => switch (layer) {
    OpacityLayer(:final alpha?) when alpha < 255 => (
      Paint()..color = Color.fromARGB(alpha, 0, 0, 0),
      alpha,
    ),
    ColorFilterLayer(:final colorFilter?) => (
      Paint()..colorFilter = colorFilter,
      colorFilter,
    ),
    ImageFilterLayer(:final imageFilter?) => (
      Paint()..imageFilter = imageFilter,
      imageFilter,
    ),
    ShaderMaskLayer(:final shader) => (Paint(), shader),
    _ => null,
  };

  bool _clip(ContainerLayer layer) {
    final Object clip;
    switch (layer) {
      case ClipRectLayer(:final clipRect?, :final clipBehavior)
          when clipBehavior != Clip.none:
        canvas
          ..save()
          ..clipRect(clipRect, doAntiAlias: clipBehavior != Clip.hardEdge);
        clip = clipRect;
      case ClipRSuperellipseLayer(
            :final clipRSuperellipse?,
            :final clipBehavior,
          )
          when clipBehavior != Clip.none:
        canvas
          ..save()
          ..clipRSuperellipse(
            clipRSuperellipse,
            doAntiAlias: clipBehavior != Clip.hardEdge,
          );
        clip = clipRSuperellipse;
      case ClipPathLayer(:final clipPath?, :final clipBehavior)
          when clipBehavior != Clip.none:
        canvas
          ..save()
          ..clipPath(clipPath, doAntiAlias: clipBehavior != Clip.hardEdge);
        clip = clipPath;
      default:
        // Lib clips to no rounded rect, so a package's clips by its bounds here.
        final bounds = layer.describeClipBounds();
        if (bounds == null) {
          return false;
        }
        canvas
          ..save()
          ..clipRect(bounds);
        clip = bounds;
    }
    drawn.add(clip);
    return true;
  }

  void _leave() {
    final (layer, _, root) = _entered.removeLast();
    if (_saves.length <= _entered.length) {
      return;
    }
    final saves = _saves.removeLast();
    if (layer
        case ShaderMaskLayer(
          :final shader?,
          :final maskRect?,
          :final blendMode?,
        )
        when !root) {
      canvas
        ..translate(maskRect.left, maskRect.top)
        ..drawRect(
          Offset.zero & maskRect.size,
          Paint()
            ..shader = shader
            ..blendMode = blendMode,
        );
      drawn
        ..add(maskRect)
        ..add(blendMode);
    }
    for (var index = 0; index < saves; index++) {
      canvas.restore();
    }
    drawn.add(saves);
  }
}
