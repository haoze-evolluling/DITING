// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'dart:async';

import 'package:animations/animations.dart';
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/keyboard_inset_hold.dart';
import 'package:diting_shared/ui/sheet_navigator.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class BaseNavigator {
  static PageRoute<T> _routeOf<T>(BuildContext context, Widget child) {
    return CommonRoute(builder: (context) => child);
  }

  /// The mobile layout drops a home page's navigator, so a desktop page left open reopens.
  static Future<T?> push<T>(BuildContext context, Widget child) {
    final navigator = Navigator.of(context);
    if (context.isMobileView) {
      return navigator.push<T>(_routeOf(context, child));
    }
    final completer = Completer<T?>();
    var popped = false;
    void reopenIfDropped() {
      if (popped) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        completer.complete(context.mounted ? push<T>(context, child) : null);
      });
    }

    final route = CommonRoute<T>(
      builder: (_) => _DropWatch(onDropped: reopenIfDropped, child: child),
    );
    unawaited(
      navigator.push<T>(route).then((value) {
        popped = true;
        completer.complete(value);
      }),
    );
    return completer.future;
  }

  static Future<T?> pushReplacement<T>(BuildContext context, Widget child) {
    return Navigator.of(context)
        .pushReplacement<T, void>(_routeOf(context, child));
  }
}

class _DropWatch extends StatefulWidget {
  const _DropWatch({required this.onDropped, required this.child});

  final VoidCallback onDropped;
  final Widget child;

  @override
  State<_DropWatch> createState() => _DropWatchState();
}

class _DropWatchState extends State<_DropWatch> {
  @override
  void dispose() {
    widget.onDropped();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The route of [context]'s page plus, for a page in a sheet, the sheets'.
Iterable<ModalRoute<Object?>> routesCarrying(BuildContext context) sync* {
  var route = ModalRoute.of(context);
  while (route != null) {
    yield route;
    final navigator = route.navigator;
    if (navigator == null ||
        !navigator.mounted ||
        navigator.widget is! SheetPagesNavigator) {
      return;
    }
    route = ModalRoute.of(navigator.context);
  }
}

Future<void> whenRouteSettled(BuildContext context) async {
  final routes = routesCarrying(context).toList();
  for (final route in routes) {
    await _whenSettled(route);
  }
}

bool isRouteArriving(BuildContext context) => routesCarrying(context)
    .any((route) => route.offstage || (route.animation?.isAnimating ?? false));

/// Completes once the route [context] is on stops moving under the route
/// above it, as while that route still leaves after its pop.
Future<void> whenRouteUncovered(BuildContext context) async {
  final animation = ModalRoute.of(context)?.secondaryAnimation;
  if (animation != null) {
    await _whenStill(animation);
  }
}

Future<void> _whenSettled(ModalRoute<Object?> route) async {
  // HeroController builds a pushed route offstage first, so it tells the truth only after.
  while (route.offstage && route.isActive) {
    await SchedulerBinding.instance.endOfFrame;
  }
  final animation = route.animation;
  if (animation != null) {
    await _whenStill(animation);
  }
}

Future<void> _whenStill(Animation<double> animation) {
  if (!animation.isAnimating) {
    return Future.value();
  }
  final completer = Completer<void>();
  void handleStatus(AnimationStatus status) {
    if (status.isAnimating) {
      return;
    }
    animation.removeStatusListener(handleStatus);
    completer.complete();
  }

  animation.addStatusListener(handleStatus);
  return completer.future;
}

const commonSharedXPageTransitions = SharedAxisPageTransitionsBuilder(
  transitionType: SharedAxisTransitionType.horizontal,
  fillColor: Colors.transparent,
);

/// A pushed page; the theme's [PageTransitionsTheme] supplies the transition.
class CommonRoute<T> extends MaterialPageRoute<T> {
  CommonRoute({required Widget Function(BuildContext context) builder})
    : super(builder: (context) => KeyboardInsetHold(child: builder(context)));
}
