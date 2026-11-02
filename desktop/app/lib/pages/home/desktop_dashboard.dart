/// The dashboard cards of the home page: one board of natural-height cards, laid out by the shared
/// `DesktopCardBoard` one/two-column rule like every other desktop page.
///
/// The cards are returned as a list, not a widget, so the home page can append its device and log
/// cards to the same board; a second board would leave the page with two waterfalls and a hole
/// between them.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/pages/home/widgets/dashboard_cards.dart';
import 'package:diting_desktop/pages/home/widgets/dashboard_tiles.dart';
import 'package:diting_desktop/pages/home/widgets/recent_queries_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The dashboard cards in reading order. The home page spreads them into the board it shares with
/// the device and log cards.
List<Widget> desktopDashboardCards(DesktopStatus status) => [
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
