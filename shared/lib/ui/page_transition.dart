// Portions derived from FlClash (https://github.com/chen08209/FlClash), Copyright (c) the FlClash authors, GPL-3.0-or-later.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:diting_shared/ui/drag_back.dart';
import 'package:diting_shared/ui/liquid_glass.dart';
import 'package:diting_shared/ui/motion.dart';
import 'package:diting_shared/ui/page_background.dart';
import 'package:diting_shared/ui/surface.dart';
import 'package:material_ui/material_ui.dart';

part 'page_transition_card.dart';

/// iOS 27 pushes and pops a page on a critically damped spring of 0.3 s that
/// sets off at nine times its distance a second, as measured on the simulator.
final _pushSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
);
const _pushSpeed = 9.0;
const _settleTolerance = Tolerance(distance: 1e-3, velocity: 1e-2);

/// For what reads a route's duration rather than following its animation.
Duration _settlingTimeOf(SpringDescription spring, double launchSpeed) {
  final simulation = SpringSimulation(
    spring,
    0,
    1,
    launchSpeed,
    tolerance: _settleTolerance,
  );
  var milliseconds = 0;
  while (!simulation.isDone(milliseconds / 1000)) {
    milliseconds++;
  }
  return Duration(milliseconds: milliseconds);
}

const cardCoveredSlide = 0.3;
const cardCoveredDim = Color.from(alpha: 0.1, red: 0, green: 0, blue: 0);

/// UIKit's zoom shrinks the page it covers toward its center by 34.667 dp of
/// width, to no less than 80%, and dims it.
const _recededShrinkWidth = 34.667;
const _recededMinScale = 0.8;
const _recededDim = Color.from(alpha: 0.15, red: 0, green: 0, blue: 0);

double _recededShrinkOf(Size size) =>
    math.min(1 - _recededMinScale, _recededShrinkWidth / size.width);

/// What a 4% black Gaussian of sigma 12 casts past the card's leading edge.
const _cardShadowSigma = 12.0;
const _cardShadowStops = [0.0, 1 / 6, 1 / 3, 1 / 2, 2 / 3, 1.0];
final _cardShadowColors = [
  for (final share in const [0.5, 0.3085, 0.1587, 0.0668, 0.0228, 0.0])
    Color.from(alpha: 0.04 * share, red: 0, green: 0, blue: 0),
];

Rect _scaleTowardCenter(Rect rect, Size size, double scale) {
  final center = size.center(Offset.zero);
  return Rect.fromLTRB(
    center.dx + (rect.left - center.dx) * scale,
    center.dy + (rect.top - center.dy) * scale,
    center.dx + (rect.right - center.dx) * scale,
    center.dy + (rect.bottom - center.dy) * scale,
  );
}

Rect recededRect(Rect rect, Size size, double covered) =>
    _scaleTowardCenter(rect, size, 1 - _recededShrinkOf(size) * covered);

Rect unrecededRect(Rect rect, Size size, double covered) =>
    _scaleTowardCenter(rect, size, 1 / (1 - _recededShrinkOf(size) * covered));

var _measuringAtRest = false;

T measureAtRest<T>(T Function() measure) {
  final measuring = _measuringAtRest;
  _measuringAtRest = true;
  try {
    return measure();
  } finally {
    _measuringAtRest = measuring;
  }
}

bool get isMeasuringAtRest => _measuringAtRest;

/// How a route moves its page's bar items: [lifted] out of a snapshot of the
/// page, [moving] while the page moves under a bar that holds still.
typedef BarItemsMotion = ({
  bool lifted,
  bool moving,
  bool shown,
  double? tracking,
});

/// The display's corners where the platform reports them, which Android does
/// from API 31; elsewhere a moving page stays square.
BorderRadius displayRadiusOf(BuildContext context) =>
    MediaQuery.displayCornerRadiiOf(context) ?? BorderRadius.zero;

/// The [ModalRoute.delegatedTransition] of every card route. Sharing it keeps
/// Flutter from wrapping one's page in another's transition, which would move
/// the page to a new parent and rebuild all of it; any other route under a
/// card route stays still.
Widget? _cardRouteMotion(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) => null;

/// iOS 27's navigation push.
mixin CardRouteMixin<T> on ModalRoute<T> {
  BorderRadius cardRadiusOf(BuildContext context) => displayRadiusOf(context);

  Color settledFillOf(Color surface) => surface;

  /// A root page hosts a nested navigator whose own branch animations build
  /// every frame; snapshotting it would freeze those animations.
  @protected
  bool get snapshotWhileMoving => true;

  @protected
  SpringDescription get openSpring => _pushSpring;

  @protected
  SpringDescription get closeSpring => _pushSpring;

  /// The speed a spring from rest sets off at, as a multiple of its distance
  /// a second.
  @protected
  double get openLaunchSpeed => _pushSpeed;

  @protected
  double get closeLaunchSpeed => _pushSpeed;

  /// Whether this route shrinks the page it covers, as iOS's zoom does,
  /// rather than sliding it back.
  @protected
  bool get recedesCovered => false;

  final _coveredByZoom = ValueNotifier(false);

  final _barItems = ValueNotifier<BarItemsMotion>((
    lifted: false,
    moving: false,
    shown: true,
    tracking: null,
  ));

  ValueListenable<BarItemsMotion> get barItems => _barItems;

  CardRouteMixin<dynamic>? _next;

  final _coveringOverdrag = ValueNotifier(0.0);
  ValueListenable<double>? _nextOverdrag;

  void _copyOverdrag() => _coveringOverdrag.value = _nextOverdrag?.value ?? 0;

  ValueListenable<double> get _overdrag => switch (this) {
    final DragBackRouteMixin<T> route => route.dragBackOverdrag,
    _ => const AlwaysStoppedAnimation(0.0),
  };

  /// How far a drag back of this route shows the bar items under it.
  @protected
  double? get barItemsUncovering => null;

  /// Whether [animation]'s card has moved in and not yet moved back out.
  @protected
  bool hasCome(Animation<double> animation) => switch (animation.status) {
    AnimationStatus.forward => animation.value > 0,
    AnimationStatus.reverse => animation.value == 1,
    AnimationStatus.completed => true,
    AnimationStatus.dismissed => false,
  };

  /// iOS's bar items hold still while a push moves the pages under them.
  @protected
  BarItemsMotion computeBarItems() {
    final secondary = secondaryAnimation!;
    if (_coveredByZoom.value && !secondary.isDismissed) {
      return (
        lifted: true,
        moving: true,
        shown: !hasCome(secondary),
        tracking: _next?.barItemsUncovering,
      );
    }
    final animation = this.animation!;
    return (
      lifted: false,
      moving: animation.isAnimating || secondary.isAnimating,
      shown: hasCome(animation) && !hasCome(secondary),
      tracking: null,
    );
  }

  @protected
  void updateBarItems() => _barItems.value = computeBarItems();

  // Impeller redraws a moving page in full each frame.
  final _motionSnapshot = SnapshotController();

  // Only a page going out of view is drawn from its snapshot. One coming into
  // view stays live, as a frozen picture of it would show what it held when
  // last covered, such as a press still fading out, until it settles.
  void _updateMotionSnapshot() {
    final animation = this.animation!;
    final secondary = secondaryAnimation!;
    final dragged = navigator?.userGestureInProgress ?? false;
    _motionSnapshot.allowSnapshotting = _coveredByZoom.value
        ? animation.isCompleted && secondary.isAnimating
        : (secondary.status == AnimationStatus.forward && !dragged) ||
              (!recedesCovered &&
                  animation.status.isAnimating &&
                  (animation.status == AnimationStatus.reverse || dragged));
  }

  void retakeSnapshot() {
    if (!_motionSnapshot.allowSnapshotting) {
      return;
    }
    _motionSnapshot.allowSnapshotting = false;
    _updateMotionSnapshot();
  }

  void _handleStatus(AnimationStatus _) {
    _updateMotionSnapshot();
    updateBarItems();
  }

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      _settlingTimeOf(openSpring, openLaunchSpeed);

  @override
  Duration get reverseTransitionDuration =>
      _settlingTimeOf(closeSpring, closeLaunchSpeed);

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _cardRouteMotion;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) =>
      nextRoute is CardRouteMixin;

  // The navigator announces a route pushed over this one while it pops.
  @override
  void didChangeNext(Route<dynamic>? nextRoute) {
    final next = isActive ? nextRoute : null;
    _next = next is CardRouteMixin ? next : null;
    _nextOverdrag?.removeListener(_copyOverdrag);
    _nextOverdrag = switch (next) {
      final DragBackRouteMixin<dynamic> route => route.dragBackOverdrag,
      _ => null,
    };
    _nextOverdrag?.addListener(_copyOverdrag);
    _copyOverdrag();
    if (next is CardRouteMixin) {
      _coveredByZoom.value = next.recedesCovered;
    }
    super.didChangeNext(next);
    retakeSnapshot();
  }

  @override
  void didPopNext(Route<dynamic> nextRoute) {
    super.didPopNext(nextRoute);
    retakeSnapshot();
  }

  @override
  void install() {
    super.install();
    animation!
      ..addListener(updateBarItems)
      ..addStatusListener(_handleStatus);
    secondaryAnimation!
      ..addListener(updateBarItems)
      ..addStatusListener(_handleStatus);
    _coveredByZoom
      ..addListener(_updateMotionSnapshot)
      ..addListener(updateBarItems);
  }

  @override
  void dispose() {
    animation!
      ..removeListener(updateBarItems)
      ..removeStatusListener(_handleStatus);
    secondaryAnimation!
      ..removeListener(updateBarItems)
      ..removeStatusListener(_handleStatus);
    _nextOverdrag?.removeListener(_copyOverdrag);
    _coveringOverdrag.dispose();
    _coveredByZoom.dispose();
    _barItems.dispose();
    _motionSnapshot.dispose();
    super.dispose();
  }

  Widget _snapshotWhileMoving(BuildContext context, Widget child) {
    _updateMotionSnapshot();
    if (!snapshotWhileMoving) {
      return child;
    }
    // The snapshot has no host over it, so one within takes the page's panes
    // for it, and they come out as glass rather than a flat tint.
    final path = PageBackgroundScope.pathOf(context);
    final content = path == null
        ? child
        : PageCardSurface(path: path, child: child);
    return SnapshotWidget(
      controller: _motionSnapshot,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: LiquidGlassHost(
        enabled: LiquidGlassScope.of(context),
        child: content,
      ),
    );
  }

  @protected
  TickerFuture settleTo(double target, {double? velocity}) {
    final controller = this.controller!;
    final from = controller.value;
    final opens = target == 1;
    final simulation = SpringSimulation(
      opens ? openSpring : closeSpring,
      from,
      target,
      velocity ??
          (target - from) * (opens ? openLaunchSpeed : closeLaunchSpeed),
      tolerance: _settleTolerance,
      snapToEnd: true,
    );
    final settle = ArrivingSimulation(simulation, end: target);
    return opens
        ? controller.animateWith(settle)
        : controller.animateBackWith(settle);
  }

  @override
  TickerFuture didPush() {
    super.didPush();
    return settleTo(1);
  }

  @override
  bool didPop(T? result) {
    final controller = this.controller!;
    final velocity = controller.isAnimating ? controller.velocity : null;
    final popped = super.didPop(result);
    // A pop that only drops a local history entry, such as a search layer,
    // leaves the route in place.
    if (!popped) {
      return false;
    }
    // A drag back lets go with its own spring.
    if (this case DragBackRouteMixin<T>(isDragBackActive: true)) {
      return popped;
    }
    if (!controller.isDismissed) {
      settleTo(0, velocity: velocity);
    }
    return popped;
  }

  @protected
  Widget coveredTransition(
    BuildContext context,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _CardTransition(
      animation: kAlwaysCompleteAnimation,
      secondaryAnimation: secondaryAnimation,
      overdrag: const AlwaysStoppedAnimation(0.0),
      coveringOverdrag: _coveringOverdrag,
      radius: cardRadiusOf(context),
      settledFill: Colors.transparent,
      receding: _coveredByZoom,
      child: _snapshotWhileMoving(context, child),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final surface = SurfaceLevel.page.colorOf(ColorScheme.of(context));
    final wallpaper = PageBackgroundScope.maybeOf(context)?.isActive ?? false;
    final transition = _CardTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      overdrag: _overdrag,
      coveringOverdrag: _coveringOverdrag,
      radius: cardRadiusOf(context),
      settledFill: wallpaper ? Colors.transparent : settledFillOf(surface),
      receding: _coveredByZoom,
      child: _snapshotWhileMoving(context, child),
    );
    return switch (this) {
      final DragBackRouteMixin<T> route => route.dragBackDetector(transition),
      _ => transition,
    };
  }
}

class HomeRoute<T> extends PageRoute<T> with CardRouteMixin<T> {
  HomeRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color settledFillOf(Color surface) => Colors.transparent;

  @override
  bool get snapshotWhileMoving => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: builder(context),
    );
  }
}

/// Moves the page by painting alone, so it is neither rebuilt nor laid out
/// again while it moves.
