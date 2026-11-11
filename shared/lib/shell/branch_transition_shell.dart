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

    final content = Opacity(
      opacity: opacity,
      child: Transform.scale(scale: scale, child: widget.children[index]),
    );
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: FractionalTranslation(
          translation: Offset(dx, 0),
          child: content,
        ),
      ),
    );
  }
}
