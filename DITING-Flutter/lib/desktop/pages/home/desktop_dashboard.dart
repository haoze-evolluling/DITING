/// The dashboard board: upstream FlClash's desktop grid (four columns of at most 440 dp, centered,
/// with a summary row, a control row and a card row) over this app's cards.
///
/// A window narrower than four columns gets one column of cards at their natural height, so no
/// card has to fit a height meant for a wider window.
library;

import 'dart:math' as math;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/pages/home/widgets/dashboard_cards.dart';
import 'package:diting/desktop/pages/home/widgets/dashboard_tiles.dart';
import 'package:diting/desktop/pages/home/widgets/recent_queries_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_density.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Cards never grow past this width; the grid centers what is left over.
const _maxColumnWidth = 440.0;

/// Below this the query list is not worth a row: it would show one entry and a scroll bar.
const _tableMinHeight = 150.0;

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
        return DashboardDensityScope(
          density: density,
          scale: scale,
          child: density.isDesktop
              ? _DesktopGrid(
                  status: status,
                  columns: dashboardColumnsOf(room.width),
                )
              : _StackedCards(status: status, width: room.width),
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

/// The cards in reading order; shared so the stacked and gridded boards cannot drift apart.
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

class _DesktopGrid extends StatelessWidget {
  const _DesktopGrid({required this.status, required this.columns});

  final DesktopStatus status;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final density = DashboardDensityScope.of(context);
    final compact = density.isCompact;
    final scale = DashboardDensityScope.scaleOf(context);
    final gap = 16.0 * scale;
    final base = EdgeInsetsDirectional.fromSTEB(
      16,
      _topPaddingOf(context),
      24,
      _bottomPaddingOf(context),
    );
    final topHeight = (compact ? 176 : 208) * scale;
    final controlHeight = (compact ? 56 : 64) * scale;
    final middleHeight = (compact ? 152 : 176) * scale;
    if (columns < 4) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: base,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: _cardsOf(status),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final room =
            constraints.maxWidth - base.horizontal - gap * (columns - 1);
        final column = math.min(room / columns, _maxColumnWidth * scale);
        final inset = (room - column * columns) / 2;
        final padding = base.copyWith(
          start: base.start + inset,
          end: base.end + inset,
        );
        double span(int count) => column * count + gap * (count - 1);
        Widget cardRow(List<(int, Widget)> cards) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: gap,
          children: [
            for (final (count, card) in cards)
              SizedBox(
                width: span(count),
                child: RepaintBoundary(child: card),
              ),
          ],
        );
        Widget row(double height, List<(int, Widget)> cards) =>
            SizedBox(height: height, child: cardRow(cards));
        final rowsHeight =
            padding.vertical +
            topHeight +
            controlHeight +
            middleHeight +
            gap * 2;
        // A window with room to spare gives it to the query list, as upstream gives its tables the
        // leftover rows; a short one keeps the design heights and scrolls instead of squeezing.
        final fills =
            constraints.maxHeight >= rowsHeight + _tableMinHeight * scale;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: fills ? constraints.maxHeight : null,
            child: Padding(
              padding: padding,
              child: Column(
                spacing: gap,
                children: [
                  row(topHeight, [
                    (2, DnsServiceCard(status: status)),
                    (2, QueryMetricsCard(status: status)),
                  ]),
                  row(controlHeight, [
                    (1, TakeoverTile(status: status)),
                    (1, FilterPauseTile(status: status)),
                    (2, const HostServiceCard()),
                  ]),
                  row(middleHeight, [
                    (1, CacheCard(status: status)),
                    (1, FilterStatsCard(status: status)),
                    (1, PerformanceCard(status: status)),
                    (1, RuntimeCard(status: status)),
                  ]),
                  if (fills)
                    const Expanded(child: RecentQueriesCard())
                  else
                    row(middleHeight, [(4, const RecentQueriesCard())]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
