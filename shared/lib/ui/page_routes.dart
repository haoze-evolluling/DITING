// Ported from FlClash's prism_ui `FadePageRoute` / `CardPageRoute` transitions.
//
// FlClash picks a plain fade on desktop and a horizontal "card" slide on mobile
// (see its `BaseNavigator.push`): both keep their state and expose no barrier.
// Only the visual transition is borrowed here; the drag-back gesture stays with
// the sheets, where the vendored `DragBackRouteMixin` already drives it.
//
// The performance half is FlClash's too: a page that only slides or fades is
// drawn from a `SnapshotWidget` while it moves, so Impeller does not rasterize
// the whole page (text, card shadows, superellipse edges) again every frame.
// The page coming into view stays live, as a frozen picture of it would show
// whatever it held when it was last covered — a spinner, a fading press — until
// the transition settles.
import 'package:material_ui/material_ui.dart';

const _fadeDuration = Duration(milliseconds: 200);
const _cardDuration = Duration(milliseconds: 300);
const _cardCurve = Curves.fastEaseInToSlowEaseOut;
const _cardExitOffset = Offset(-0.28, 0.0);

/// Freezes [child] into a texture while its route is covered or leaving, and
/// leaves it live while it comes in. Wrapping it in a [RepaintBoundary] keeps
/// even the live path a composited layer, so the slide translates a cached
/// raster instead of repainting the page.
class _RouteSnapshot extends StatefulWidget {
  const _RouteSnapshot({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_RouteSnapshot> createState() => _RouteSnapshotState();
}

class _RouteSnapshotState extends State<_RouteSnapshot> {
  final SnapshotController _snapshot = SnapshotController();

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _snapshot.allowSnapshotting =
        widget.secondaryAnimation.value > 0 ||
        widget.animation.status == AnimationStatus.reverse;
    return SnapshotWidget(
      controller: _snapshot,
      mode: SnapshotMode.permissive,
      autoresize: true,
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// A full-screen page that cross-fades under the theme's own background.
class FadePageRoute<T> extends PageRoute<T> {
  FadePageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => _fadeDuration;

  @override
  Duration get reverseTransitionDuration => _fadeDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  /// Non-opaque so the page it covers stays painted through the fade; a fade
  /// route's whole point is to show the outgoing page underneath.
  @override
  bool get opaque => false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: curved,
      child: _RouteSnapshot(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    );
  }
}

/// A mobile page that slides in from the reading end and eases the page it
/// covers a little to the other side (FlClash's `CardPageRoute`).
class CardPageRoute<T> extends PageRoute<T> {
  CardPageRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => _cardDuration;

  @override
  Duration get reverseTransitionDuration => _cardDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: _cardCurve,
      reverseCurve: _cardCurve,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOut,
    );
    return SlideTransition(
      position: exit.drive(Tween(begin: Offset.zero, end: _cardExitOffset)),
      child: SlideTransition(
        position: enter.drive(
          Tween(begin: const Offset(1, 0), end: Offset.zero),
        ),
        child: FadeTransition(
          opacity: enter,
          child: _RouteSnapshot(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            child: child,
          ),
        ),
      ),
    );
  }
}
