// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'navigation_dock.dart';

/// Lets a touch that misses the dock by at most [_hitSlop] still reach it.
class _HitSlop extends SingleChildRenderObjectWidget {
  const _HitSlop({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHitSlop();
}

class _RenderHitSlop extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (size.isEmpty ||
        !(Offset.zero & size).inflate(_hitSlop).contains(position)) {
      return false;
    }
    if (!hitTestChildren(result, position: _onSpine(position))) {
      return false;
    }
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  // A pill's rounded ends clip hit tests; its straight core never does.
  Offset _onSpine(Offset position) {
    final radius = size.shortestSide / 2;
    return Offset(
      position.dx.clamp(radius, size.width - radius),
      size.height / 2,
    );
  }
}

/// Grows under a press and stretches after a drag, as the bar's lens does; the press only paints.
class ElasticPress extends StatefulWidget {
  const ElasticPress({
    super.key,
    this.enabled = true,
    this.pullPastEdges = false,
    this.maxGrowth = _maxPressGrowth,
    this.maxPull,
    this.panelOf,
    required this.child,
  });

  /// Leaves a press on the button inside to the swell alone.
  static const buttonStyle = ButtonStyle(
    splashFactory: NoSplash.splashFactory,
    overlayColor: WidgetStateMapper<Color?>({
      WidgetState.pressed: Colors.transparent,
    }),
  );

  final bool enabled;
  final bool pullPastEdges;
  final double maxGrowth;
  final double? maxPull;

  final Rect Function(RenderBox box)? panelOf;

  final Widget child;

  static ElasticPressHandle? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<_ElasticPressState>();

  /// How far a full press scales a panel whose longest side is [side].
  static double growthOf(double side, {double maxGrowth = _maxPressGrowth}) =>
      math.min(_pressGrowth * 2, maxGrowth / side);

  static Rect paintBoundsOf(RenderBox box) {
    final bounds = Offset.zero & box.size;
    var painted = Matrix4.identity();
    RenderObject from = box;
    for (var node = box.parent; node != null; node = node.parent) {
      if (node is _RenderPressTransform && node.hasSize) {
        painted = node._transform.multiplied(
          from.getTransformTo(node).multiplied(painted),
        );
        from = node;
      }
    }
    final rest = Matrix4.tryInvert(box.getTransformTo(from));
    if (identical(from, box) || rest == null) {
      return bounds;
    }
    return MatrixUtils.transformRect(rest.multiplied(painted), bounds);
  }

  /// Calls [onMove] as presses around [box] move it, until the result is called.
  static VoidCallback followPresses(RenderObject box, VoidCallback onMove) {
    final presses = [
      for (var node = box.parent; node != null; node = node.parent)
        if (node is _RenderPressTransform) node,
    ];
    for (final press in presses) {
      press._followers.add(onMove);
    }
    return () {
      for (final press in presses) {
        press._followers.remove(onMove);
      }
    };
  }

  /// How far a press, never a hover, swells the nearest press around [box].
  static double liftOf(RenderBox box) {
    for (var node = box.parent; node != null; node = node.parent) {
      if (node is _RenderPressTransform) {
        return node._press;
      }
    }
    return 0;
  }

  @override
  State<ElasticPress> createState() => _ElasticPressState();
}

/// Drives an [ElasticPress] with a press it does not hear, at global positions.
abstract interface class ElasticPressHandle {
  void press(Offset position);

  void drag(Offset position);

  void release();

  void hover(bool entered);
}

class _ElasticPressState extends State<ElasticPress>
    with TickerProviderStateMixin
    implements ElasticPressHandle {
  late final _Spring _lift = _Spring(this, 0);
  late final _Spring _hover = _Spring(this, 0);
  late final _Spring _pullX = _Spring(this, 0);
  late final _Spring _pullY = _Spring(this, 0);
  late final Listenable _motion = Listenable.merge([
    _lift,
    _hover,
    _pullX,
    _pullY,
  ]);
  int? _pointer;
  var _hovers = 0;
  Offset _origin = Offset.zero;
  bool _releasing = false;

  @override
  void initState() {
    super.initState();
    _lift.addListener(_settle);
  }

  @override
  void dispose() {
    _lift.dispose();
    _hover.dispose();
    _pullX.dispose();
    _pullY.dispose();
    super.dispose();
  }

  void _swell(Offset origin) {
    _origin = origin;
    _releasing = false;
    _lift.springTo(1, _pressSpring);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabled ||
        _pointer != null ||
        event.buttons & kPrimaryButton == 0) {
      return;
    }
    _pointer = event.pointer;
    _swell(event.localPosition);
  }

  // A press removed mid-gesture still hears its moves and release.
  void _handlePointerMove(PointerMoveEvent event) {
    if (!mounted || event.pointer != _pointer) {
      return;
    }
    _pullToward(event.localPosition);
  }

  void _pullToward(Offset position) {
    final box = context.findRenderObject()! as RenderBox;
    final panel = widget.panelOf?.call(box) ?? Offset.zero & box.size;
    final limit = widget.maxPull ?? panel.shortestSide * _pullLimit;
    final pull = widget.pullPastEdges
        ? position -
              Offset(
                position.dx.clamp(panel.left, panel.right),
                position.dy.clamp(panel.top, panel.bottom),
              )
        : position - _origin;
    _pullX.springTo(_rubberBand(pull.dx, limit), _trackSpring);
    _pullY.springTo(_rubberBand(pull.dy, limit), _trackSpring);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!mounted || event.pointer != _pointer) {
      return;
    }
    _release();
  }

  void _release() {
    _pointer = null;
    _pullX.springTo(0, _pressSpring);
    _pullY.springTo(0, _pressSpring);
    _releasing = true;
    _settle();
  }

  // A tap lets go before the swell rises; it rises fully first, as UIKit does.
  void _settle() {
    if (!_releasing || _lift.value < _liftSnap) {
      return;
    }
    _releasing = false;
    _lift.springTo(0, _pressSpring);
  }

  Offset _localOf(Offset position) =>
      (context.findRenderObject()! as RenderBox).globalToLocal(position);

  @override
  void press(Offset position) {
    if (!widget.enabled) {
      return;
    }
    _swell(_localOf(position));
  }

  @override
  void drag(Offset position) => _pullToward(_localOf(position));

  @override
  void release() => _release();

  @override
  void hover(bool entered) {
    if (!mounted) {
      return;
    }
    _hovers = math.max(0, _hovers + (entered ? 1 : -1));
    _hover.springTo(
      widget.enabled && _hovers > 0 ? _hoverSwell : 0,
      _settleSpring,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (_, child) => _PressTransform(
          lift: _lift.value + (1 - _lift.value) * _hover.value,
          press: _lift.value,
          pull: Offset(_pullX.value, _pullY.value),
          maxGrowth: widget.maxGrowth,
          panelOf: widget.panelOf,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Lifts the [ElasticPress] around [child] part way while a pointer hovers over
/// it, as iPadOS lifts a button under its pointer.
class ElasticHover extends StatefulWidget {
  const ElasticHover({super.key, required this.child});

  final Widget child;

  @override
  State<ElasticHover> createState() => _ElasticHoverState();
}

class _ElasticHoverState extends State<ElasticHover> {
  ElasticPressHandle? _entered;

  void _handleEnter(PointerEnterEvent event) {
    if (_entered != null) {
      return;
    }
    _entered = ElasticPress.maybeOf(context)?..hover(true);
  }

  void _handleExit(PointerExitEvent event) => _leave();

  void _leave() {
    _entered?.hover(false);
    _entered = null;
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: widget.child,
    );
  }
}

/// Leaves the press inside to [ElasticPress]; a foreground color merges its buttonStyle.
class ElasticButton extends StatelessWidget {
  const ElasticButton({super.key, this.enabled = true, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElasticPress(
      enabled: enabled,
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        child: IconTheme(
          data: IconTheme.of(context),
          child: IconButtonTheme(
            data: IconButtonThemeData(
              style: ElasticPress.buttonStyle.merge(
                IconButtonTheme.of(context).style,
              ),
            ),
            child: FilledButtonTheme(
              data: FilledButtonThemeData(
                style: ElasticPress.buttonStyle.merge(
                  FilledButtonTheme.of(context).style,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _PressTransform extends SingleChildRenderObjectWidget {
  const _PressTransform({
    required this.lift,
    double? press,
    required this.pull,
    this.maxGrowth = _maxPressGrowth,
    this.panelOf,
    super.child,
  }) : press = press ?? lift;

  final double lift;
  final double press;
  final Offset pull;
  final double maxGrowth;
  final Rect Function(RenderBox box)? panelOf;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPressTransform(lift: lift, press: press, pull: pull)
      ..maxGrowth = maxGrowth
      ..panelOf = panelOf;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPressTransform renderObject,
  ) {
    renderObject
      ..lift = lift
      ..press = press
      ..pull = pull
      ..maxGrowth = maxGrowth
      ..panelOf = panelOf;
  }
}

class _RenderPressTransform extends RenderProxyBox {
  _RenderPressTransform({
    required double lift,
    required double press,
    required Offset pull,
  }) : _lift = lift,
       _press = press,
       _pull = pull;

  double _lift;
  double _press;
  Offset _pull;
  double maxGrowth = _maxPressGrowth;
  Rect Function(RenderBox box)? panelOf;
  final _followers = <VoidCallback>[];

  set lift(double value) {
    if (value == _lift) {
      return;
    }
    _lift = value;
    _moved();
  }

  set press(double value) {
    if (value == _press) {
      return;
    }
    _press = value;
    _moved();
  }

  set pull(Offset value) {
    if (value == _pull) {
      return;
    }
    _pull = value;
    _moved();
  }

  void _moved() {
    markNeedsPaint();
    for (final follower in _followers) {
      follower();
    }
  }

  Matrix4 get _transform {
    final panel = panelOf?.call(this) ?? Offset.zero & size;
    final swell =
        1 +
        _lift * ElasticPress.growthOf(panel.longestSide, maxGrowth: maxGrowth);
    final scaleX = swell * (1 + _pull.dx.abs() / panel.width * _pullStretch);
    final scaleY = swell * (1 + _pull.dy.abs() / panel.height * _pullStretch);
    final center = panel.center;
    return Matrix4.diagonal3Values(scaleX, scaleY, 1)..setTranslationRaw(
      center.dx * (1 - scaleX) + _pull.dx,
      center.dy * (1 - scaleY) + _pull.dy,
      0,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || size.isEmpty || (_lift == 0 && _pull == .zero)) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }
}
