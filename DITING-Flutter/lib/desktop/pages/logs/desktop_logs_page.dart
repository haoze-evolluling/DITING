/// The log branch: the service's 24-hour summary and rankings over the query log it retained, the
/// queries it pushes live, that log as a paged table, and the retention policy behind all three.
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
import 'package:diting/desktop/data/api/desktop_log_providers.dart';
import 'package:diting/desktop/pages/home/desktop_dashboard.dart';
import 'package:diting/desktop/pages/logs/widgets/log_config_card.dart';
import 'package:diting/desktop/pages/logs/widgets/log_live_panel.dart';
import 'package:diting/desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting/desktop/pages/logs/widgets/log_rankings_card.dart';
import 'package:diting/desktop/pages/logs/widgets/log_summary_card.dart';
import 'package:diting/desktop/widgets/desktop_card_board.dart';
import 'package:diting/ui/ui.dart';
import 'package:diting/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopLogsPage extends ConsumerWidget {
  const DesktopLogsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(desktopQueryStatsProvider);
    void refreshStats() =>
        ref.read(desktopQueryStatsProvider.notifier).refresh();
    void refreshFeed() => ref.invalidate(desktopLogFeedProvider);

    final l10n = context.l10n;
    return CommonScaffold(
      title: l10n.logsDashboardTitle,
      actions: [
        IconButton(
          tooltip: l10n.logsRefresh,
          onPressed: () {
            refreshFeed();
            refreshStats();
          },
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          // The notice carries its own side padding and sits above the cards, as it does on the
          // dashboard.
          if (snapshot.isStale) StaleStatusNotice(onRetry: refreshStats),
          DesktopCardBoard(
            cards: [
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
            ],
          ),
        ],
      ),
    );
  }
}
