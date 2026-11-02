import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/log_dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/log_dashboard_overview_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// One legend segment. Order follows the mode, see [TrafficStructureMode].
class TrafficStructureLegend {
  const TrafficStructureLegend({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

class TrafficStructureRate {
  const TrafficStructureRate({
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;
  final double progress;
}

enum TrafficStructureMode { all, filtered }

/// Layout only; callers compute the numbers so the card cannot drift across midnight.
class TrafficStructureCard extends StatelessWidget {
  const TrafficStructureCard({
    super.key,
    required this.mode,
    required this.title,
    required this.total,
    required this.segments,
    required this.legends,
    required this.rates,
    this.badgeLabel,
  });

  final TrafficStructureMode mode;
  final String title;
  final int total;

  /// Donut segments, same order as [legends]; zero-value segments are filtered.
  final List<DonutSegment> segments;
  final List<TrafficStructureLegend> legends;
  final List<TrafficStructureRate> rates;

  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final compact = legends.length <= 3;
    return DashboardCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: title,
            trailing: [
              DashboardChip(
                label: badgeLabel ?? context.l10n.trafficStructureLive,
              ),
            ],
          ),
          SizedBox(height: 14 * scale),
          Row(
            spacing: 20,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DashboardResultDonut(
                segments: segments,
                total: total,
                // Smaller donut for three-row legends so the text does not outgrow it.
                diameter: compact ? 108 : 128,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: compact ? 12 * scale : 8 * scale,
                  children: [
                    for (final legend in legends)
                      DashboardLegendRow(
                        label: legend.label,
                        value: legend.value,
                        color: legend.color,
                      ),
                  ],
                ),
              ),
            ],
          ),
          for (final rate in rates) ...[
            SizedBox(height: 14 * scale),
            DashboardRateRow(
              label: rate.label,
              value: rate.value,
              progress: rate.progress,
            ),
          ],
          SizedBox(height: 2 * scale),
        ],
      ),
    );
  }
}

/// Traffic structure card backed by the real aggregate snapshot. A not-ready snapshot
/// renders an empty ring and dashes, never 0%, which would read as "no traffic today".
class LogTrafficStructureCard extends ConsumerWidget {
  const LogTrafficStructureCard({super.key, required this.mode});

  final TrafficStructureMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(
      logDashboardProvider.select((async) => async.value),
    );
    final breakdown = snapshot?.breakdown ?? const LogTrafficBreakdown.empty();
    final colorScheme = context.colorScheme;
    final filtered = mode == TrafficStructureMode.filtered;
    final race = snapshot?.race ?? const LogRaceSummary.empty();
    final bootstrap = snapshot?.bootstrap ?? const LogBootstrapSummary.empty();
    final ready = snapshot != null;
    return TrafficStructureCard(
      mode: mode,
      title: filtered ? context.l10n.trafficStructureFocused : context.l10n.trafficStructureToday,
      total: filtered ? (snapshot?.highlightedTotal ?? 0) : breakdown.total,
      segments: filtered
          ? [
              if (breakdown.blocked > 0)
                (value: breakdown.blocked, color: colorScheme.error),
              if (breakdown.error > 0)
                (
                  value: breakdown.error,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
              if (breakdown.bypassed > 0)
                (value: breakdown.bypassed, color: colorScheme.secondary),
            ]
          : [
              if (breakdown.passed > 0)
                (value: breakdown.passed, color: colorScheme.primary),
              if (breakdown.blocked > 0)
                (value: breakdown.blocked, color: colorScheme.error),
              if (breakdown.error > 0)
                (
                  value: breakdown.error,
                  color: colorScheme.error.withValues(alpha: 0.7),
                ),
              if (breakdown.bypassed > 0)
                (value: breakdown.bypassed, color: colorScheme.secondary),
              if (breakdown.cached > 0)
                (value: breakdown.cached, color: colorScheme.tertiary),
            ],
      legends: filtered
          ? [
              TrafficStructureLegend(
                label: context.l10n.logFiltered,
                value: dashboardCount(breakdown.blocked),
                color: colorScheme.error,
              ),
              TrafficStructureLegend(
                label: context.l10n.commonFailed,
                value: dashboardCount(breakdown.error),
                color: colorScheme.error.withValues(alpha: 0.7),
              ),
              TrafficStructureLegend(
                label: context.l10n.trafficStructureBypass,
                value: dashboardCount(breakdown.bypassed),
                color: colorScheme.secondary,
              ),
            ]
          : [
              TrafficStructureLegend(
                label: context.l10n.logPassed,
                value: dashboardCount(breakdown.passed),
                color: colorScheme.primary,
              ),
              TrafficStructureLegend(
                label: context.l10n.logFiltered,
                value: dashboardCount(breakdown.blocked),
                color: colorScheme.error,
              ),
              TrafficStructureLegend(
                label: context.l10n.commonFailed,
                value: dashboardCount(breakdown.error),
                color: colorScheme.error.withValues(alpha: 0.7),
              ),
              TrafficStructureLegend(
                label: context.l10n.trafficStructureBypass,
                value: dashboardCount(breakdown.bypassed),
                color: colorScheme.secondary,
              ),
              TrafficStructureLegend(
                label: context.l10n.trafficStructureCache,
                value: dashboardCount(breakdown.cached),
                color: colorScheme.tertiary,
              ),
            ],
      rates: [
        TrafficStructureRate(
          label: context.l10n.trafficStructureRaceRate,
          value: ready
              ? context.l10n.trafficStructureRateValue(
                  dashboardPercent(race.successRate),
                  dashboardCount(race.requests),
                  dashboardLatency(race.averageElapsedMs),
                )
              : '—',
          progress: race.successRate,
        ),
        TrafficStructureRate(
          label: context.l10n.trafficStructureBootstrapRate,
          value: ready
              ? context.l10n.trafficStructureRateValue(
                  dashboardPercent(bootstrap.successRate),
                  dashboardCount(bootstrap.attempts),
                  dashboardLatency(bootstrap.averageElapsedMs),
                )
              : '—',
          progress: bootstrap.successRate,
        ),
        TrafficStructureRate(
          label: filtered ? context.l10n.trafficStructureBlockedShare : context.l10n.trafficStructureBlockRate,
          value: ready
              ? context.l10n.trafficStructureShareValue(
                  dashboardPercent(breakdown.blockRate),
                  dashboardCount(breakdown.blocked),
                )
              : '—',
          progress: breakdown.blockRate,
        ),
        if (!filtered)
          TrafficStructureRate(
            label: context.l10n.trafficStructureCacheRate,
            value: ready
                ? context.l10n.trafficStructureShareValue(
                    dashboardPercent(breakdown.cacheRate),
                    dashboardCount(breakdown.cached),
                  )
                : '—',
            progress: breakdown.cacheRate,
          ),
      ],
    );
  }
}
