/// The one card board every desktop page uses: one column below [desktopTwoColumnWidth] and a
/// two-column masonry above it.
///
/// Every child is one card and always occupies exactly one column. Pages must not place a card
/// outside the board to make it span the full width; put it in [cards] like the rest.
///
/// The two-column threshold is the desktop's own, not the dashboard's mobile one: a desktop card
/// carries a title row with a chip and a switch, a one-line description and often a form, and below
/// roughly 460 points none of that fits without truncating. The mobile threshold is tuned for
/// 390-wide phones, where a card is allowed to be that narrow because it is the only column.
library;

import 'package:diting_desktop/widgets/masonry_grid.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

/// Narrowest card the two-column board draws, and the width one step above it: the gutter on both
/// sides plus the gap between the columns. 460 is the width at which the densest card (a header with
/// title, chip and switch) still fits its first line.
const double desktopCardMinWidth = 460;
const double desktopTwoColumnWidth =
    desktopCardMinWidth * 2 + dashboardCardGap + 2 * desktopPageGutter;

/// Gutter between the page edge and the board, and the gap above the first card.
const double desktopPageGutter = 24;
const double desktopBoardTopGap = 16;

/// A board holding a single card keeps it near a comfortable reading width and centers it: a lone
/// card pinned to the left edge of a wide empty board reads as a loading failure.
const double desktopSoloCardWidth = 760;

class DesktopCardBoard extends StatelessWidget {
  const DesktopCardBoard({
    super.key,
    required this.cards,
    this.padding = const EdgeInsets.fromLTRB(
      desktopPageGutter,
      desktopBoardTopGap,
      desktopPageGutter,
      0,
    ),
    this.singleColumn = false,
  });

  /// Cards in reading order. Each one is laid out at the column width.
  final List<Widget> cards;

  final EdgeInsetsGeometry padding;

  /// Keeps a page in one column even on a wide board, even though the cards would fit side by
  /// side. Used where a card is itself a grid (the appearance card), where the cards read top to
  /// bottom as one flow (app blocking: the group shortcuts above the service catalogue) and where a
  /// card holds a table whose columns need the full width.
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            singleColumn || constraints.maxWidth < desktopTwoColumnWidth
            ? 1
            : 2;
        // A page that asked for one column has a card that is itself a grid or a table (the
        // appearance palettes), and that card wants the whole board, not a capped measure.
        final board = cards.length == 1 && !singleColumn
            ? Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: desktopSoloCardWidth,
                  ),
                  child: cards.single,
                ),
              )
            : columns <= 1
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
        return Padding(padding: padding, child: board);
      },
    );
  }
}
