// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'scroll.dart';

class _ScrollbarHintPill extends StatelessWidget {
  final String label;
  final double? scrubRate;

  const _ScrollbarHintPill({required this.label, required this.scrubRate});

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final style = AppTextStyle.caption1.of(context, emphasized: true);
    final rate = scrubRate;
    return DecoratedBox(
      key: const ValueKey('scrollbarHintPill'),
      decoration: ShapeDecoration(
        color: SurfaceLevel.floatingOf(colorScheme).colorOf(colorScheme),
        shape: AppShape.sm,
        shadows: kElevationToShadow[2],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: style.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            if (rate != null && rate < 1) ...[
              const SizedBox(width: 6),
              Text(
                '×1/${(1 / rate).round()}',
                key: const ValueKey('scrollbarScrubRate'),
                style: style.copyWith(color: colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChanged;

  const _MeasureSize({required this.onChanged, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _MeasureSizeRenderObject(onChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChanged);

  ValueChanged<Size> onChanged;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    if (_oldSize == size) return;
    _oldSize = size;
    final newSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(newSize));
  }
}

class ScrollToEndBox extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final bool enable;
  final VoidCallback? onCancelToEnd;
  final VoidCallback? onResumeToEnd;

  const ScrollToEndBox({
    super.key,
    required this.child,
    required this.controller,
    this.onCancelToEnd,
    this.onResumeToEnd,
    this.enable = true,
  });

  @override
  State<ScrollToEndBox> createState() => _ScrollToEndBoxState();
}

class _ScrollToEndBoxState extends State<ScrollToEndBox> {
  @override
  void didUpdateWidget(ScrollToEndBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enable && !oldWidget.enable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _jumpToEnd() {
    final controller = widget.controller;
    if (!mounted || !widget.enable || !controller.hasClients) {
      return;
    }
    final position = controller.position;
    if (!FollowEndScrollPhysics.isAtEnd(position)) {
      controller.jumpTo(position.maxScrollExtent);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward) {
        widget.onCancelToEnd?.call();
      }
    } else if (notification is ScrollEndNotification) {
      final atEnd = FollowEndScrollPhysics.isAtEnd(notification.metrics);
      if (widget.enable && !atEnd) {
        widget.onCancelToEnd?.call();
      } else if (!widget.enable && atEnd) {
        widget.onResumeToEnd?.call();
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: widget.child,
    );
  }
}
