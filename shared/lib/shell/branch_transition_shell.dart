// Animates a `StatefulShellRoute` branch switch the way FlClash's `_HomePageView`
// does: the outgoing page and the incoming page move together (slide) or cross
// fade in place (fade), instead of the incoming page merely fading in alone.
//
// This is the container go_router asks for via `navigatorContainerBuilder`
// (route.dart's `ShellNavigationContainerBuilder`). It mirrors the default
// index-stack container's `Offstage` + `TickerMode` wrapper so every branch
// Navigator keeps its state and an off-screen page stops ticking, but adds the
// per-page transform the default cannot express.
import 'package:diting_shared/state/appearance_extra_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class BranchTransitionShell extends ConsumerStatefulWidget {
  const BranchTransitionShell({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  ConsumerState<BranchTransitionShell> createState() =>
      _BranchTransitionShellState();
}

class _BranchTransitionShellState extends ConsumerState<BranchTransitionShell>
    with SingleTickerProviderStateMixin {
  static const _slideDuration = Duration(milliseconds: 300);
  static const _fadeDuration = Duration(milliseconds: 200);
  static const _scaleDuration = Duration(milliseconds: 260);

  late int _current = widget.navigationShell.currentIndex;
  late int _previous = _current;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _slideDuration,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant BranchTransitionShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.navigationShell.currentIndex;
    if (next == _current) {
      return;
    }
    final transition = ref.read(tabTransitionProvider);
    _previous = _current;
    _current = next;
    if (transition == TabTransition.none) {
      _controller.value = 1;
      return;
    }
    _controller
      ..duration = switch (transition) {
        TabTransition.fade => _fadeDuration,
        TabTransition.scale => _scaleDuration,
        _ => _slideDuration,
      }
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _eased(TabTransition transition, double value) => switch (transition) {
    TabTransition.fade => Curves.easeInOutCubic.transform(value),
    _ => Curves.easeOutCubic.transform(value),
  };

  @override
  Widget build(BuildContext context) {
    final transition = ref.watch(tabTransitionProvider);
    if (transition == TabTransition.none) {
      return _stack(transition, 1);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _stack(transition, _controller.value),
    );
  }

  Widget _stack(TabTransition transition, double raw) {
    final t = _eased(transition, raw);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var index = 0; index < widget.children.length; index++)
          _slot(index, transition, t),
      ],
    );
  }

  /// Every branch is wrapped in the same `Offstage > TickerMode > transform`
  /// chain every frame; only the property values change, so a switch never
  /// reparents a Navigator and its state survives. Intermediate branches of a
  /// long jump are simply offstage, so nothing between gets built or painted.
  Widget _slot(int index, TabTransition transition, double t) {
    final isCurrent = index == _current;
    final isPrevious = index == _previous && index != _current && t < 1;
    final visible = isCurrent || isPrevious;

    double dx = 0;
    var opacity = 1.0;
    var scale = 1.0;
    if (isCurrent) {
      if (transition == TabTransition.slide) {
        dx = (_current > _previous ? 1.0 : -1.0) * (1 - t);
      } else if (transition == TabTransition.fade) {
        opacity = t;
      } else if (transition == TabTransition.scale) {
        opacity = t;
        scale = 0.88 + 0.12 * t;
      }
    } else if (isPrevious) {
      if (transition == TabTransition.slide) {
        dx = -(_current > _previous ? 1.0 : -1.0) * t;
      } else if (transition == TabTransition.fade) {
        opacity = 1 - t;
      } else if (transition == TabTransition.scale) {
        opacity = 1 - t;
        scale = 1 - 0.12 * t;
      }
    } else {
      opacity = 0;
    }

    // Moving a whole page means transforming whatever it paints. Drawing it
    // from a snapshot while it moves keeps Impeller from re-rasterizing every
    // glyph and shadow on each step, as FlClash's `_FadeTabPage` does.
    return _BranchPage(
      key: ValueKey<int>(index),
      visible: visible,
      dx: dx,
      opacity: opacity,
      scale: scale,
      snapshotting: visible && t > 0 && t < 1,
      child: widget.children[index],
    );
  }
}

class _BranchPage extends StatefulWidget {
  const _BranchPage({
    super.key,
    required this.child,
    required this.visible,
    required this.dx,
    required this.opacity,
    required this.scale,
    required this.snapshotting,
  });

  final Widget child;
  final bool visible;
  final double dx;
  final double opacity;
  final double scale;
  final bool snapshotting;

  @override
  State<_BranchPage> createState() => _BranchPageState();
}

class _BranchPageState extends State<_BranchPage> {
  final SnapshotController _snapshot = SnapshotController();

  @override
  void dispose() {
    _snapshot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _snapshot.allowSnapshotting = widget.snapshotting;
    return Offstage(
      offstage: !widget.visible,
      child: TickerMode(
        enabled: widget.visible,
        child: FractionalTranslation(
          translation: Offset(widget.dx, 0),
          child: Opacity(
            opacity: widget.opacity,
            child: Transform.scale(
              scale: widget.scale,
              child: SnapshotWidget(
                controller: _snapshot,
                mode: SnapshotMode.permissive,
                autoresize: true,
                child: RepaintBoundary(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
