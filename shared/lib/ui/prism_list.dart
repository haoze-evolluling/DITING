// themselves vendor super_sliver_list (Copyright (c) 2024 Matej Knopp, Superlist
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

export 'package:super_sliver_list/super_sliver_list.dart' show ListController;

class SliverPrismList extends StatelessWidget {
  static const defaultEstimatedItemExtent = 64.0;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final double? itemExtent;
  final double estimatedItemExtent;
  final ChildIndexGetter? findChildIndexCallback;
  final ListController? listController;
  final bool addRepaintBoundaries;

  const SliverPrismList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 0,
    this.itemExtent,
    this.estimatedItemExtent = defaultEstimatedItemExtent,
    this.findChildIndexCallback,
    this.listController,
    this.addRepaintBoundaries = true,
  }) : assert(listController == null || (gap == 0 && itemExtent == null));

  double _estimate(int? index, double crossAxisExtent) {
    final extent = itemExtent ?? estimatedItemExtent;
    if (gap == 0) {
      return extent;
    }
    return switch (index) {
      null => 0,
      _ when index.isEven => extent,
      _ => gap,
    };
  }

  SliverChildBuilderDelegate _delegate() {
    if (gap == 0) {
      return SliverChildBuilderDelegate(
        itemBuilder,
        childCount: itemCount,
        findChildIndexCallback: findChildIndexCallback,
        addRepaintBoundaries: addRepaintBoundaries,
      );
    }
    final findChildIndex = findChildIndexCallback;
    return SliverChildBuilderDelegate(
      (context, index) => index.isEven
          ? itemBuilder(context, index ~/ 2)
          : SizedBox.square(dimension: gap),
      childCount: math.max(0, itemCount * 2 - 1),
      findChildIndexCallback: findChildIndex == null
          ? null
          : (key) => switch (findChildIndex(key)) {
              final index? => index * 2,
              null => null,
            },
      addRepaintBoundaries: addRepaintBoundaries,
      semanticIndexCallback: (_, index) => index.isEven ? index ~/ 2 : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemExtent = this.itemExtent;
    if (itemExtent != null && gap == 0) {
      return SliverFixedExtentList(
        itemExtent: itemExtent,
        delegate: _delegate(),
      );
    }
    return SuperSliverList(
      delegate: _delegate(),
      listController: listController,
      extentEstimation: _estimate,
    );
  }
}

class PrismListView extends BoxScrollView {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final double? itemExtent;
  final double estimatedItemExtent;
  final ChildIndexGetter? findChildIndexCallback;
  final ListController? listController;
  final bool addRepaintBoundaries;

  const PrismListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.primary,
    super.physics,
    super.shrinkWrap,
    super.padding,
    super.scrollCacheExtent,
    super.keyboardDismissBehavior,
    super.clipBehavior,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 0,
    this.itemExtent,
    this.estimatedItemExtent = SliverPrismList.defaultEstimatedItemExtent,
    this.findChildIndexCallback,
    this.listController,
    this.addRepaintBoundaries = true,
  }) : super(semanticChildCount: itemCount);

  @override
  Widget buildChildLayout(BuildContext context) {
    return SliverPrismList(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      gap: gap,
      itemExtent: itemExtent,
      estimatedItemExtent: estimatedItemExtent,
      findChildIndexCallback: findChildIndexCallback,
      listController: listController,
      addRepaintBoundaries: addRepaintBoundaries,
    );
  }
}
