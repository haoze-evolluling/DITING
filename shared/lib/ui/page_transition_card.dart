part of 'page_transition.dart';

class _CardTransition extends SingleChildRenderObjectWidget {
  const _CardTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.overdrag,
    required this.coveringOverdrag,
    required this.radius,
    required this.settledFill,
    required this.receding,
    super.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;

  /// How far a drag has pulled the page, and the page over it, past rest.
  final ValueListenable<double> overdrag;
  final ValueListenable<double> coveringOverdrag;
  final BorderRadius radius;
  final Color settledFill;
  final ValueListenable<bool> receding;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final wallpaper = PageBackgroundScope.maybeOf(context)?.isActive ?? false;
    return _RenderCardTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      overdrag: overdrag,
      coveringOverdrag: coveringOverdrag,
      radius: radius,
      settledFill: settledFill,
      receding: receding,
      surface: wallpaper
          ? Colors.transparent
          : SurfaceLevel.page.colorOf(colorScheme),
      backdrop: wallpaper
          ? Colors.transparent
          : colorScheme.surfaceContainerLowest,
      shadow: colorScheme.brightness == Brightness.light,
      textDirection: Directionality.of(context),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardTransition renderObject,
  ) {
    final colorScheme = ColorScheme.of(context);
    final wallpaper = PageBackgroundScope.maybeOf(context)?.isActive ?? false;
    renderObject
      ..animation = animation
      ..secondaryAnimation = secondaryAnimation
      ..overdrag = overdrag
      ..coveringOverdrag = coveringOverdrag
      ..radius = radius
      ..settledFill = settledFill
      ..receding = receding
      ..surface = wallpaper
          ? Colors.transparent
          : SurfaceLevel.page.colorOf(colorScheme)
      ..backdrop = wallpaper
          ? Colors.transparent
          : colorScheme.surfaceContainerLowest
      ..shadow = colorScheme.brightness == Brightness.light
      ..textDirection = Directionality.of(context)
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderCardTransition extends RenderProxyBox {
  _RenderCardTransition({
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required ValueListenable<double> overdrag,
    required ValueListenable<double> coveringOverdrag,
    required BorderRadius radius,
    required Color settledFill,
    required ValueListenable<bool> receding,
    required Color surface,
    required Color backdrop,
    required bool shadow,
    required TextDirection textDirection,
    required double devicePixelRatio,
  }) : _animation = animation,
       _secondaryAnimation = secondaryAnimation,
       _overdrag = overdrag,
       _coveringOverdrag = coveringOverdrag,
       _radius = radius,
       _settledFill = settledFill,
       _receding = receding,
       _surface = surface,
       _backdrop = backdrop,
       _shadow = shadow,
       _textDirection = textDirection,
       _devicePixelRatio = devicePixelRatio;

  Animation<double> _animation;
  set animation(Animation<double> value) {
    if (identical(value, _animation)) {
      return;
    }
    if (attached) {
      _unlisten();
    }
    _animation = value;
    if (attached) {
      _listen();
    }
    markNeedsPaint();
  }

  Animation<double> _secondaryAnimation;
  set secondaryAnimation(Animation<double> value) {
    if (identical(value, _secondaryAnimation)) {
      return;
    }
    if (attached) {
      _unlisten();
    }
    _secondaryAnimation = value;
    if (attached) {
      _listen();
    }
    markNeedsPaint();
  }

  ValueListenable<double> _overdrag;
  set overdrag(ValueListenable<double> value) {
    if (identical(value, _overdrag)) {
      return;
    }
    if (attached) {
      _overdrag.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _overdrag = value;
    markNeedsPaint();
  }

  ValueListenable<double> _coveringOverdrag;
  set coveringOverdrag(ValueListenable<double> value) {
    if (identical(value, _coveringOverdrag)) {
      return;
    }
    if (attached) {
      _coveringOverdrag.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _coveringOverdrag = value;
    markNeedsPaint();
  }

  BorderRadius _radius;
  set radius(BorderRadius value) {
    if (value == _radius) {
      return;
    }
    _radius = value;
    markNeedsPaint();
  }

  Color _settledFill;
  set settledFill(Color value) {
    if (value == _settledFill) {
      return;
    }
    _settledFill = value;
    markNeedsPaint();
  }

  ValueListenable<bool> _receding;
  set receding(ValueListenable<bool> value) {
    if (identical(value, _receding)) {
      return;
    }
    if (attached) {
      _receding.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _receding = value;
    markNeedsPaint();
  }

  Color _surface;
  set surface(Color value) {
    if (value == _surface) {
      return;
    }
    _surface = value;
    markNeedsPaint();
  }

  Color _backdrop;
  set backdrop(Color value) {
    if (value == _backdrop) {
      return;
    }
    _backdrop = value;
    markNeedsPaint();
  }

  bool _shadow;
  set shadow(bool value) {
    if (value == _shadow) {
      return;
    }
    _shadow = value;
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

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final _clipLayer = LayerHandle<ClipRSuperellipseLayer>();
  final _transformLayer = LayerHandle<TransformLayer>();

  bool get _moving =>
      !_animation.isCompleted || !_secondaryAnimation.isDismissed;

  bool get _recedes => _receding.value;

  double get _covered => _secondaryAnimation.value + _coveringOverdrag.value;

  double get _dx {
    final width = size.width;
    final slide = _recedes ? 0.0 : cardCoveredSlide * width * _covered;
    final dx = (1 - _animation.value - _overdrag.value) * width - slide;
    // On whole physical pixels a snapshot is drawn as sharp as the page.
    final snapped =
        (dx * _devicePixelRatio).roundToDouble() / _devicePixelRatio;
    return _textDirection == TextDirection.rtl ? -snapped : snapped;
  }

  Rect get _card {
    final page = Offset.zero & size;
    final card = _recedes
        ? recededRect(page, size, _secondaryAnimation.value)
        : page;
    return card.shift(Offset(_dx, 0));
  }

  Matrix4 _childTransform(Rect card) {
    final scale = card.width / size.width;
    return Matrix4.translationValues(card.left, card.top, 0)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _handleStatus(AnimationStatus _) => markNeedsSemanticsUpdate();

  void _listen() {
    for (final animation in [_animation, _secondaryAnimation]) {
      animation
        ..addListener(markNeedsPaint)
        ..addStatusListener(_handleStatus);
    }
    _receding.addListener(markNeedsPaint);
    _overdrag.addListener(markNeedsPaint);
    _coveringOverdrag.addListener(markNeedsPaint);
  }

  void _unlisten() {
    for (final animation in [_animation, _secondaryAnimation]) {
      animation
        ..removeListener(markNeedsPaint)
        ..removeStatusListener(_handleStatus);
    }
    _receding.removeListener(markNeedsPaint);
    _overdrag.removeListener(markNeedsPaint);
    _coveringOverdrag.removeListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
  }

  @override
  void detach() {
    _unlisten();
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _transformLayer.layer = null;
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      return;
    }
    if (!_moving) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
      if (_settledFill.a > 0) {
        context.canvas.drawRect(offset & size, Paint()..color = _settledFill);
      }
      context.paintChild(child, offset);
      return;
    }
    final covered = _covered;
    final recedes = _recedes;
    final card = _card;
    // A card leaving while still covered, as in a second pop before the first
    // has ended, has the page below it beside it, not the empty backdrop.
    if (covered > 0 && _animation.isCompleted) {
      final screen = offset & size;
      if (recedes) {
        context.canvas.drawRect(screen, Paint()..color = _surface);
      } else {
        _paintBesideCard(context.canvas, screen, card.shift(offset));
      }
    }
    if (_shadow && !_animation.isCompleted) {
      _paintShadow(context.canvas, card.shift(offset));
    }
    void paintCard(PaintingContext context, Offset offset) {
      context.canvas.drawRect(card.shift(offset), Paint()..color = _surface);
      if (card.width == size.width) {
        _transformLayer.layer = null;
        context.paintChild(child, offset + card.topLeft);
        return;
      }
      _transformLayer.layer = context.pushTransform(
        needsCompositing,
        offset,
        _childTransform(card),
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _transformLayer.layer,
      );
    }

    // iOS shrinks the content of a page under a zoom but keeps its
    // background, so a receding page has no corners of its own.
    if (_radius == BorderRadius.zero || (recedes && _animation.isCompleted)) {
      _clipLayer.layer = null;
      paintCard(context, offset);
    } else {
      _clipLayer.layer = context.pushClipRSuperellipse(
        needsCompositing,
        offset,
        card,
        _radius.toRSuperellipse(card),
        paintCard,
        oldLayer: _clipLayer.layer,
      );
    }
    if (covered > 0) {
      final dim = recedes ? _recededDim : cardCoveredDim;
      context.canvas.drawRect(
        offset & size,
        Paint()..color = dim.withValues(alpha: dim.a * math.min(covered, 1)),
      );
    }
  }

  void _paintShadow(Canvas canvas, Rect card) {
    final rtl = _textDirection == TextDirection.rtl;
    final edge = rtl ? card.right : card.left;
    final end = edge + (rtl ? 3 : -3) * _cardShadowSigma;
    final top = card.top + (rtl ? _radius.topRight.y : _radius.topLeft.y);
    final bottom =
        card.bottom - (rtl ? _radius.bottomRight.y : _radius.bottomLeft.y);
    if (bottom <= top) {
      return;
    }
    canvas.drawRect(
      Rect.fromLTRB(math.min(edge, end), top, math.max(edge, end), bottom),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(edge, 0),
          Offset(end, 0),
          _cardShadowColors,
          _cardShadowStops,
        ),
    );
  }

  /// Only the uncovered strip and corners take the backdrop; each piece reaches
  /// a pixel under the card so its antialiased edge stays off the root.
  void _paintBesideCard(Canvas canvas, Rect screen, Rect card) {
    final paint = Paint()..color = _backdrop;
    final radius = _radius;
    for (final rect in [
      Rect.fromLTRB(screen.left, screen.top, card.left + 1, screen.bottom),
      Rect.fromLTRB(card.right - 1, screen.top, screen.right, screen.bottom),
      Rect.fromLTWH(
        card.left,
        card.top,
        radius.topLeft.x + 1,
        radius.topLeft.y + 1,
      ),
      Rect.fromLTRB(
        card.right - radius.topRight.x - 1,
        card.top,
        card.right,
        card.top + radius.topRight.y + 1,
      ),
      Rect.fromLTRB(
        card.left,
        card.bottom - radius.bottomLeft.y - 1,
        card.left + radius.bottomLeft.x + 1,
        card.bottom,
      ),
      Rect.fromLTRB(
        card.right - radius.bottomRight.x - 1,
        card.bottom - radius.bottomRight.y - 1,
        card.right,
        card.bottom,
      ),
    ]) {
      final visible = rect.intersect(screen);
      if (!visible.isEmpty) {
        canvas.drawRect(visible, paint);
      }
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_moving && !_measuringAtRest) {
      transform.multiply(_childTransform(_card));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) {
      return false;
    }
    return result.addWithPaintTransform(
      transform: _moving ? _childTransform(_card) : null,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }
}
