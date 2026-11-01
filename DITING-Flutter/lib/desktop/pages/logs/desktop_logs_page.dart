/// The log branch: the service's 24-hour summary and rankings over the query log it retained, and
/// that log as a paged table.
///
/// The functional blueprint is the old desktop console, not Android: `OverviewView`'s query
/// history and statistics panels (`frontend/src/components/overview/QueryHistoryPanel.vue`,
/// `QueryStatsPanel.vue`) define what these figures mean and which filters the search takes. The
/// layout follows the current desktop style instead: summary and rankings over one wide table.
/// Android's log board is a card board over sqflite, which this host does not have and does not
/// emulate. Nothing here is derived locally: the totals and rankings come from
/// `/api/v1/querylog/stats` and every row from `/api/v1/querylog/search`.
library;

import 'package:diting/app/l10n/l10n.dart';
import 'package:diting/desktop/data/api/desktop_api_models.dart';
import 'package:diting/desktop/data/api/desktop_log_providers.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting/desktop/pages/logs/widgets/log_rankings_card.dart';
import 'package:diting/desktop/pages/logs/widgets/log_summary_card.dart';
import 'package:diting/pages/home/dashboard/dashboard_style.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Wide enough for a table with all of its columns and the summary on one row.
const double _wideBreakpoint = 900;

class DesktopLogsPage extends ConsumerWidget {
  const DesktopLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(desktopQueryStatsProvider);
    void refreshStats() =>
        ref.read(desktopQueryStatsProvider.notifier).refresh();
    void refreshFeed() => ref.invalidate(desktopLogFeedProvider);

    return CommonScaffold(
      title: context.l10n.logsDashboardTitle,
      actions: [
        IconButton(
          tooltip: context.l10n.logsRefresh,
          onPressed: () {
            refreshFeed();
            refreshStats();
          },
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= _wideBreakpoint;
          return PageBody(
            children: [
              // The notice carries its own side padding and sits above the cards, as it does on
              // the dashboard.
              if (snapshot.isStale) StaleStatusNotice(onRetry: refreshStats),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    const SizedBox(height: 8),
                    LogSummaryCard(snapshot: snapshot, onRetry: refreshStats),
                    if (snapshot.stats case final stats?)
                      LogRankings(snapshot: stats, wide: wide),
                    LogQueryTable(wide: wide, onRetry: refreshFeed),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The three ranked lists the service returns with the summary. Shown only once an answer exists:
/// a ranking that cannot be read is already explained by the summary card above, and repeating
/// "offline" three more times would drown it out.
class LogRankings extends StatelessWidget {
  const LogRankings({super.key, required this.snapshot, required this.wide});

  final DesktopQueryStats snapshot;

  /// Whether the three lists sit side by side.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cards = <Widget>[
      LogRankingCard(
        title: l10n.desktopLogTopDomains,
        glyph: AppGlyphs.dns,
        items: snapshot.topDomains,
      ),
      LogRankingCard(
        title: l10n.desktopLogTopBlocked,
        glyph: AppGlyphs.block,
        items: snapshot.topBlocked,
        tone: LogRankingTone.blocked,
        emptyLabel: l10n.desktopLogNoBlocked,
      ),
      LogRankingCard(
        title: l10n.desktopLogTopClients,
        glyph: AppGlyphs.connections,
        items: snapshot.topClients,
        bar: true,
      ),
    ];
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: cards,
      );
    }
    // Intrinsic heights so the three cards share one baseline instead of each sizing its own list.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: dashboardCardGap,
        children: [for (final card in cards) Expanded(child: card)],
      ),
    );
  }
}
