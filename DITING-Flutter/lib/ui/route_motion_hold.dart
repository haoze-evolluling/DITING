// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';

import 'package:diting/ui/navigator.dart';
import 'package:diting/ui/sheet_navigator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class _RouteMotion {
  _RouteMotion(BuildContext context)
    : _animations = [
        for (final route in routesCarrying(context)) ...[
          ?route.animation,
          ?route.secondaryAnimation,
        ],
        sheetCoverOf(context),
      ],
      _gestures = [
        for (final route in routesCarrying(context))
          ?route.navigator?.userGestureInProgressNotifier,
      ];

  final List<Animation<double>> _animations;
  final List<ValueListenable<bool>> _gestures;

  bool get isMoving =>
      _animations.any((animation) => animation.isAnimating) ||
      _gestures.any((gesture) => gesture.value);

  void addListener(AnimationStatusListener onStatus, VoidCallback onGesture) {
    for (final animation in _animations) {
      animation.addStatusListener(onStatus);
    }
    for (final gesture in _gestures) {
      gesture.addListener(onGesture);
    }
  }

  void removeListener(
    AnimationStatusListener onStatus,
    VoidCallback onGesture,
  ) {
    for (final animation in _animations) {
      animation.removeStatusListener(onStatus);
    }
    for (final gesture in _gestures) {
      gesture.removeListener(onGesture);
    }
  }
}

/// Whether a route transition or a drag moves this page or covers it.
bool isRouteMoving(BuildContext context) => _RouteMotion(context).isMoving;

/// Holds list refreshes while the page's route moves, replaying the latest once it settles.
mixin RouteMotionHoldMixin<T extends StatefulWidget> on State<T> {
  ModalRoute<Object?>? _route;
  _RouteMotion? _motion;
  VoidCallback? _heldUpdate;

  void updateWhenRouteSettled(VoidCallback update) {
    if (_motion?.isMoving ?? false) {
      _heldUpdate = update;
      return;
    }
    _heldUpdate = null;
    update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_motion != null && identical(route, _route)) {
      return;
    }
    _detach();
    _route = route;
    _motion = _RouteMotion(context)..addListener(_handleStatus, _releaseHeld);
  }

  @override
  void dispose() {
    _detach();
    _heldUpdate = null;
    super.dispose();
  }

  void _detach() {
    _motion?.removeListener(_handleStatus, _releaseHeld);
    _motion = null;
  }

  void _handleStatus(AnimationStatus _) => _releaseHeld();

  void _releaseHeld() {
    final update = _heldUpdate;
    if (update == null || !mounted || (_motion?.isMoving ?? false)) {
      return;
    }
    _heldUpdate = null;
    update();
  }
}

/// Calls [didSettleRoute] once the route that brought the page in has settled.
mixin RouteSettledMixin<T extends StatefulWidget> on State<T> {
  var _settleScheduled = false;
  var _routeSettled = false;

  bool get routeSettled => _routeSettled;

  @protected
  void didSettleRoute();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settleScheduled) {
      return;
    }
    _settleScheduled = true;
    unawaited(_settle());
  }

  Future<void> _settle() async {
    await whenRouteSettled(context);
    if (!mounted) {
      return;
    }
    _routeSettled = true;
    didSettleRoute();
  }
}

ScrollCacheExtent? arrivalScrollCacheExtent(bool routeSettled) {
  return routeSettled ? null : const ScrollCacheExtent.pixels(0);
}

/// Builds a scroll body with no cache extent while its route slides in, so the transition's first
/// frame only builds what is on screen; the rows below follow once the route settles. A page that
/// is not arriving (a tab root, a rebuilt page) starts settled and never rebuilds for it.
class RouteArrivalScope extends StatefulWidget {
  const RouteArrivalScope({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollCacheExtent? cacheExtent)
  builder;

  @override
  State<RouteArrivalScope> createState() => _RouteArrivalScopeState();
}

class _RouteArrivalScopeState extends State<RouteArrivalScope> {
  bool? _settled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled != null) {
      return;
    }
    _settled = !isRouteArriving(context);
    if (!_settled!) {
      unawaited(_settle());
    }
  }

  Future<void> _settle() async {
    await whenRouteSettled(context);
    if (mounted) {
      setState(() => _settled = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, arrivalScrollCacheExtent(_settled ?? true));
}
