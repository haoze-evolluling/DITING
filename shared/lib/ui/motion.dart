// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

const fadeTabDuration = Duration(milliseconds: 220);
const fadeTabCurve = Curves.easeInOut;

Duration frameIntervalOf(BuildContext context) {
  final rate = View.maybeOf(context)?.display.refreshRate ?? 0;
  return rate > 0
      ? Duration(microseconds: Duration.microsecondsPerSecond ~/ rate)
      : Duration.zero;
}

/// Ends [simulation] at [end], where a controller would hold an overshoot.
class ArrivingSimulation extends Simulation {
  ArrivingSimulation(this.simulation, {required this.end})
    : _start = simulation.x(0),
      super(tolerance: simulation.tolerance);

  final Simulation simulation;
  final double end;
  final double _start;

  @override
  double x(double time) => simulation.x(time);

  @override
  double dx(double time) => simulation.dx(time);

  @override
  bool isDone(double time) =>
      simulation.isDone(time) ||
      (_start != end && (x(time) - end) * (_start - end) <= 0);
}

/// Plays [spring] for [seconds], easing out the residual so it ends at 1.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
    : _simulation = SpringSimulation(spring, 0, 1, 0);

  final double seconds;
  final SpringSimulation _simulation;

  late final double _residual = 1 - _simulation.x(seconds);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}

final dropletSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 165,
  ratio: 0.8,
);

/// Rises to 1 at [peak] and back, as iOS 27's droplets overshoot and swell.
double riseAndFall(double time, double peak, double sharpness) {
  if (time <= 0) {
    return 0;
  }
  final x = time / peak;
  return math.pow(x, sharpness).toDouble() * math.exp(sharpness * (1 - x));
}
