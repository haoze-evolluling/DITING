// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'snap_sheet.dart';

/// Detents resolve every frame; a drag below the shortest moves the route.
class _SheetModel extends ChangeNotifier {
  _SheetModel({required this.route, required TickerProvider vsync})
    : detents = route.detents,
      fitsContent = route.fitsContent {
    _ticker = vsync.createTicker(_tick);
    route.animation!.addListener(_syncLift);
  }

  final SnapSheetRoute<dynamic> route;
  final List<double> detents;
  final bool fitsContent;

  late final Ticker _ticker;
  Duration? _lastTick;
  bool _disposed = false;
  bool _openPending = false;

  final settling = ValueNotifier(false);
  final open = ValueNotifier(false);

  final lift = ValueNotifier(0.0);
  bool _liftFollows = false;

  double _available = 0;
  double _keyboard = 0;

  double _fitHeight = double.infinity;
  double _filledRoom = 0;
  double? _measureRoom;
  double _contentRoom = 0;
  double _contentLimit = 0;
  double contentHeight = 0;
  _RenderSheetContent? _content;

  _Activity _activity = const _Resting(0);

  Animation<double> get _presentation => route.animation!;

  bool get _closing => _presentation.status == AnimationStatus.reverse;

  /// The tallest a sheet may reach, a peek below the top of the space it gets.
  double get _peak => math.max(_available - stackedSheetPeek, 0.0);

  /// The tallest detent, lifted by the keyboard up to a peek below the top.
  double get _top {
    final peak = _peak;
    final tallest = detents.last * _available;
    final room = clampDouble(peak - tallest, 0, _peakEase);
    return peak - _rounded(peak - tallest - _keyboard, room);
  }

  /// A fit sheet follows its content up to each detent, never below the shortest.
  List<double> get _stops {
    final shortest = detents.first * _available;
    final top = _top;
    return [
      for (final fraction in detents)
        math.max(_stopFor(fraction * _available, shortest, top), _keyboard) -
            _keyboard,
    ];
  }

  double _stopFor(double detent, double shortest, double top) {
    final rest = clampDouble(_fitHeight, shortest, detent);
    final blank = rest - math.min(_fitHeight, rest);
    return math.min(top, rest + _rounded(_keyboard - blank, blank / 2));
  }

  double get minHeight => _stops.first;

  double get maxHeight => _stops.last;

  double get height => _heightIn(_stops);

  double _heightIn(List<double> stops) => switch (_activity) {
    _Resting(:final stop) => stops[stop],
    _Holding(:final height, :final overshoot) =>
      clampDouble(height, stops.first, stops.last) +
          _rubberBand(overshoot, _stretchExtent(stops.last)),
    _Settling(:final stop, :final offset) => stops[stop] + offset,
  };

  /// What the sheet may stretch past its tallest detent, up to the peek.
  double _stretchExtent(double tallest) =>
      clampDouble(_peak - _keyboard - tallest, 0, _rubberBandExtent);

  bool get isSettling => _activity is _Settling;

  bool get isOpen {
    final stops = _stops;
    final height = switch (_activity) {
      _Resting(:final stop) || _Settling(:final stop) => stops[stop],
      _Holding(:final height) => height,
    };
    return height >= stops.last - precisionErrorTolerance;
  }

  /// At rest the content is measured up to the detent; moving, at what it shows.
  double beginLayout(double available, double keyboard) {
    _available = available;
    _keyboard = keyboard;
    final stops = _stops;
    final height = _heightIn(stops);
    final measured = switch (_activity) {
      _ when height >= stops.last - precisionErrorTolerance =>
        detents.length - 1,
      _Resting(:final stop) => stop,
      _ => null,
    };
    _contentRoom = measured == null || !fitsContent
        ? math.max(height, stops.first)
        : math.max(
            math.min(detents[measured] * available, _top - keyboard),
            height,
          );
    if (!fitsContent || !_isShortOfLimit) {
      _contentLimit = _contentRoom;
    }
    return _contentLimit;
  }

  bool get _isShortOfLimit =>
      contentHeight <
      math.min(_contentRoom, _contentLimit) - precisionErrorTolerance;

  bool releaseLimit() {
    if (_contentLimit == _contentRoom || _isShortOfLimit) {
      return false;
    }
    _contentLimit = _contentRoom;
    return true;
  }

  bool fitContent() {
    final limit = _contentLimit;
    final fills = contentHeight >= limit - precisionErrorTolerance;
    final fit = !fills
        ? contentHeight
        : _fitHeight >= limit - precisionErrorTolerance
        ? _fitHeight
        : double.infinity;
    return _refit(fit);
  }

  double get _tallestRoom =>
      math.min(detents.last * _available, _top - _keyboard);

  /// Measure up to the tallest detent before moving, so a release lands where it ends.
  void _measureBeforeMoving() {
    final room = _tallestRoom;
    if (!fitsContent ||
        _fitHeight.isFinite ||
        _contentLimit >= room - precisionErrorTolerance ||
        _filledRoom >= room - precisionErrorTolerance) {
      return;
    }
    _measureRoom = room;
  }

  void _measured(double natural, double room) {
    final fills = natural >= room - precisionErrorTolerance;
    _refit(fills ? double.infinity : natural);
    if (fills) {
      _filledRoom = room;
    }
  }

  bool _refit(double fit) {
    if (fit == _fitHeight) {
      return false;
    }
    _filledRoom = 0;
    final shown = height;
    _fitHeight = fit;
    _keepSettlingFrom(shown);
    return true;
  }

  void _keepSettlingFrom(double shown) {
    final activity = _activity;
    if (activity is! _Settling) {
      return;
    }
    final offset = shown - _stops[activity.stop];
    final launch = _launch(-offset, activity.velocity, overshoots: true);
    _activity = _Settling(activity.stop, offset, launch.velocity, launch.ratio);
  }

  void endLayout() {
    _syncLift();
    _syncOpen();
  }

  void _syncLift() {
    if (_closing) {
      return;
    }
    lift.value = _liftFollows
        ? (1 - _presentation.value) * (minHeight + _keyboard)
        : 0;
  }

  void _syncOpen() {
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      open.value = isOpen;
      return;
    }
    if (_openPending || open.value == isOpen) {
      return;
    }
    _openPending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _openPending = false;
      if (!_disposed) {
        open.value = isOpen;
      }
    });
  }

  void _changed() {
    notifyListeners();
    _syncOpen();
  }

  void _hold({required bool dragged}) {
    final activity = _activity;
    if (activity is _Holding && activity.dragged == dragged) {
      return;
    }
    final stops = _stops;
    final height = _heightIn(stops);
    _stopTicker();
    _activity = _Holding(
      math.min(height, stops.last),
      dragged: dragged,
      overshoot: _overshootOf(height - stops.last, _stretchExtent(stops.last)),
    );
    if (dragged) {
      _measureBeforeMoving();
    }
  }

  /// Returns how much of [delta], positive to grow, the sheet took: what is
  /// left past the tallest detent goes to the content, or [stretches] it.
  double dragBy(double delta, {bool stretches = false}) {
    // A drag the pop caught mid-gesture would hold the route from leaving.
    if (_closing) {
      return delta;
    }
    _hold(dragged: true);
    final held = _activity as _Holding;
    final stops = _stops;
    held.height = clampDouble(held.height, stops.first, stops.last);
    final extent = stops.first + _keyboard;
    var rest = delta;
    if (rest < 0) {
      final relax = math.max(rest, -held.overshoot);
      held.overshoot += relax;
      rest -= relax;
      final shrink = math.max(rest, math.min(stops.first - held.height, 0.0));
      held.height += shrink;
      rest -= shrink;
      if (rest < 0 && extent > 0) {
        _liftFollows = true;
        route._drag(math.max(_presentation.value + rest / extent, 0));
        rest = 0;
      }
    } else if (rest > 0) {
      final shown = _presentation.value;
      if (shown < 1 && extent > 0) {
        final restored = math.min(rest / extent, 1 - shown);
        route._drag(shown + restored);
        rest -= restored * extent;
      }
      final grow = math.min(rest, math.max(stops.last - held.height, 0.0));
      held.height += grow;
      rest -= grow;
      if (stretches && _stretchExtent(stops.last) > 0) {
        held.overshoot += rest;
        rest = 0;
      }
    }
    _changed();
    return delta - rest;
  }

  void dragEnd(double velocity) {
    final activity = _activity;
    if (activity is! _Holding || !activity.dragged) {
      return;
    }
    if (_closing) {
      _hold(dragged: false);
      return;
    }
    final stops = _stops;
    final shown = _presentation.value;
    final extent = stops.first + _keyboard;
    final position = shown < 1 ? extent * shown : _keyboard + _heightIn(stops);
    final projected = position + velocity * _projectionTime;
    var target = -1;
    var distance = projected.abs();
    for (final (index, stop) in stops.indexed) {
      final away = (stop + _keyboard - projected).abs();
      if (away < distance) {
        distance = away;
        target = index;
      }
    }
    if (target < 0) {
      _closeAt(velocity, extent);
    } else if (shown < 1) {
      _rest(0);
      route._restore(extent > 0 ? velocity / extent : 0);
    } else {
      _settleTo(target, velocity);
    }
  }

  void _closeAt(double velocity, double extent) {
    if (_presentation.value >= 1 &&
        height > minHeight + precisionErrorTolerance) {
      _settleTo(0, 0);
    } else {
      _rest(0);
    }
    route._close(extent > 0 ? velocity / extent : 0);
  }

  void settleTowards(double direction) {
    final stops = _stops;
    final height = _heightIn(stops);
    var target = 0;
    if (direction > 0) {
      target = stops.indexWhere(
        (stop) => stop > height + precisionErrorTolerance,
      );
      if (target < 0) {
        target = stops.length - 1;
      }
    } else if (direction < 0) {
      target = math.max(
        stops.lastIndexWhere((stop) => stop < height - precisionErrorTolerance),
        0,
      );
    }
    final current = switch (_activity) {
      _Resting(:final stop) || _Settling(:final stop) => stop,
      _Holding() => null,
    };
    if (current != null && stops[current] == stops[target]) {
      return;
    }
    _settleTo(target, 0);
  }

  void _settleTo(int stop, double velocity) {
    final stops = _stops;
    final offset = _heightIn(stops) - stops[stop];
    if (offset.abs() < _settleTolerance.distance &&
        velocity.abs() < _settleTolerance.velocity) {
      _rest(stop);
      return;
    }
    final launch = _launch(-offset, velocity, overshoots: true);
    _activity = _Settling(stop, offset, launch.velocity, launch.ratio);
    _measureBeforeMoving();
    settling.value = true;
    if (!_ticker.isActive) {
      _lastTick = SchedulerBinding.instance.currentSystemFrameTimeStamp;
      _ticker.start();
    }
    _changed();
  }

  void _tick(Duration _) {
    final activity = _activity;
    if (activity is! _Settling) {
      _stopTicker();
      return;
    }
    // Timed from the frame the settle began in, so its first frame moves.
    final now = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    final time =
        (now - (_lastTick ?? now)).inMicroseconds /
        Duration.microsecondsPerSecond;
    _lastTick = now;
    final spring = _SheetSpring(
      from: activity.offset,
      to: 0,
      velocity: activity.velocity,
      ratio: activity.ratio,
      tolerance: _settleTolerance,
    );
    if (spring.isDone(time)) {
      _rest(activity.stop);
      return;
    }
    activity
      ..offset = spring.x(time)
      ..velocity = spring.dx(time);
    _changed();
  }

  void _rest(int stop) {
    _stopTicker();
    _activity = _Resting(stop);
    _changed();
  }

  void _stopTicker() {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _lastTick = null;
    settling.value = false;
  }

  void stop() {
    if (_activity is _Settling) {
      _hold(dragged: false);
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    route.animation!.removeListener(_syncLift);
    _ticker.dispose();
    settling.dispose();
    open.dispose();
    lift.dispose();
    super.dispose();
  }
}
