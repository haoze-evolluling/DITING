/// A waterfall grid for desktop pages: every child keeps its natural height and lands in the
/// shortest column, so a short card never leaves a hole under a tall neighbour.
///
/// Columns are fixed by the caller (the pages own their breakpoints); this widget only decides
/// which column each child goes into and how tall the whole board is. Children are laid out at the
/// column width, which means cards may be measured once and then placed without a second frame.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

class MasonryGrid extends MultiChildRenderObjectWidget {
  const MasonryGrid({
    super.key,
    required this.columns,
    this.spacing = 16,
    this.runSpacing = 16,
    required super.children,
  });

  /// Number of columns; at least one is always laid out.
  final int columns;

  /// Horizontal gap between two columns.
  final double spacing;

  /// Vertical gap between two children in the same column.
  final double runSpacing;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMasonry(
    columns: columns,
    spacing: spacing,
    runSpacing: runSpacing,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final masonry = renderObject as _RenderMasonry;
    masonry
      ..setColumns(columns)
      ..setSpacing(spacing)
      ..setRunSpacing(runSpacing);
  }
}

class _MasonryParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderMasonry extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _MasonryParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _MasonryParentData> {
  _RenderMasonry({
    required int columns,
    required this._spacing,
    required this._runSpacing,
  }) : _columns = math.max(1, columns);

  int _columns;
  double _spacing;
  double _runSpacing;

  void setColumns(int value) {
    final next = math.max(1, value);
    if (next == _columns) return;
    _columns = next;
    markNeedsLayout();
  }

  void setSpacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  void setRunSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _MasonryParentData) {
      child.parentData = _MasonryParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => _layout(
    BoxConstraints.tightFor(width: width),
    ChildLayoutHelper.dryLayoutChild,
  ).height;

  @override
  double computeMaxIntrinsicHeight(double width) => _layout(
    BoxConstraints.tightFor(width: width),
    ChildLayoutHelper.dryLayoutChild,
  ).height;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild);

  @override
  void performLayout() {
    size = _layout(constraints, ChildLayoutHelper.layoutChild, place: true);
  }

  /// Lays every child out at the column width, assigns it to the shortest column and, when
  /// [place] is true, records its offset. Dry layout and real layout share the arithmetic so a
  /// dry pass can never predict a different height than the painted one.
  Size _layout(
    BoxConstraints constraints,
    ChildLayouter layoutChild, {
    bool place = false,
  }) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final columnWidth = math.max(
      0.0,
      (width - _spacing * (_columns - 1)) / _columns,
    );
    final heights = List<double>.filled(_columns, 0);
    var child = firstChild;
    while (child != null) {
      final childSize = layoutChild(
        child,
        BoxConstraints.tightFor(width: columnWidth),
      );
      var column = 0;
      for (var i = 1; i < _columns; i++) {
        if (heights[i] < heights[column]) column = i;
      }
      if (place) {
        (child.parentData! as _MasonryParentData).offset = Offset(
          column * (columnWidth + _spacing),
          heights[column],
        );
      }
      heights[column] = heights[column] + childSize.height + _runSpacing;
      child = childAfter(child);
    }
    final tallest = heights.fold(0.0, math.max);
    final height = tallest > 0 ? tallest - _runSpacing : 0.0;
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
