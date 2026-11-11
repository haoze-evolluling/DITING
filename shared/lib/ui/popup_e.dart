// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.

part of 'popup.dart';

class CommonPopupMenu extends StatefulWidget {
  const CommonPopupMenu({
    super.key,
    required this.items,
    this.maxVisibleItems,
    this.dense = false,
  });

  final List<CommonPopupMenuItem> items;

  /// Half the next row shows past these, telling the menu scrolls; rows in view share one height.
  final int? maxVisibleItems;

  /// Smaller rows, icons and type, for menus inside small surfaces.
  final bool dense;

  @override
  State<CommonPopupMenu> createState() => _CommonPopupMenuState();
}

class _MenuStep {
  const _MenuStep({
    required this.index,
    required this.itemTop,
    required this.itemHeight,
    required this.cardWidth,
  });

  final int index;
  final double itemTop;
  final double itemHeight;
  final double cardWidth;
}

class _MenuLevel {
  const _MenuLevel({
    required this.items,
    required this.top,
    required this.fromWidth,
    required this.minWidth,
    required this.maxWidth,
    this.owner,
    this.step,
  });

  final List<CommonPopupMenuItem> items;
  final CommonPopupMenuItem? owner;

  final _MenuStep? step;
  final double top;
  final double fromWidth;
  final double minWidth;
  final double maxWidth;
}

class _Span extends Animatable<double> {
  const _Span(this.begin, this.end);

  final double begin;
  final double end;

  @override
  double transform(double t) => ((t - begin) / (end - begin)).clamp(0.0, 1.0);
}
