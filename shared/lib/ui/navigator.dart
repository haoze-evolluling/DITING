// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'dart:async';

import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/deferred_push.dart';
import 'package:diting_shared/ui/drag_back.dart';
import 'package:diting_shared/ui/keyboard_inset_hold.dart';
import 'package:diting_shared/ui/page_background.dart';
import 'package:diting_shared/ui/page_transition.dart';
import 'package:diting_shared/ui/sheet_navigator.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

class BaseNavigator {
  static PageRoute<T> _routeOf<T>(BuildContext context, Widget child) {
    final view = KeyboardInsetHold(child: child);
    // FlClash picks the mobile card slide and the desktop fade; the view width,
    // not the host platform, decides, so a narrow desktop window matches too.
    return context.isMobileView
        ? CardPageRoute<T>(builder: (_) => view)
        : FadePageRoute<T>(builder: (_) => view);
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

    final route = FadePageRoute<T>(
      builder: (_) => KeyboardInsetHold(
        child: _DropWatch(onDropped: reopenIfDropped, child: child),
      ),
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

/// A navigator's first page: it never animates itself, and a card route pushed
/// over it drives how it recedes through its delegated transition.
class RootPage<T> extends Page<T> {
  const RootPage({required this.child, super.key, super.name});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _RootPageRoute<T>(page: this);
}

class _RootPageRoute<T> extends PageRoute<T> {
  _RootPageRoute({required RootPage<T> page}) : super(settings: page);

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is CardRouteMixin &&
      (nextRoute is! PageRoute<dynamic> || !nextRoute.fullscreenDialog);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return AnimatedBuilder(
      animation: secondaryAnimation,
      child: child,
      builder: (context, child) {
        final covered = secondaryAnimation.value;
        if (covered == 0) {
          return child!;
        }
        final path = PageBackgroundScope.pathOf(context);
        final content = path == null
            ? child!
            : PageCardSurface(path: path, child: child!);
        final width = MediaQuery.sizeOf(context).width;
        return Transform.translate(
          offset: Offset(-cardCoveredSlide * width * covered, 0),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              ColoredBox(
                color: cardCoveredDim.withValues(
                  alpha: cardCoveredDim.a * covered,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: (settings as RootPage<T>).child,
    );
  }
}

class FadePageRoute<T> extends PageRoute<T>
    with DragBackRouteMixin<T>, DeferredPushRouteMixin<T> {
  FadePageRoute({required this.builder, super.settings});

  final Widget Function(BuildContext context) builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: KeyboardInsetHold(child: builder(context)),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return dragBackDetector(
      isDragBackActive
          ? dragBackSlide(context, animation, child)
          : FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);
}

class CardPageRoute<T> extends PageRoute<T>
    with DragBackRouteMixin<T>, DeferredPushRouteMixin<T>, CardRouteMixin<T> {
  CardPageRoute({required this.builder, super.settings});

  final Widget Function(BuildContext context) builder;

  // HeroController would hold the first frame offstage. Painted at rest off
  // screen instead, the page takes its costly first paint and snapshots there
  // rather than in the first frames it moves in.
  @override
  set offstage(bool value) {}

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: KeyboardInsetHold(child: builder(context)),
    );
  }
}
