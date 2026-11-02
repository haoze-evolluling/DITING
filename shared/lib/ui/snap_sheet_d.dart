// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'snap_sheet.dart';

/// Rounding may pick the other root where the discriminant vanishes.
class _SheetSpring extends Simulation {
  _SheetSpring({
    required double from,
    required this.to,
    required double velocity,
    required this.ratio,
    super.tolerance,
  }) : _start = from - to,
       _velocity = velocity;

  final double to;
  final double ratio;
  final double _start;
  final double _velocity;

  late final double _damped = _omega * math.sqrt(1 - ratio * ratio);

  double _offset(double time) {
    if (ratio >= 1) {
      return (_start + (_velocity + _omega * _start) * time) *
          math.exp(-_omega * time);
    }
    final sine = (_velocity + ratio * _omega * _start) / _damped;
    return math.exp(-ratio * _omega * time) *
        (_start * math.cos(_damped * time) + sine * math.sin(_damped * time));
  }

  /// Lands exactly on [to]; a controller would stop a tolerance short.
  @override
  double x(double time) => isDone(time) ? to : to + _offset(time);

  @override
  double dx(double time) {
    if (ratio >= 1) {
      return (_velocity - _omega * (_velocity + _omega * _start) * time) *
          math.exp(-_omega * time);
    }
    final sine = (_velocity + ratio * _omega * _start) / _damped;
    final decay = ratio * _omega;
    return math.exp(-decay * time) *
        ((sine * _damped - decay * _start) * math.cos(_damped * time) -
            (_start * _damped + decay * sine) * math.sin(_damped * time));
  }

  @override
  bool isDone(double time) =>
      nearZero(_offset(time), tolerance.distance) &&
      nearZero(dx(time), tolerance.velocity);
}

sealed class _Activity {
  const _Activity();
}

class _Resting extends _Activity {
  const _Resting(this.stop);

  final int stop;
}

class _Holding extends _Activity {
  _Holding(this.height, {required this.dragged, this.overshoot = 0});

  double height;
  double overshoot;
  final bool dragged;
}

class _Settling extends _Activity {
  _Settling(this.stop, this.offset, this.velocity, this.ratio);

  final int stop;
  double offset;
  double velocity;
  final double ratio;
}
