// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
import 'package:diting_shared/ui/context.dart';
import 'package:diting_shared/ui/metrics.dart';
import 'package:material_ui/material_ui.dart';


class FadeScaleEnterBox extends StatefulWidget {
  final Widget child;

  const FadeScaleEnterBox({super.key, required this.child});

  @override
  State<FadeScaleEnterBox> createState() => _FadeScaleEnterBoxState();
}

class _FadeScaleEnterBoxState extends State<FadeScaleEnterBox>
    with SingleTickerProviderStateMixin, _EnterAnimation {
  @override
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: commonDuration);
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _animation = Tween<double>(begin: 0, end: 1).animate(_curve);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.disableAnimations) {
      return widget.child;
    }
    return FadeScaleEnterTransition(animation: _animation, child: widget.child);
  }
}

mixin _EnterAnimation<T extends StatefulWidget> on State<T> {
  AnimationController get _controller;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entered) {
      return;
    }
    _entered = true;
    if (context.disableAnimations) {
      _controller.value = _controller.upperBound;
    } else {
      _controller.forward();
    }
  }
}

const _defaultSlideDistance = 24.0;

class FadeSlideEnterTransition extends StatelessWidget {
  const FadeSlideEnterTransition({
    super.key,
    required this.animation,
    this.distance = _defaultSlideDistance,
    this.axis = Axis.horizontal,
    this.child,
  });

  final Animation<double> animation;
  final double distance;
  final Axis axis;
  final Widget? child;

  static final Animatable<double> _fadeInTransition = CurveTween(
    curve: const Interval(0.0, 0.25),
  );
  static final Animatable<double> _slideInCurve = CurveTween(
    curve: Easing.emphasizedDecelerate,
  );

  @override
  Widget build(BuildContext context) {
    final begin = axis == Axis.horizontal
        ? Offset(-distance, 0)
        : Offset(0, distance);
    final slide = Tween<Offset>(
      begin: begin,
      end: Offset.zero,
    ).chain(_slideInCurve).animate(animation);
    return FadeTransition(
      opacity: _fadeInTransition.animate(animation),
      child: AnimatedBuilder(
        animation: slide,
        builder: (_, child) =>
            Transform.translate(offset: slide.value, child: child),
        child: child,
      ),
    );
  }
}

class FadeScaleEnterTransition extends StatelessWidget {
  const FadeScaleEnterTransition({
    super.key,
    required this.animation,
    this.child,
  });

  final Animation<double> animation;
  final Widget? child;

  static final Animatable<double> _fadeInTransition = CurveTween(
    curve: const Interval(0.0, 0.3),
  );
  static final Animatable<double> _scaleInTransition = Tween<double>(
    begin: 0.70,
    end: 1.00,
  ).chain(CurveTween(curve: Easing.legacyDecelerate));

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeInTransition.animate(animation),
      child: ScaleTransition(
        scale: _scaleInTransition.animate(animation),
        child: child,
      ),
    );
  }
}
