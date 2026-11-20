library;

import 'package:diting_desktop/widgets/masonry_grid.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

const double desktopCardMinWidth = 460;
const double desktopTwoColumnWidth =
    desktopCardMinWidth * 2 + dashboardCardGap + 2 * desktopPageGutter;

const double desktopPageGutter = 24;
const double desktopBoardTopGap = 16;

const double desktopSingleColumnMaxWidth = 960;

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

  final List<Widget> cards;

  final EdgeInsetsGeometry padding;

  final bool singleColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
