// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

class _PopupUnfoldNotification extends Notification {
  const _PopupUnfoldNotification();
}

typedef _PlatterGlass = ({
  LiquidGlassStyle from,
  LiquidGlassStyle to,
  LiquidGlassRim rim,
  bool coarse,
});

/// The press that opened a popup on its control's pointer down. Its events
/// keep reaching the control, which hands them on for the menu to follow.
class _CarriedPress {
  ValueSetter<Offset>? onMove;
  ValueSetter<Offset>? onRelease;
  VoidCallback? onCancel;
}

/// The part of the popup's box that returns into its control, when not all
/// of it: a menu returns its open sub menu alone, as iOS does.
class _PopupSurface {
  Rect? Function(RenderBox popup)? rectIn;
}

class _PopupScope extends InheritedWidget {
  const _PopupScope({
    required this.platter,
    required this.press,
    required this.surface,
    required this.runPicked,
    required super.child,
  });

  final ValueListenable<bool> platter;
  final _CarriedPress press;
  final _PopupSurface surface;
  final ValueSetter<VoidCallback> runPicked;

  static _PopupScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PopupScope>();

  @override
  bool updateShouldNotify(_PopupScope oldWidget) =>
      platter != oldWidget.platter ||
      press != oldWidget.press ||
      surface != oldWidget.surface ||
      runPicked != oldWidget.runPicked;
}

class _PopupMorph extends SingleChildRenderObjectWidget {
  const _PopupMorph({
    required this.anchor,
    required this.animation,
    required this.platter,
    required this.surface,
    required this.sourceColor,
    required this.sourceImage,
    required this.surfaceColor,
    required this.shadows,
    required this.glass,
    super.child,
  });

  final Rect anchor;
  final Animation<double> animation;
  final ValueListenable<bool> platter;
  final _PopupSurface surface;
  final Color sourceColor;
  final ValueListenable<ui.Image?>? sourceImage;
  final Color surfaceColor;
  final List<BoxShadow> shadows;

  /// The platter's glass as it leaves the anchor and as it lands on the card,
  /// or null for a [surfaceColor] fill.
  final _PlatterGlass? glass;

  @override
  _RenderPopupMorph createRenderObject(BuildContext context) {
    return _RenderPopupMorph(
      anchor: anchor,
      animation: animation,
      platter: platter,
      surface: surface,
      sourceColor: sourceColor,
      sourceImage: sourceImage,
      surfaceColor: surfaceColor,
      shadows: shadows,
      glass: glass,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPopupMorph renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..animation = animation
      ..platter = platter
      ..surface = surface
      ..sourceColor = sourceColor
      ..sourceImage = sourceImage
      ..surfaceColor = surfaceColor
      ..shadows = shadows
      ..glass = glass;
  }
}

typedef _MorphFrame = ({double time, bool platter});

typedef _Opening = ({
  Rect platter,
  double radius,
  Rect? droplet,
  double progress,
});

/// Grows the popup out of its anchor the way iOS 27 menus leave their button,
/// and returns it into its control, as one drop of glass with it, the content
/// blurring out first; with no control to return into, the popup shrinks
/// toward its anchor as it fades.
class _RenderPopupMorph extends RenderProxyBox {
  _RenderPopupMorph({
    required Rect anchor,
    required Animation<double> animation,
    required ValueListenable<bool> platter,
    required this.surface,
    required Color sourceColor,
    required ValueListenable<ui.Image?>? sourceImage,
    required Color surfaceColor,
    required List<BoxShadow> shadows,
    required _PlatterGlass? glass,
  }) : _anchor = anchor,
       _animation = animation,
       _platter = platter,
       _sourceColor = sourceColor,
       _sourceImage = sourceImage,
       _surfaceColor = surfaceColor,
       _shadows = shadows,
       _glass = glass;

  late final _pane = LiquidGlassPane(markNeedsPaint);

  _PopupSurface surface;

  Rect _anchor;

  set anchor(Rect value) {
    if (value == _anchor) {
      return;
    }
    _anchor = value;
    markNeedsPaint();
  }

  Animation<double> _animation;

  set animation(Animation<double> value) {
    if (value == _animation) {
      return;
    }
    if (attached) {
      _animation
        ..removeListener(markNeedsPaint)
        ..removeStatusListener(_handleStatusChanged);
      value
        ..addListener(markNeedsPaint)
        ..addStatusListener(_handleStatusChanged);
    }
    _animation = value;
    markNeedsPaint();
  }

  _MorphFrame? _closingFrame;
  double _closingFrom = 1;
  Rect? _closingSurface;

  void _handleStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.reverse) {
      return;
    }
    _closingFrom = _animation.value;
    _closingFrame = _frame();
    _closingSurface = hasSize ? surface.rectIn?.call(this) : null;
  }

  /// Where the opening stands, or null once it has settled.
  _MorphFrame? _frame() {
    if (_animation.value >= 1) {
      return null;
    }
    return (time: _animation.value * _openSeconds, platter: _platter.value);
  }

  ValueListenable<bool> _platter;

  set platter(ValueListenable<bool> value) {
    if (value == _platter) {
      return;
    }
    if (attached) {
      _platter.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _platter = value;
    markNeedsPaint();
  }

  Color _sourceColor;

  set sourceColor(Color value) {
    if (value == _sourceColor) {
      return;
    }
    _sourceColor = value;
    markNeedsPaint();
  }

  ValueListenable<ui.Image?>? _sourceImage;

  set sourceImage(ValueListenable<ui.Image?>? value) {
    if (value == _sourceImage) {
      return;
    }
    if (attached) {
      _sourceImage?.removeListener(markNeedsPaint);
      value?.addListener(markNeedsPaint);
    }
    _sourceImage = value;
    markNeedsPaint();
  }

  Color _surfaceColor;

  set surfaceColor(Color value) {
    if (value == _surfaceColor) {
      return;
    }
    _surfaceColor = value;
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

  _PlatterGlass? _glass;

  set glass(_PlatterGlass? value) {
    if (value == _glass) {
      return;
    }
    _glass = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation
      ..addListener(markNeedsPaint)
      ..addStatusListener(_handleStatusChanged);
    _platter.addListener(markNeedsPaint);
    _sourceImage?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation
      ..removeListener(markNeedsPaint)
      ..removeStatusListener(_handleStatusChanged);
    _platter.removeListener(markNeedsPaint);
    _sourceImage?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _pane.dispose();
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  /// The anchor in this box's coordinates; it comes in those of the layout
  /// box that places this one.
  Rect get _localAnchor =>
      _anchor.shift(-(parentData! as BoxParentData).offset);

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }
    if (_animation.status != AnimationStatus.reverse) {
      _paintFrame(context, offset, _frame());
      return;
    }
    final frame = _closingFrame;
    final from = _closingFrom;
    final dismissal = from <= 0
        ? 1.0
        : (1 - _animation.value / from).clamp(0.0, 1.0);
    if (_sourceImage != null) {
      _paintReturn(context, offset, frame, dismissal * _dismissSeconds);
      return;
    }
    final shrink = Curves.easeOut.transform(dismissal);
    final scale = lerpDouble(1, _dismissScale, shrink)!;
    final anchor = _localAnchor.center;
    final origin = Offset(
      anchor.dx.clamp(0.0, size.width),
      anchor.dy.clamp(0.0, size.height),
    );
    final transform = Matrix4.translationValues(origin.dx, origin.dy, 0)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1);
    context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => LiquidGlassFade.push(
        context,
        offset,
        Color.getAlphaFromOpacity(1 - shrink),
        (context, offset) => _paintFrame(context, offset, frame),
      ),
    );
  }

  void _paintFrame(PaintingContext context, Offset offset, _MorphFrame? frame) {
    final child = this.child!;
    if (frame == null || size.isEmpty) {
      _pane.clear();
      context.paintChild(child, offset);
      return;
    }
    final anchor = _localAnchor;
    final bounds = Offset.zero & size;
    final (:platter, :radius, :droplet, :progress) = _openingOf(
      frame.time,
      bounds,
    );
    final sourceImage = _sourceImage;
    final image = sourceImage?.value;
    // The source control stays visible until its snapshot exists, so the
    // platter would only cover it.
    if (sourceImage != null && image == null) {
      return;
    }
    final content = _contentTransform(platter, platter.width / size.width);
    // The card paints the same surface and shadow as the platter, so once a
    // sub menu leaves the root's bounds, the platter steps aside instead of
    // clipping the levels until the springs settle.
    if (!frame.platter) {
      _pane.clear();
      context.pushTransform(
        needsCompositing,
        offset,
        content,
        (context, offset) => context.paintChild(child, offset),
      );
      return;
    }
    final glass = _glass;
    final settled = progress.clamp(0.0, 1.0);
    final clip = AppShape.all(radius).getOuterPath(platter);
    final depth = droplet == null
        ? _rimDepth
        : gooPairDepth(platter, radius, droplet, _dropletBlend);
    final merged = depth >= 0;
    final outline = merged
        ? clip
        : gooPairOutline(
            platter,
            radius,
            droplet!,
            _dropletBlend,
            coarse: glass?.coarse ?? false,
          );
    final rim = merged
        ? glass?.rim.scale(settled * math.min(1.0, depth / _rimDepth))
        : null;
    final path = outline.shift(offset);
    if (glass != null) {
      final shape = outline.getBounds();
      // Frosted as the card and shadowed after, so one capture serves the morph.
      _pane.paint(
        context,
        (merged ? platter : shape).shift(offset),
        shape: merged
            ? LiquidGlassCorners.circular(radius)
            : LiquidGlassGoo(
                outline.shift(-shape.topLeft),
                [platter.shift(-shape.topLeft), droplet!.shift(-shape.topLeft)],
                const [_dropletBlend],
                firstRadius: math.max(radius, 1e-3),
              ),
        style: LiquidGlassStyle.lerp(
          glass.from,
          glass.to,
          settled,
        ).copyWith(blur: glass.to.blur),
        hold: bounds
            .expandToInclude(anchor)
            .inflate(size.longestSide * _overshootPerLongestSide)
            .shift(offset),
        rim: rim,
      );
    }
    _paintShadows(context.canvas, path, platter.shift(offset), radius, settled);
    final Color fill;
    if (glass == null) {
      fill = Color.lerp(_sourceColor, _surfaceColor, settled)!;
    } else {
      fill = _sourceColor.withValues(alpha: _sourceColor.a * (1 - settled));
    }
    context.canvas.drawPath(path, Paint()..color = fill);
    rim?.paintLine(context.canvas, platter.shift(offset), radius);
    if (image != null && droplet != null) {
      final under = math.min(1.0, settled / _glyphUnderAt);
      _paintSource(
        context.canvas,
        image,
        droplet.shift(offset),
        1 - under,
        blur: _openContentBlur * under,
      );
    }
    if (settled > 0) {
      context.pushClipPath(
        needsCompositing,
        offset,
        bounds,
        clip,
        (context, offset) => _paintContent(
          context,
          offset,
          settled,
          math.sqrt(
            math.pow(_openContentBlur * (1 - settled), 2) +
                math.pow(
                  _openBlurBump * riseAndFall(frame.time, 0.069, 2.1),
                  2,
                ),
          ),
          content,
        ),
      );
    }
  }
}
