/// The log cards, spread by the home page into its one board: the service's 24-hour summary and
/// rankings over the query log it retained, the queries it pushes live, that log as a paged table,
/// and the retention policy behind all three.
///
/// The functional blueprint is the old desktop console, not Android: `OverviewView`'s query history
/// and statistics panels (`frontend/src/components/overview/QueryHistoryPanel.vue`,
/// `QueryStatsPanel.vue`) define what these figures mean and which filters the search takes.
/// Nothing here is derived locally: the totals and rankings come from `/api/v1/querylog/stats` and
/// every row from `/api/v1/querylog/search`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/pages/logs/widgets/log_config_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_live_panel.dart';
import 'package:diting_desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting_desktop/pages/logs/widgets/log_rankings_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_summary_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The summary, the three rankings, the live stream, the query table and the retention policy, in
/// reading order. A failed stats read still leaves the table and the live stream usable.
List<Widget> desktopLogCards(BuildContext context, WidgetRef ref) {
  final snapshot = ref.watch(desktopQueryStatsProvider);
  void refreshStats() =>
      ref.read(desktopQueryStatsProvider.notifier).refresh();
  void refreshFeed() => ref.invalidate(desktopLogFeedProvider);
  final l10n = context.l10n;
  return [
    LogSummaryCard(snapshot: snapshot, onRetry: refreshStats),
    if (snapshot.stats case final stats?) ...[
      LogRankingCard(
        title: l10n.desktopLogTopDomains,
        glyph: AppGlyphs.dns,
        items: stats.topDomains,
      ),
      LogRankingCard(
        title: l10n.desktopLogTopBlocked,
        glyph: AppGlyphs.block,
        items: stats.topBlocked,
        tone: LogRankingTone.blocked,
        emptyLabel: l10n.desktopLogNoBlocked,
      ),
      LogRankingCard(
        title: l10n.desktopLogTopClients,
        glyph: AppGlyphs.connections,
        items: stats.topClients,
        bar: true,
      ),
    ],
    const LogLivePanel(),
    LogQueryTable(onRetry: refreshFeed),
    const LogConfigCard(),
  ];
}
