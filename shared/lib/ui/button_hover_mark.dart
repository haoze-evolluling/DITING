// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'button.dart';

// iOS 27 on iPad marks the button of a group under a pointer with a capsule
// 4 pt inside the group, sliding to the next on this spring and fading in
// place as the pointer comes and goes; the group does not swell.
const _markAlpha = 0.08;
const _markInsets = EdgeInsets.symmetric(horizontal: 2, vertical: 4);
final _markSlide = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 2350,
  ratio: 0.95,
);
final _markFade = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 380),
);

class _HoverMark {
  _HoverMark(TickerProvider vsync)
    : _travel = AnimationController.unbounded(vsync: vsync, value: 1),
      _shown = AnimationController.unbounded(vsync: vsync);

  final AnimationController _travel;
  final AnimationController _shown;
  late final Listenable _motion = Listenable.merge([_travel, _shown]);
  final _area = GlobalKey();
  Object? _slot;
  RenderBox? _box;
  Rect? _from;
  Rect? _painted;

  bool get _hidden => _shown.value < 0.01;

  void enter(Object slot, RenderBox box) {
    _slot = slot;
    _box = box;
    _from = _hidden ? null : _painted;
    if (_from == null) {
      _travel.value = 1;
    } else {
      _travel.value = 0;
      _springTo(_travel, 1, _markSlide);
    }
    _springTo(_shown, 1, _markFade);
  }

  void leave(Object slot) {
    if (_slot == slot) {
      _slot = null;
      _box = null;
      _from = _painted;
      _springTo(_shown, 0, _markFade);
    }
  }

  static void _springTo(
    AnimationController controller,
    double target,
    SpringDescription spring,
  ) {
    controller.animateWith(
      SpringSimulation(spring, controller.value, target, controller.velocity),
    );
  }

  /// Where the button under the pointer shows in the area now, cut by the
  /// clips between them, as a bar's search narrows its slot.
  Rect? _slotRect() {
    final box = _box;
    final area = _area.currentContext?.findRenderObject();
    if (box == null || !box.attached || area is! RenderBox) {
      return null;
    }
    var rect = MatrixUtils.transformRect(
      box.getTransformTo(area),
      Offset.zero & box.size,
    );
    RenderObject child = box;
    for (var node = box.parent; node != null && node != area;) {
      final clip = node.describeApproximatePaintClip(child);
      if (clip != null) {
        rect = rect.intersect(
          MatrixUtils.transformRect(node.getTransformTo(area), clip),
        );
      }
      child = node;
      node = node.parent;
    }
    return _markInsets.deflateRect(rect);
  }

  Rect? _rect() {
    if (_hidden) {
      return _painted = null;
    }
    final slot = _slotRect();
    final from = _from;
    final rect = slot == null
        ? from
        : from == null
        ? slot
        : Rect.lerp(from, slot, _travel.value);
    return _painted = rect;
  }

  Widget build(BuildContext context, Widget row) {
    return Stack(
      key: _area,
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _HoverMarkPainter(
              mark: this,
              color: context.colorScheme.onSurface,
            ),
          ),
        ),
        row,
      ],
    );
  }

  void dispose() {
    _travel.dispose();
    _shown.dispose();
  }
}

class _HoverMarkPainter extends CustomPainter {
  _HoverMarkPainter({required this.mark, required this.color})
    : super(repaint: mark._motion);

  final _HoverMark mark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = mark._rect();
    if (rect == null || rect.width <= 0 || rect.height <= 0) {
      return;
    }
    canvas.drawPath(
      AppShape.full.getOuterPath(rect),
      Paint()
        ..color = color.withValues(
          alpha: _markAlpha * math.min(mark._shown.value, 1),
        ),
    );
  }

  @override
  bool shouldRepaint(_HoverMarkPainter oldDelegate) =>
      mark != oldDelegate.mark || color != oldDelegate.color;
}

class _HoverMarkScope extends InheritedWidget {
  const _HoverMarkScope({required this.mark, required super.child});

  final _HoverMark mark;

  static _HoverMark? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HoverMarkScope>()?.mark;

  @override
  bool updateShouldNotify(_HoverMarkScope oldWidget) => mark != oldWidget.mark;
}

class _HoverSlot extends StatefulWidget {
  const _HoverSlot({
    required this.mark,
    required this.enabled,
    required this.child,
  });

  final _HoverMark mark;
  final bool enabled;
  final Widget child;

  @override
  State<_HoverSlot> createState() => _HoverSlotState();
}

class _HoverSlotState extends State<_HoverSlot> {
  void _handleEnter(PointerEnterEvent event) {
    if (widget.enabled && event.kind != PointerDeviceKind.touch) {
      widget.mark.enter(this, context.findRenderObject()! as RenderBox);
    }
  }

  void _handleExit(PointerExitEvent event) => widget.mark.leave(this);

  @override
  void didUpdateWidget(_HoverSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.mark != oldWidget.mark) {
      oldWidget.mark.leave(this);
    }
  }

  @override
  void dispose() {
    widget.mark.leave(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      opaque: false,
      onEnter: _handleEnter,
      onExit: _handleExit,
      child: widget.child,
    );
  }
}
