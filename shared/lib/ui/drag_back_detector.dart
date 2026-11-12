part of 'drag_back.dart';

class _DragBackDetector extends StatefulWidget {
  const _DragBackDetector({required this.route, required this.child});

  final DragBackRouteMixin<dynamic> route;
  final Widget child;

  @override
  State<_DragBackDetector> createState() => _DragBackDetectorState();
}

class _DragBackDetectorState extends State<_DragBackDetector> {
  late final DragGestureRecognizer _recognizer;
  late final _DragBackRecognizer _directed;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    final route = widget.route;
    final DragGestureRecognizer recognizer;
    if (route.dragBackDownward) {
      final dismiss = _DismissGestureRecognizer(route: route, debugOwner: this);
      _directed = dismiss;
      recognizer = dismiss;
    } else {
      final back = _DragBackGestureRecognizer(route: route, debugOwner: this);
      _directed = back;
      recognizer = back;
    }
    _recognizer = recognizer
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    if (_dragging) {
      widget.route._abortDragBack();
    }
    super.dispose();
  }

  double get _towardEnd => switch (Directionality.of(context)) {
    TextDirection.rtl => -1,
    TextDirection.ltr => 1,
  };

  Offset _toLogical(Offset value) => Offset(value.dx * _towardEnd, value.dy);

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.route._canDragBack) {
      _directed.towardEnd = _towardEnd;
      _recognizer.addPointer(event);
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _dragging = true;
    widget.route._startDragBack(
      details.localPosition,
      context.size!,
      _directed.axis!,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragging) {
      return;
    }
    widget.route._updateDragBack(_toLogical(details.delta));
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.route._endDragBack(_toLogical(details.velocity.pixelsPerSecond));
  }

  void _handleDragCancel() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    widget.route._endDragBack(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

mixin _DragBackRecognizer on GestureRecognizer {
  double towardEnd = 1;

  Axis? get axis;
}

// Desktop text fields select with a pan, which accepts past the pan slop.
class _DragBackGestureRecognizer extends HorizontalDragGestureRecognizer
    with _DragBackRecognizer {
  _DragBackGestureRecognizer({required this.route, super.debugOwner}) {
    // Alone in the arena, it would win by default and start at once.
    onlyAcceptDragOnThreshold = true;
  }

  final DragBackRouteMixin<dynamic> route;

  @override
  Axis get axis => Axis.horizontal;

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return globalDistanceMoved * towardEnd >
        route.dragBackSlopOf(pointerDeviceKind, gestureSettings);
  }
}

/// iOS's zoom dismisses on a drag toward the reading end or down that keeps
/// within about 22° of its axis, and never on one with any upward part.
class _DismissGestureRecognizer extends PanGestureRecognizer
    with _DragBackRecognizer {
  _DismissGestureRecognizer({required this.route, super.debugOwner}) {
    onlyAcceptDragOnThreshold = true;
  }

  static const _lockSlope = 0.4;

  final DragBackRouteMixin<dynamic> route;
  @override
  Axis? axis;
  Offset? _down;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down = event.position;
    axis = null;
    super.addAllowedPointer(event);
  }

  Axis? _lockOf(Offset moved) {
    final along = moved.dx * towardEnd;
    if (moved.dy < 0) {
      return null;
    }
    if (along > 0 && moved.dy <= along * _lockSlope) {
      return Axis.horizontal;
    }
    if (moved.dy > 0 && moved.dx.abs() <= moved.dy * _lockSlope) {
      return Axis.vertical;
    }
    return null;
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _down;
    if (event is PointerMoveEvent && axis == null && down != null) {
      final moved = event.position - down;
      if (moved.distance > route.dragBackSlopOf(event.kind, gestureSettings)) {
        axis = _lockOf(moved);
        if (axis == null) {
          _down = null;
          resolve(GestureDisposition.rejected);
          return;
        }
      }
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => axis != null;
}

/// Trails a target on springs, on a ticker that keeps running so that a
/// target moved every frame still advances.
class _DragFollower {
  _DragFollower(this._navigator, this._onChanged) {
    _ticker = _navigator.createTicker(_tick);
  }

  final NavigatorState _navigator;
  final VoidCallback _onChanged;
  late final Ticker _ticker;
  Offset _value = Offset.zero;
  Offset _velocity = Offset.zero;
  SpringSimulation? _x;
  SpringSimulation? _y;
  Duration _now = Duration.zero;
  Duration _setOff = Duration.zero;
  double? _arrival;
  Completer<void>? _rest;

  Offset get value => _value;
  Offset get velocity => _velocity;
  bool get isMoving => _ticker.isActive;

  void reset() {
    stop();
    _value = Offset.zero;
    _velocity = Offset.zero;
  }

  Future<void> moveTo(
    Offset target,
    SpringDescription spring, {
    Offset? velocity,
    bool endsOnArrival = false,
  }) {
    final from = velocity ?? _velocity;
    _arrival = endsOnArrival && target.dx != _value.dx ? target.dx : null;
    _x = SpringSimulation(
      spring,
      _value.dx,
      target.dx,
      from.dx,
      snapToEnd: true,
    );
    _y = SpringSimulation(
      spring,
      _value.dy,
      target.dy,
      from.dy,
      snapToEnd: true,
    );
    if (_ticker.isActive) {
      _setOff = _now;
    } else {
      _now = Duration.zero;
      _setOff = Duration.zero;
      _ticker.start();
    }
    return (_rest ??= Completer<void>.sync()).future;
  }

  void stop() {
    _ticker.stop();
    _x = null;
    _y = null;
    _settle();
  }

  void _settle() {
    final rest = _rest;
    _rest = null;
    rest?.complete();
  }

  void _tick(Duration elapsed) {
    if (elapsed == Duration.zero) {
      _setOff = -frameIntervalOf(_navigator.context);
    }
    _now = elapsed;
    final x = _x!;
    final y = _y!;
    final time =
        (elapsed - _setOff).inMicroseconds / Duration.microsecondsPerSecond;
    final from = _value.dx;
    _value = Offset(x.x(time), y.x(time));
    _velocity = Offset(x.dx(time), y.dx(time));
    final arrival = _arrival;
    final arrived =
        arrival != null && (_value.dx - arrival) * (from - arrival) <= 0;
    if (arrived) {
      _value = Offset(arrival, _value.dy);
    }
    if (arrived || (x.isDone(time) && y.isDone(time))) {
      _velocity = Offset.zero;
      _ticker.stop();
      _onChanged();
      _settle();
      return;
    }
    _onChanged();
  }

  void dispose() {
    _ticker.dispose();
    _settle();
  }
}
