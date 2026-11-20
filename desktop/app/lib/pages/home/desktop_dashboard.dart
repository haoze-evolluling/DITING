library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/pages/home/widgets/dashboard_cards.dart';
import 'package:diting_desktop/pages/home/widgets/dashboard_tiles.dart';
import 'package:diting_desktop/pages/home/widgets/recent_queries_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

List<Widget> desktopDashboardCards(DesktopStatus status) => [
  DnsServiceCard(status: status),
  QueryMetricsCard(status: status),
  const HostServiceCard(),
  CacheCard(status: status),
  FilterStatsCard(status: status),
  PerformanceCard(status: status),
  RuntimeCard(status: status),
  const RecentQueriesCard(),
];

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
