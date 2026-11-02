// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'sortable.dart';

/// Springs in from the row trailing edge, where the card clips it; only a width change relayouts.
class SortableTrailing extends StatefulWidget {
  const SortableTrailing({super.key, required this.item, this.child});

  final SortableItemData item;
  final Widget? child;

  @override
  State<SortableTrailing> createState() => _SortableTrailingState();
}

class _SortableTrailingState extends State<SortableTrailing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: widget.item.sorting ? 1 : 0,
  )..addStatusListener(_handleStatus);

  @override
  void didUpdateWidget(SortableTrailing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.sorting == widget.item.sorting) {
      return;
    }
    final sorting = widget.item.sorting;
    _controller.animateTo(
      sorting ? 1 : 0,
      duration: context.motionDuration(
        sorting ? _enterDuration : _exitDuration,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleStatus(AnimationStatus status) {
    if (!status.isAnimating) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorting = widget.item.sorting;
    return RepaintBoundary(
      child: _SortableSlot(
        animation: _controller,
        sorting: sorting,
        children: [
          ExcludeSemantics(
            excluding: sorting,
            child: ExcludeFocus(
              excluding: sorting,
              child: widget.child ?? const SizedBox.shrink(),
            ),
          ),
          if (sorting || _controller.isAnimating)
            SortHandle(index: widget.item.index),
        ],
      ),
    );
  }
}

class _SortableSlot extends MultiChildRenderObjectWidget {
  const _SortableSlot({
    required this.animation,
    required this.sorting,
    super.children,
  });

  final Animation<double> animation;
  final bool sorting;

  @override
  _RenderSortableSlot createRenderObject(BuildContext context) =>
      _RenderSortableSlot(
        animation: animation,
        sorting: sorting,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSortableSlot renderObject,
  ) {
    renderObject
      ..animation = animation
      ..sorting = sorting
      ..textDirection = Directionality.of(context);
  }
}

class _SlotParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSortableSlot extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlotParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlotParentData> {
  _RenderSortableSlot({
    required Animation<double> animation,
    required bool sorting,
    required TextDirection textDirection,
  }) : _animation = animation,
       _sorting = sorting,
       _textDirection = textDirection;

  Animation<double> _animation;
  bool _sorting;
  TextDirection _textDirection;
  double? _laidOutWidthProgress;
  final _trailingLayer = LayerHandle<TransformLayer>();
  final _handleLayer = LayerHandle<TransformLayer>();

  set animation(Animation<double> value) {
    if (identical(value, _animation)) {
      return;
    }
    if (attached) {
      _animation.removeListener(_handleTick);
      value.addListener(_handleTick);
    }
    _animation = value;
    markNeedsLayout();
  }

  set sorting(bool value) {
    if (value == _sorting) {
      return;
    }
    _sorting = value;
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _trailing => firstChild!;

  RenderBox? get _handle => childAfter(firstChild!);

  double get _widthProgress {
    final value = _animation.value;
    return _sorting
        ? const Interval(0, 0.5, curve: Curves.easeOutCubic).transform(value)
        : 1 -
              const Interval(
                0.2,
                0.8,
                curve: Curves.easeInOutCubic,
              ).transform(1 - value);
  }

  double get _handleProgress {
    final value = _animation.value;
    return _sorting
        ? _handleSpring.transform(value)
        : const Interval(0.55, 1, curve: Curves.easeOut).transform(value);
  }

  double get _trailingScale {
    final value = _animation.value;
    return _sorting
        ? 1 - const Interval(0, 0.2, curve: Curves.easeIn).transform(value)
        : const Interval(
            0.4,
            1,
            curve: Curves.easeOutBack,
          ).transform(1 - value);
  }

  void _handleTick() {
    final resizing =
        _laidOutWidthProgress != null &&
        _laidOutWidthProgress != _widthProgress;
    if (resizing) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlotParentData) {
      child.parentData = _SlotParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(_handleTick);
  }

  @override
  void detach() {
    _animation.removeListener(_handleTick);
    super.detach();
  }

  @override
  void dispose() {
    _trailingLayer.layer = null;
    _handleLayer.layer = null;
    super.dispose();
  }

  double _lerpWidth(double trailing, double? handle) =>
      handle == null ? trailing : lerpDouble(trailing, handle, _widthProgress)!;

  @override
  double computeMinIntrinsicWidth(double height) => _lerpWidth(
    _trailing.getMinIntrinsicWidth(height),
    _handle?.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => _lerpWidth(
    _trailing.getMaxIntrinsicWidth(height),
    _handle?.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    _trailing.getMinIntrinsicHeight(width),
    _handle?.getMinIntrinsicHeight(width) ?? 0,
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    _trailing.getMaxIntrinsicHeight(width),
    _handle?.getMaxIntrinsicHeight(width) ?? 0,
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final loose = constraints.loosen();
    final trailing = _trailing.getDryLayout(loose);
    final handle = _handle?.getDryLayout(loose);
    return constraints.constrain(
      Size(
        _lerpWidth(trailing.width, handle?.width),
        math.max(trailing.height, handle?.height ?? 0),
      ),
    );
  }

  @override
  void performLayout() {
    final loose = constraints.loosen();
    final trailing = _trailing..layout(loose, parentUsesSize: true);
    final handle = _handle?..layout(loose, parentUsesSize: true);
    final resizes = handle != null && handle.size.width != trailing.size.width;
    _laidOutWidthProgress = resizes ? _widthProgress : null;
    size = constraints.constrain(
      Size(
        _lerpWidth(trailing.size.width, handle?.size.width),
        math.max(trailing.size.height, handle?.size.height ?? 0),
      ),
    );
    for (final child in [trailing, ?handle]) {
      (child.parentData! as _SlotParentData).offset = Offset(
        _textDirection == TextDirection.rtl ? 0 : size.width - child.size.width,
        (size.height - child.size.height) / 2,
      );
    }
  }

  Matrix4 _transformOf(RenderBox child) {
    final offset = (child.parentData! as _SlotParentData).offset;
    if (child != _trailing) {
      final direction = _textDirection == TextDirection.rtl ? -1 : 1;
      return Matrix4.translationValues(
        offset.dx +
            direction *
                _handleTravel *
                (1 - _handleProgress) *
                child.size.width,
        offset.dy,
        0,
      );
    }
    final scale = _trailingScale;
    return Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
      offset.dx + child.size.width / 2 * (1 - scale),
      offset.dy + child.size.height / 2 * (1 - scale),
      0,
    );
  }

  TransformLayer? _paintChild(
    PaintingContext context,
    Offset offset,
    RenderBox child,
    TransformLayer? oldLayer,
  ) => context.pushTransform(
    needsCompositing,
    offset,
    _transformOf(child),
    (context, offset) => context.paintChild(child, offset),
    oldLayer: oldLayer,
  );

  @override
  void paint(PaintingContext context, Offset offset) {
    _trailingLayer.layer = _trailingScale <= 0
        ? null
        : _paintChild(context, offset, _trailing, _trailingLayer.layer);
    final handle = _handle;
    _handleLayer.layer = handle == null
        ? null
        : _paintChild(context, offset, handle, _handleLayer.layer);
  }

  bool _hitTestChild(
    BoxHitTestResult result,
    Offset position,
    RenderBox child,
  ) => result.addWithPaintTransform(
    transform: _transformOf(child),
    position: position,
    hitTest: (result, position) => child.hitTest(result, position: position),
  );

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final handle = _handle;
    if (handle != null && _hitTestChild(result, position, handle)) {
      return true;
    }
    return !_sorting &&
        _trailingScale > 0 &&
        _hitTestChild(result, position, _trailing);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transformOf(child));
  }
}

IconButtonData sortModeAction(
  BuildContext context, {
  required bool sorting,
  required VoidCallback? onPressed,
}) {
  final localizations = UiLocalizations.of(context);
  return IconButtonData(
    glyph: AppGlyphs.sort,
    onPressed: onPressed,
    tooltip: localizations.sort,
    isSelected: sorting,
  );
}
