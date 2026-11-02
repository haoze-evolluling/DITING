// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';
import 'dart:math' as math;

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/scroll_behavior.dart';
import 'package:diting_shared/ui/shape.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'inherited.dart';
import 'sheet.dart';
import 'sheet_navigator.dart';
part 'snap_sheet_a.dart';
part 'snap_sheet_b.dart';
part 'snap_sheet_c.dart';
part 'snap_sheet_d.dart';

/// Receives the sheet's own scroll controller, or null with no detents to drag between.
typedef SnapSheetBuilder = Widget Function(
  BuildContext context,
  ScrollController? controller,
);

const snapSheetDetents = [9 / 16, 0.9];

/// UIKit's presentation spring, mass 3 and stiffness 1000, critically damped.
const _stiffness = 1000 / 3;

final _omega = math.sqrt(_stiffness);

/// A sheet thrown at its detent overshoots it slightly on iOS.
const _thrownRatio = 0.8;
const _fullThrow = 0.3;
const _hardestThrow = 0.75;

/// UIScrollView.DecelerationRate.fast, which iOS projects a release with.
const _projectionTime = 0.99 / (1 - 0.99) / 1000;

/// UIKit's rubber band past the tallest detent, read from iOS 27.
const _rubberBandExtent = 100.0;
const _rubberBandCoefficient = 0.55;

const _settleTolerance = Tolerance(distance: 0.5, velocity: 10);

const _peakEase = 120.0;

/// [_settleTolerance] for a sheet about 500 pixels tall, in UIKit's 0.5 s.
const _presentationTolerance = Tolerance(distance: 0.001, velocity: 0.02);

/// Wheel events closer than this are one turn, as Chromium latches one wheel sequence.
const _wheelTurnGap = Duration(milliseconds: 500);

class SnapSheetRoute<T> extends PopupRoute<T> with SheetCoverRouteMixin<T> {
  SnapSheetRoute({
    required this.builder,
    required this.sheetBarrierColor,
    required this.barrierLabel,
    this.detents = snapSheetDetents,
    this.fitsContent = false,
    this.initialScrollOffset = 0,
  });

  final SnapSheetBuilder builder;
  final Color sheetBarrierColor;
  final List<double> detents;

  final bool fitsContent;

  final double initialScrollOffset;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => sheetBarrierColor;

  @override
  bool get barrierDismissible => true;

  final _dismissHandler = ValueNotifier<SheetDismissHandler?>(null);

  final _coveringSheet = ValueNotifier<SnapSheetRoute<dynamic>?>(null);

  double _closingVelocity = 0;

  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    super.didChangeNext(nextRoute);
    _coveringSheet.value = nextRoute is SnapSheetRoute ? nextRoute : null;
  }

  Future<void> _dismiss() async {
    final handler = _dismissHandler.value;
    if (handler != null) {
      await handler();
    } else {
      await navigator?.maybePop();
    }
  }

  void _drag(double value) => controller!.value = value;

  void _restore(double velocity) {
    controller!.animateWith(_presentation(1, velocity));
  }

  /// Springs back while a guard decides, then closes with [velocity] as UIKit does.
  void _close(double velocity) {
    _restore(0);
    _closingVelocity = velocity;
    SchedulerBinding.instance.addPostFrameCallback((_) => _closingVelocity = 0);
    unawaited(_dismiss());
  }

  _SheetSpring _presentation(double target, double velocity) {
    final from = controller!.value;
    final launch = _launch(target - from, velocity, overshoots: false);
    return _SheetSpring(
      from: from,
      to: target,
      velocity: launch.velocity,
      ratio: launch.ratio,
      tolerance: _presentationTolerance,
    );
  }

  @override
  Simulation createSimulation({required bool forward}) {
    final velocity = forward ? 0.0 : _closingVelocity;
    _closingVelocity = 0;
    return _presentation(forward ? 1 : 0, velocity);
  }

  @override
  Widget buildModalBarrier() {
    void onDismiss() => unawaited(_dismiss());
    final color = barrierColor;
    if (color == null || color.a == 0 || offstage) {
      return ModalBarrier(
        dismissible: barrierDismissible,
        semanticsLabel: barrierLabel,
        barrierSemanticsDismissible: semanticsDismissible,
        onDismiss: onDismiss,
      );
    }
    return AnimatedModalBarrier(
      color: animation!.drive(
        ColorTween(begin: color.withValues(alpha: 0), end: color),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
      onDismiss: onDismiss,
    );
  }

  @override
  void dispose() {
    _dismissHandler.dispose();
    _coveringSheet.dispose();
    super.dispose();
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 500);

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return ElevatedSurfaceTheme(child: _SnapSheet(route: this));
  }
}

/// A throw away from the target is dropped, as UIKit drops it.
({double velocity, double ratio}) _launch(
  double distance,
  double velocity, {
  required bool overshoots,
}) {
  if (distance == 0 || velocity == 0 || velocity.sign != distance.sign) {
    return (velocity: 0, ratio: 1);
  }
  final reach = _omega * distance.abs();
  final strength = velocity.abs() / reach;
  if (!overshoots) {
    return (velocity: velocity.sign * math.min(strength, 1) * reach, ratio: 1);
  }
  return (
    velocity: velocity.sign * math.min(strength, _hardestThrow) * reach,
    ratio: 1 - (1 - _thrownRatio) * math.min(strength / _fullThrow, 1),
  );
}

double _rounded(double x, double width) {
  if (x >= width) {
    return x;
  }
  if (x <= -width) {
    return 0;
  }
  final reach = x + width;
  return reach * reach / (4 * width);
}

/// How far a drag past the tallest detent shows, easing off as [overshoot] grows.
double _rubberBand(double overshoot, double extent) {
  if (overshoot <= 0 || extent <= 0) {
    return 0;
  }
  return (1 - 1 / (overshoot * _rubberBandCoefficient / extent + 1)) * extent;
}

/// The overshoot that shows [stretch], so a held sheet resumes where it showed.
double _overshootOf(double stretch, double extent) {
  if (stretch <= 0 || extent <= 0) {
    return 0;
  }
  final reach = math.min(stretch, extent * 0.99);
  return extent / _rubberBandCoefficient * reach / (extent - reach);
}
