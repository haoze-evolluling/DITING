// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:diting_shared/ui/motion.dart';

part 'drag_back_detector.dart';

/// iOS 27's interactive pop, as measured on the simulator: the page trails
/// the finger on a stiff spring, pops when the distance dragged plus the
/// velocity over the 0.35 s left of the transition reaches 0.4665 of the
/// width, and lets go on a spring a flick past 1.5 widths a second speeds
/// up 4.25 times, ramping in from one.
final _followSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 80),
  bounce: 0.15,
);
final _releaseSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
  bounce: 0.15,
);
const double _popReach = 0.4665;
const double _popLead = 0.35;
const double _flickSpeed = 1.5;
const double _flickRampStart = 1;
const double _flickBoost = 4.25;
const double _touchSlop = 30;
const double _rubberStiffness = 0.55;
const double _rubberReach = 0.5;
const double _dragEdge = 1e-6;

final Animatable<Offset> _slideTween = Tween<Offset>(
  begin: const Offset(1.0, 0.0),
  end: Offset.zero,
);
const Animation<Offset> _noSlide = AlwaysStoppedAnimation(Offset.zero);

/// Lets a press anywhere on the route drag it toward the reading end to pop.
/// A horizontal scrollable, slider or text field under the pointer is deeper
/// in the hit test, so it wins the arena and keeps the drag.
mixin DragBackRouteMixin<T> on ModalRoute<T> {
  bool _dragBackActive = false;
  bool _dragBackHeld = false;
  Offset _dragBackOrigin = Offset.zero;
  Size _dragBackExtent = Size.zero;
  Axis _dragBackAxis = Axis.horizontal;
  Offset _dragBackTranslation = Offset.zero;
  _DragFollower? _follower;
  FocusNode? _focusBeforeDragBack;

  /// While true the route's own transition should follow the finger, through
  /// the release until the route settles.
  bool get isDragBackActive => _dragBackActive;

  @protected
  bool get isDragBackHeld => _dragBackHeld;

  @protected
  Offset get dragBackOrigin => _dragBackOrigin;

  @protected
  Size get dragBackExtent => _dragBackExtent;

  @protected
  Axis get dragBackAxis => _dragBackAxis;

  @protected
  Offset get dragBackFollowVelocity => _follower?.velocity ?? Offset.zero;

  @protected
  AnimationController get dragBackController => controller!;

  /// Whether a drag down dismisses too, locking to the axis it sets off on.
  @protected
  bool get dragBackDownward => false;

  @protected
  double dragBackSlopOf(
    PointerDeviceKind kind,
    DeviceGestureSettings? settings,
  ) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => computePanSlop(kind, settings),
      _ when kind == PointerDeviceKind.touch => _touchSlop,
      _ => computeHitSlop(kind, settings),
    };
  }

  /// How far the page has been pulled past where it rests, as a share of the
  /// width; iOS lets a drag toward the leading end stretch it there.
  ValueListenable<double> get dragBackOverdrag => _dragBackOverdrag;
  final _dragBackOverdrag = ValueNotifier(0.0);

  @protected
  Offset dragBackTargetOf(Offset translation) {
    final width = _dragBackExtent.width;
    final reach = _rubberReach * width;
    final dx = translation.dx;
    return Offset(
      dx >= 0
          ? math.min(dx, width)
          : -(1 - 1 / (_rubberStiffness * -dx / reach + 1)) * reach,
      0,
    );
  }

  @protected
  SpringDescription dragBackFollowSpring({required bool first}) =>
      _followSpring;

  @protected
  void didFollowDragBack(Offset followed) {
    if (_dragBackExtent.width == 0) {
      return;
    }
    final value = 1 - followed.dx / _dragBackExtent.width;
    final held = clampDouble(value, _dragEdge, 1 - _dragEdge);
    dragBackController.value = held;
    _dragBackOverdrag.value = math.max(0, value - held);
  }

  @protected
  bool dragBackPops(Offset translation, Offset velocity) {
    return translation.dx + _popLead * velocity.dx >=
        _popReach * _dragBackExtent.width;
  }

  /// Completes once the route rests after the release, or is null if it does.
  @protected
  Future<void>? settleDragBack({required bool pops, required Offset velocity}) {
    final controller = dragBackController;
    final width = _dragBackExtent.width;
    final speed = _releaseSpeedOf(width == 0 ? 0.0 : velocity.dx / width);
    final target = pops ? 0.0 : 1.0;
    if (pops && isCurrent) {
      navigator!.pop();
    }
    final goesPastRest = !pops || _dragBackOverdrag.value > 0;
    if (goesPastRest) {
      controller.stop();
      return _follower!
          .moveTo(
            Offset((1 - target) * width, 0),
            _releaseSpring,
            velocity: Offset(speed * width, 0),
            endsOnArrival: pops,
          )
          .then((_) {
            if (_follower != null) {
              controller.value = target;
            }
          });
    }
    if (!controller.isAnimating) {
      return null;
    }
    controller.animateBackWith(
      ArrivingSimulation(
        SpringSimulation(_releaseSpring, controller.value, target, -speed),
        end: target,
      ),
    );
    return whenStopped(controller);
  }

  double _releaseSpeedOf(double speed) {
    final boost = clampDouble(
      (speed - _flickRampStart) / (_flickSpeed - _flickRampStart),
      0,
      1,
    );
    return speed * (1 + (_flickBoost - 1) * boost);
  }

  @protected
  Future<void>? followDragBackTo(Offset target, SpringDescription spring) {
    return _follower?.moveTo(target, spring);
  }

  /// Completes in the frame [controller] stops in, or is null if it has.
  @protected
  Future<void>? whenStopped(AnimationController controller) {
    if (!controller.isAnimating) {
      return null;
    }
    final stopped = Completer<void>.sync();
    void handleStatus(AnimationStatus status) {
      if (status.isAnimating) {
        return;
      }
      controller.removeStatusListener(handleStatus);
      stopped.complete();
    }

    controller.addStatusListener(handleStatus);
    return stopped.future;
  }

  FocusScopeNode? get _focusScope {
    final context = subtreeContext;
    return context == null
        ? null
        : FocusScope.of(context, createDependency: false);
  }

  @protected
  void didStartDragBack() {}

  /// Called once the route has settled after a drag back, popped or not.
  @protected
  void didEndDragBack() {}

  Widget dragBackDetector(Widget child) {
    return _DragBackDetector(route: this, child: child);
  }

  /// Follows the finger while a drag back is active and stays still
  /// otherwise. A route keeps it in its tree either way: wrapping the page
  /// only once the drag starts would move the page to a new parent, which
  /// rebuilds all of it.
  Widget dragBackSlide(
    BuildContext context,
    Animation<double> animation,
    Widget child,
  ) {
    return SlideTransition(
      position: _dragBackActive ? animation.drive(_slideTween) : _noSlide,
      textDirection: Directionality.of(context),
      child: child,
    );
  }

  @override
  void dispose() {
    final follower = _follower;
    _follower = null;
    follower?.dispose();
    _dragBackOverdrag.dispose();
    super.dispose();
  }

  // popGestureEnabled no longer waits for the route to be fully uncovered or
  // for another drag back to settle, and NavigatorResizable would settle on
  // a pop still running under the drag.
  bool get _canDragBack =>
      isCurrent &&
      popGestureEnabled &&
      secondaryAnimation!.isDismissed &&
      !popGestureInProgress;

  void _startDragBack(Offset origin, Size extent, Axis axis) {
    _dragBackActive = true;
    _dragBackHeld = true;
    _dragBackOrigin = origin;
    _dragBackExtent = extent;
    _dragBackAxis = axis;
    _dragBackTranslation = Offset.zero;
    (_follower ??= _DragFollower(navigator!, _handleFollow)).reset();
    _focusBeforeDragBack = (_focusScope?.hasFocus ?? false)
        ? FocusManager.instance.primaryFocus
        : null;
    didStartDragBack();
    navigator!.didStartUserGesture();
  }

  void _handleFollow() => didFollowDragBack(_follower!.value);

  void _updateDragBack(Offset delta) {
    final follower = _follower!;
    final first = _dragBackTranslation == Offset.zero && !follower.isMoving;
    _dragBackTranslation += delta;
    follower.moveTo(
      dragBackTargetOf(_dragBackTranslation),
      dragBackFollowSpring(first: first),
    );
  }

  void _endDragBack(Offset velocity) {
    final navigator = this.navigator!;
    _dragBackHeld = false;
    _follower!.stop();
    final pops = isCurrent
        ? dragBackPops(_dragBackTranslation, velocity)
        : !isActive;
    final settled = settleDragBack(pops: pops, velocity: velocity);
    if (settled == null) {
      _finishDragBack(navigator);
    } else {
      settled.whenComplete(() => _finishDragBack(navigator));
    }
  }

  void _finishDragBack(NavigatorState navigator) {
    if (!_dragBackActive) {
      return;
    }
    _dragBackActive = false;
    _dragBackOverdrag.value = 0;
    didEndDragBack();
    navigator.didStopUserGesture();
    _refocusAfterDragBack();
  }

  // ModalRoute unfocuses a route under a user gesture and refocuses nothing.
  void _refocusAfterDragBack() {
    final focus = _focusBeforeDragBack;
    _focusBeforeDragBack = null;
    if (focus == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isCurrent &&
          !(_focusScope?.hasFocus ?? false) &&
          (focus.context?.mounted ?? false)) {
        focus.requestFocus();
      }
    });
  }

  void _abortDragBack() {
    final navigator = this.navigator;
    if (!_dragBackActive || navigator == null) {
      return;
    }
    _follower?.stop();
    _dragBackActive = false;
    _dragBackHeld = false;
    _dragBackOverdrag.value = 0;
    _focusBeforeDragBack = null;
    didEndDragBack();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted) {
        navigator.didStopUserGesture();
      }
    });
  }
}
