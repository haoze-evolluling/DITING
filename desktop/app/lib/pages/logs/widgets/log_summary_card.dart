/// The 24-hour request summary: the figures the old desktop console shows in its statistics panel
/// (`frontend/src/components/overview/QueryStatsPanel.vue`), read from the service's own aggregate
/// instead of being recounted from a page of rows.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/data/api/desktop_log_providers.dart';
import 'package:diting_desktop/pages/home/desktop_format.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class LogSummaryCard extends StatelessWidget {
  const LogSummaryCard({
    super.key,
    required this.snapshot,
    required this.onRetry,
  });

  final DesktopQueryStatsSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final summary = snapshot.stats?.summary;
    return DashboardCard(
      semanticLabel: l10n.logRequestsOverview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.requests,
            title: l10n.logRequestsOverview,
            leading: [
              DashboardChip(label: l10n.desktopLogWindow24h, dot: true),
            ],
          ),
          const SizedBox(height: 16),
          if (summary == null)
            _Unavailable(snapshot: snapshot, onRetry: onRetry)
          else
            _Figures(summary: summary),
        ],
      ),
    );
  }
}

class _Figures extends StatelessWidget {
  const _Figures({required this.summary});

  final QueryStatsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    String count(int value) => dashboardCount(value);
    final cells = <(String, String, Color?)>[
      (l10n.logStatsTotal, count(summary.queries), colorScheme.onSurface),
      (l10n.logPassed, count(summary.passed), colorScheme.primary),
      (l10n.logBlocked, count(summary.blocked), colorScheme.error),
      (l10n.logCacheHits, count(summary.cached), colorScheme.tertiary),
      (l10n.logFailed, count(summary.errors), colorScheme.error),
      (
        l10n.logAverageLatency,
        desktopLatency(summary.averageResponseMs),
        colorScheme.onSurface,
      ),
      (
        l10n.logCacheHitRate,
        summary.queries == 0 ? desktopNoValue : desktopPercent(summary.cacheHitRate),
        colorScheme.success,
      ),
    ];
    // Four equal cells per row: seven figures then sit as 4 + 3 instead of 3 + 3 + a lone
    // last cell, and the grid narrows to two columns on its own when the text is scaled up.
    return DashboardMetricGrid(
      maxColumns: 4,
      runGap: 16,
      metrics: [
        for (final (label, value, color) in cells)
          DashboardMetric(label: label, value: value, color: color),
      ],
    );
  }
}

/// Before the first answer, and after a failed one. A summary that cannot be read says so in
/// place, so the table below it does not look like the whole story.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.snapshot, required this.onRetry});

  final DesktopQueryStatsSnapshot snapshot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    if (snapshot.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CommonCircleLoading(size: 20)),
      );
    }
    return Row(
      spacing: 8,
      children: [
        GlyphIcon(AppGlyphs.warning, size: 18, color: colorScheme.warning),
        Expanded(
          child: Text(
            l10n.desktopBackendOfflineTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context),
          ),
        ),
        TextButton(onPressed: onRetry, child: Text(l10n.desktopRetry)),
      ],
    );
  }
}
