/// The one card board every desktop page uses: a two-column masonry for three or more cards once
/// the board is wide enough, and one column everywhere else.
///
/// Every child is one card and always occupies exactly one column. Pages must not place a card
/// outside the board to make it span the full width; put it in [cards] like the rest.
///
/// A page with one or two cards never gets the masonry. Two columns holding a single row do not
/// read as a waterfall, they read as a pair of equals with half the page left empty, and the taller
/// card of the two drags a wide hole under its shorter neighbour. Those pages get one column that
/// is capped at [desktopSingleColumnMaxWidth] and centred, so on a wide window the card keeps a
/// readable measure and its left and right margins match instead of the card hugging one edge.
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

/// Widest the automatic single column (one or two cards) gets on a wide window. The column is
/// centred inside the board, so the margins on both sides stay equal; past this width a form card
/// would stretch into one very long line per field. A page that asks for
/// [DesktopCardBoard.singleColumn] keeps the whole board instead, because that card is itself a
/// grid or a table.
const double desktopSingleColumnMaxWidth = 960;

/// Comfortable reading width for one form card that sits inside a wider board with a sibling beside
/// it, used where a card must not stretch to the full half-pane.
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
  /// card holds a table whose columns need the full width. Such a page keeps the whole board width
  /// instead of the capped, centred column of the automatic single layout.
  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The masonry is for pages that actually have a waterfall to lay out: three or more cards
        // and the width to give each one a readable measure.
        final masonry =
            !singleColumn &&
            cards.length > 2 &&
            constraints.maxWidth >= desktopTwoColumnWidth;
        final column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: dashboardCardGap,
          children: cards,
        );
        return Padding(
          padding: padding,
          child: masonry
              ? MasonryGrid(
                  columns: 2,
                  spacing: dashboardCardGap,
                  runSpacing: dashboardCardGap,
                  children: cards,
                )
              : singleColumn
              ? column
              : Align(
                  alignment: AlignmentDirectional.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: desktopSingleColumnMaxWidth,
                    ),
                    child: column,
                  ),
                ),
        );
      },
    );
  }
}
