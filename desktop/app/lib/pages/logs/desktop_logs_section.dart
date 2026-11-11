/// The log cards the home page spreads into its one board: the service's 24-hour summary and
/// rankings over the retained query log.
///
/// The blueprint is the old desktop console (`OverviewView`'s `QueryStatsPanel.vue`), not Android.
/// Nothing is derived locally: totals and rankings come from `/api/v1/querylog/stats`.
///
/// Only readings live on the dashboard. The live stream, searchable history and retention policy
/// are settings/queries and live on `hub/query-log`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/pages/logs/widgets/log_rankings_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_summary_card.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// The summary and the three rankings, in reading order.
List<Widget> desktopLogCards(BuildContext context, WidgetRef ref) {
  final snapshot = ref.watch(desktopQueryStatsProvider);
  void refreshStats() =>
      ref.read(desktopQueryStatsProvider.notifier).refresh();
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
  ];
}
