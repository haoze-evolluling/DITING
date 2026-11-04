/// The one card board every desktop page uses: one column below [minTwoColumnWidth] and a
/// two-column masonry above it.
///
/// Every child is one card and always occupies exactly one column. Pages must not place a card
/// outside the board to make it span the full width; put it in [cards] like the rest.
library;

import 'package:diting_desktop/widgets/masonry_grid.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

class DesktopCardBoard extends StatelessWidget {
  const DesktopCardBoard({
    super.key,
    required this.cards,
    this.maxWidth = 1280,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
    this.singleColumn = false,
  });

  /// Cards in reading order. Each one is laid out at the column width.
  final List<Widget> cards;

  /// A two-column board on a very wide monitor would stretch each card past a readable width;
  /// the board centers itself inside this bound instead.
  final double maxWidth;

  final EdgeInsetsGeometry padding;

  /// Keeps a page in one column even on a wide board, even though the cards would fit side by
  /// side. Used where a card is itself a grid (the appearance card) and where the cards read top to
  /// bottom as one flow (app blocking: the group shortcuts above the service catalogue).
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = singleColumn
            ? 1
            : dashboardColumnsOf(constraints.maxWidth);
        final board = columns <= 1
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: dashboardCardGap,
                children: cards,
              )
            : MasonryGrid(
                columns: columns,
                spacing: dashboardCardGap,
                runSpacing: dashboardCardGap,
                children: cards,
              );
        return Padding(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: board,
            ),
          ),
        );
      },
    );
  }
}
