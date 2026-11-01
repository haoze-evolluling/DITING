/// The dashboard board: one column of natural-height cards on a narrow window, two columns of
/// masonry on a wider one. Cards keep the height their content needs and each one goes into the
/// shortest column, so a short card never leaves a hole under a tall neighbour.
library;

import 'dart:math' as math;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/pages/home/widgets/dashboard_cards.dart';
import 'package:diting/desktop/pages/home/widgets/dashboard_tiles.dart';
import 'package:diting/desktop/pages/home/widgets/recent_queries_card.dart';
import 'package:diting/desktop/widgets/masonry_grid.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A two-column board on a very wide monitor would stretch each card past a readable width;
/// the grid centers itself inside this bound instead.
const _maxBoardWidth = 1280.0;

/// Room below the floating app bar plus the design's own gap, so the first card never sits under
/// the title. `TopInsetScope` reads 0 inside a page, so this comes from the bar itself.
double _topPaddingOf(BuildContext context) => context.appBarInset + 12;

/// Clear of whatever floats over the foot: the dock on a narrow window, nothing on a wide one.
double _bottomPaddingOf(BuildContext context) =>
    DockInsetScope.of(context) + MediaQuery.paddingOf(context).bottom + 8;

class DesktopDashboardBoard extends StatelessWidget {
  const DesktopDashboardBoard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = Size(
          constraints.maxWidth / scale,
          constraints.maxHeight / scale,
        );
        final density = DashboardDensity.of(room);
        final columns = dashboardColumnsOf(room.width);
        return DashboardDensityScope(
          density: density,
          scale: scale,
          child: columns <= 1
              ? _StackedCards(status: status, width: room.width)
              : _MasonryBoard(status: status, columns: columns),
        );
      },
    );
  }
}

/// One column of cards, mobile density: heights come from the cards themselves.
class _StackedCards extends StatelessWidget {
  const _StackedCards({required this.status, required this.width});

  final DesktopStatus status;

  /// The width the board was given, not the window's: beside a sidebar the two differ.
  final double width;

  @override
  Widget build(BuildContext context) {
    final side = dashboardMobileSideOf(width);
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        side,
        _topPaddingOf(context),
        side,
        _bottomPaddingOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: _cardsOf(status),
      ),
    );
  }
}

/// Two columns once the window has room: cards keep their content height and fill the shorter
/// column first, so the board reads as a waterfall instead of two equal-height rows.
class _MasonryBoard extends StatelessWidget {
  const _MasonryBoard({required this.status, required this.columns});

  final DesktopStatus status;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final gap = 16.0 * scale;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        16,
        _topPaddingOf(context),
        24,
        _bottomPaddingOf(context),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxBoardWidth),
          child: MasonryGrid(
            columns: columns,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final card in _cardsOf(status)) RepaintBoundary(child: card),
            ],
          ),
        ),
      ),
    );
  }
}

/// The cards in reading order; shared so the stacked and masonry boards cannot drift apart.
List<Widget> _cardsOf(DesktopStatus status) => [
  DnsServiceCard(status: status),
  QueryMetricsCard(status: status),
  TakeoverTile(status: status),
  FilterPauseTile(status: status),
  const HostServiceCard(),
  CacheCard(status: status),
  FilterStatsCard(status: status),
  PerformanceCard(status: status),
  RuntimeCard(status: status),
  const RecentQueriesCard(),
];

/// Shown when the service answered before but the last poll failed: the figures on screen are the
/// last real ones, and saying so is better than silently freezing them.
class StaleStatusNotice extends StatelessWidget {
  const StaleStatusNotice({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
      child: Row(
        spacing: 8,
        children: [
          GlyphIcon(AppGlyphs.warning, size: 18, color: colorScheme.warning),
          Expanded(
            child: Text(
              l10n.desktopBackendOfflineTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardText.rowTitle(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
        ],
      ),
    );
  }
}
