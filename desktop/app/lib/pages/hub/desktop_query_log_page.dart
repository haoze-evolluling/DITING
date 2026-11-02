/// The `hub` branch's query log page: the live stream, the searchable history and the retention
/// policy.
///
/// These three are queries and settings, not readings, so they left the dashboard when it became a
/// page of figures. The live stream and the table keep their old blueprints
/// (`LiveQueryPanel.vue`, `QueryHistoryPanel.vue`); the policy card is `QueryLogConfigCard.vue`.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/pages/logs/widgets/log_config_card.dart';
import 'package:diting_desktop/pages/logs/widgets/log_live_panel.dart';
import 'package:diting_desktop/pages/logs/widgets/log_query_table.dart';
import 'package:diting_desktop/widgets/desktop_card_board.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class DesktopQueryLogPage extends ConsumerWidget {
  const DesktopQueryLogPage({super.key});

  static const path = '/hub/query-log';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    void refreshFeed() => ref.invalidate(desktopLogFeedProvider);
    return CommonScaffold(
      title: l10n.desktopQueryLogPageTitle,
      actions: [
        IconButton(
          tooltip: l10n.logsRefresh,
          onPressed: refreshFeed,
          icon: const GlyphIcon(AppGlyphs.refresh),
        ),
      ],
      body: PageBody(
        children: [
          DesktopCardBoard(
            cards: [
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
