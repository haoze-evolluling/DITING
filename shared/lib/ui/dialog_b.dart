// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'dialog.dart';

/// Two actions side by side when both labels fit half the width, else stacked with the first at the
/// bottom.
class _AlertActions extends MultiChildRenderObjectWidget {
  const _AlertActions({required super.children});

  @override
  _RenderAlertActions createRenderObject(BuildContext context) {
    return _RenderAlertActions(textDirection: Directionality.of(context));
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderAlertActions renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _AlertActionsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderAlertActions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _AlertActionsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _AlertActionsParentData> {
  _RenderAlertActions({required TextDirection textDirection})
    : _textDirection = textDirection;

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _AlertActionsParentData) {
      child.parentData = _AlertActionsParentData();
    }
  }

  bool _sideBySide(List<RenderBox> children, double width) =>
      children.length == 2 &&
      children.every(
        (child) =>
            child.getMaxIntrinsicWidth(double.infinity) <=
            (width - _actionGap) / 2,
      );

  double _childWidth(bool sideBySide, double width) =>
      sideBySide ? (width - _actionGap) / 2 : width;

  double _widest(double Function(RenderBox child) widthOf) =>
      getChildrenAsList().map(widthOf).fold(0, math.max);

  double _heightFor(
    double width,
    double Function(RenderBox child, double width) heightOf,
  ) {
    final children = getChildrenAsList();
    if (children.isEmpty) {
      return 0;
    }
    final sideBySide = _sideBySide(children, width);
    final heights = children.map(
      (child) => heightOf(child, _childWidth(sideBySide, width)),
    );
    return sideBySide
        ? heights.reduce(math.max)
        : heights.reduce((a, b) => a + b) + _actionGap * (children.length - 1);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widest((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widest((child) => child.getMaxIntrinsicWidth(height));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _heightFor(width, (child, width) => child.getMaxIntrinsicHeight(width));

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    bool place = false,
  }) {
    final children = getChildrenAsList();
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _widest((child) => child.getMaxIntrinsicWidth(double.infinity));
    final sideBySide = _sideBySide(children, width);
    final childConstraints = BoxConstraints.tightFor(
      width: _childWidth(sideBySide, width),
    );
    final sizes = [
      for (final child in children) layoutChild(child, childConstraints),
    ];
    final height = sizes.isEmpty
        ? 0.0
        : sideBySide
        ? math.max(sizes.first.height, sizes.last.height)
        : sizes.fold(0.0, (sum, size) => sum + size.height) +
              _actionGap * (sizes.length - 1);
    if (place) {
      final rtl = _textDirection == TextDirection.rtl;
      var y = 0.0;
      for (var step = 1; step <= children.length; step++) {
        final index = step % children.length;
        final size = sizes[index];
        final parentData =
            children[index].parentData! as _AlertActionsParentData;
        if (sideBySide) {
          final atLeft = (index == 0) != rtl;
          parentData.offset = Offset(
            atLeft ? 0 : width - size.width,
            (height - size.height) / 2,
          );
        } else {
          parentData.offset = Offset(0, y);
          y += size.height + _actionGap;
        }
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}
