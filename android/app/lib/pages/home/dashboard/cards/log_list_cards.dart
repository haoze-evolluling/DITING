import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/log_dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/pages/home/dashboard/cards/traffic_monitor_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_android/state/log_dashboard_overview_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// List-style cards of the log dashboard, shared by home and `/logs`.
///
/// Each card watches its own slice of the overview snapshot (see
/// `state/log_dashboard_overview_providers.dart`), so the 10 s refresh rebuilds only the cards whose
/// figures moved. A `null` slice means "not loaded yet", which is how cells show a dash, not `0`.

String _figure(int? value) => value == null ? '—' : dashboardCount(value);

class RequestOverviewCard extends ConsumerWidget {
  const RequestOverviewCard({super.key, this.title, this.onDetail});

  final String? title;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(logOverviewBreakdownProvider);
    final colorScheme = context.colorScheme;
    final l10n = context.l10n;
    return DashboardMetricQuadCard(
      glyph: AppGlyphs.requests,
      title: title ?? l10n.logRequestsOverview,
      onDetail: onDetail,
      cells: [
        (
          label: l10n.logTodayRequests,
          value: _figure(stats?.total),
          color: colorScheme.primary,
        ),
        (
          label: l10n.logPassed,
          value: _figure(stats?.passed),
          color: colorScheme.primary,
        ),
        (
          label: l10n.logFiltered,
          value: _figure(stats?.blocked),
          color: colorScheme.error,
        ),
        (
          label: l10n.logCacheHits,
          value: _figure(stats?.cached),
          color: colorScheme.tertiary,
        ),
      ],
    );
  }
}

class FilteredHighlightCard extends ConsumerWidget {
  const FilteredHighlightCard({super.key, this.title, this.onDetail});

  final String? title;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(logOverviewBreakdownProvider);
    final colorScheme = context.colorScheme;
    final l10n = context.l10n;
    return DashboardMetricQuadCard(
      glyph: AppGlyphs.rules,
      title: title ?? l10n.logHighlights,
      onDetail: onDetail,
      cells: [
        (
          label: l10n.logHighlights,
          value: _figure(stats == null ? null : stats.blocked + stats.error),
          color: colorScheme.primary,
        ),
        (
          label: l10n.logBlocked,
          value: _figure(stats?.blocked),
          color: colorScheme.error,
        ),
        (
          label: l10n.logFailed,
          value: _figure(stats?.error),
          color: colorScheme.error,
        ),
        (
          label: l10n.logBypassed,
          value: _figure(stats?.bypassed),
          color: colorScheme.secondary,
        ),
      ],
    );
  }
}

class OffModeMetricCard extends ConsumerWidget {
  const OffModeMetricCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(logOverviewOffModeProvider);
    final colorScheme = context.colorScheme;
    return DashboardMetricQuadCard(
      glyph: AppGlyphs.eyeOff,
      title: context.l10n.logOffModeTitle,
      onDetail: onDetail,
      cells: [
        (
          label: context.l10n.logCacheEntries,
          value: _figure(stats?.cacheEntries),
          color: colorScheme.primary,
        ),
        (
          label: context.l10n.logCacheHitsTotal,
          value: _figure(stats?.cacheHits),
          color: colorScheme.tertiary,
        ),
        (
          label: context.l10n.logRaceRequests,
          value: _figure(stats?.raceRequests),
          color: colorScheme.secondary,
        ),
        (
          label: context.l10n.logBootstrapAttempts,
          value: _figure(stats?.bootstrapAttempts),
          color: colorScheme.primary,
        ),
      ],
    );
  }
}

class RecentRequestsLogCard extends ConsumerWidget {
  const RecentRequestsLogCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(logOverviewRecentRequestsProvider);
    final colorScheme = context.colorScheme;
    return DashboardLogListCard(
      glyph: AppGlyphs.requests,
      title: context.l10n.logRecentRequests,
      emptyText: context.l10n.logRecentRequestsEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.name,
            subtitle: '${row.time} · ${row.source} · ${row.meta}',
            tag: row.resultLabel,
            tagColor: _statusColor(colorScheme, row.status),
          ),
      ],
    );
  }
}

class FilteredRecentLogCard extends ConsumerWidget {
  const FilteredRecentLogCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(logOverviewRecentRequestsProvider);
    final colorScheme = context.colorScheme;
    // Keep only blocked / failed / bypass: the rows this mode actually persists.
    final rows = [
      for (final row in all)
        if (row.status != LogRowStatus.passed &&
            row.status != LogRowStatus.cached)
          row,
    ];
    return DashboardLogListCard(
      glyph: AppGlyphs.block,
      title: context.l10n.logRecentBlocked,
      emptyText: context.l10n.logRecentBlockedEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.name,
            subtitle: '${row.time} · ${row.source} · ${row.meta}',
            tag: row.resultLabel,
            tagColor: _statusColor(colorScheme, row.status),
          ),
      ],
    );
  }
}

class CacheHotspotsCard extends ConsumerWidget {
  const CacheHotspotsCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(logOverviewCacheHotspotsProvider);
    final colorScheme = context.colorScheme;
    return DashboardLogListCard(
      glyph: AppGlyphs.layers,
      title: context.l10n.logCacheHotspots,
      emptyText: context.l10n.logCacheHotspotsEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.queryName,
            subtitle:
                '${row.queryType} · '
                '${context.l10n.logExpiresIn(dashboardDuration(row.remainingSeconds, context.l10n))} · '
                '${dashboardCount(row.responseSize)} B',
            tag: context.l10n.logTimes(dashboardCount(row.hitCount)),
            tagColor: colorScheme.tertiary,
          ),
      ],
    );
  }
}

class RaceWinnersCard extends ConsumerWidget {
  const RaceWinnersCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(logOverviewRaceWinnersProvider);
    final colorScheme = context.colorScheme;
    return DashboardLogListCard(
      glyph: AppGlyphs.shuffle,
      title: context.l10n.logRaceWinners,
      emptyText: context.l10n.logRaceWinnersEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.name,
            subtitle: context.l10n.logAverageWinLatency(
              dashboardLatency(row.averageElapsedMs),
            ),
            tag: context.l10n.logTimes(dashboardCount(row.wins)),
            tagColor: colorScheme.secondary,
          ),
      ],
    );
  }
}

class BootstrapDnsCard extends ConsumerWidget {
  const BootstrapDnsCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(logOverviewBootstrapIpsProvider);
    final colorScheme = context.colorScheme;
    return DashboardLogListCard(
      glyph: AppGlyphs.dns,
      title: 'Bootstrap DNS',
      emptyText: context.l10n.logBootstrapDnsEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.name,
            subtitle: context.l10n.logBootstrapRow(
              row.ip,
              dashboardPercent(row.successRate),
              dashboardLatency(row.averageElapsedMs),
            ),
            tag: context.l10n.logTimes(dashboardCount(row.attempts)),
            tagColor: colorScheme.primary,
          ),
      ],
    );
  }
}

class RuleBlocksCard extends ConsumerWidget {
  const RuleBlocksCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(logOverviewSubscriptionBlocksProvider);
    final colorScheme = context.colorScheme;
    return DashboardLogListCard(
      glyph: AppGlyphs.rules,
      title: context.l10n.logRuleBlocks,
      emptyText: context.l10n.logRuleBlocksEmpty,
      onDetail: onDetail,
      rows: [
        for (final row in rows)
          DashboardLogRow(
            title: row.name,
            subtitle: context.l10n.logShareRow(
              dashboardPercent(row.rate),
              row.statusLabel,
            ),
            tag: context.l10n.logTimes(dashboardCount(row.hits)),
            tagColor: colorScheme.error,
          ),
      ],
    );
  }
}

class PrivacyModeCard extends StatelessWidget {
  const PrivacyModeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: context.l10n.logPrivacyMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: context.l10n.logPrivacyMode,
            trailing: [DashboardChip(label: context.l10n.logLoggingOff)],
          ),
          SizedBox(height: 12 * scale),
          Text(
            context.l10n.logPrivacyModeBody,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// Resolution efficiency card. Average latency shows a dash when there is no timing sample,
/// not `0 ms`.
class ResolutionPerfCard extends ConsumerWidget {
  const ResolutionPerfCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(logOverviewQualityProvider);
    final race = ref.watch(logOverviewRaceProvider);
    final bootstrap = ref.watch(logOverviewBootstrapProvider);
    final scale = DashboardDensityScope.scaleOf(context);
    final latency = quality?.averageLatencyMs;
    return DashboardCard(
      semanticLabel: context.l10n.logPerfTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: context.l10n.logPerfTitle,
            trailing: [DashboardChip(label: context.l10n.logTodayStats)],
          ),
          SizedBox(height: 14 * scale),
          DashboardRateRow(
            label: context.l10n.logAverageLatency,
            value: quality == null
                ? '—'
                : latency == null
                ? context.l10n.logNoTimingSamples
                : context.l10n.logSampleValue(
                    dashboardLatency(latency),
                    dashboardCount(quality.latencySamples),
                  ),
            // Latency is not a ratio, so pass 0 to render text only (no bar at progress 0).
            progress: 0,
          ),
          SizedBox(height: 14 * scale),
          DashboardRateRow(
            label: context.l10n.logCacheHitRate,
            value: quality == null
                ? '—'
                : context.l10n.logCacheHitRateValue(
                    dashboardPercent(quality.cacheHitRate),
                  ),
            progress: quality?.cacheHitRate ?? 0,
          ),
          SizedBox(height: 14 * scale),
          DashboardRateRow(
            label: context.l10n.logRaceSuccessRate,
            value: race == null
                ? '—'
                : context.l10n.logRateValue(
                    dashboardPercent(race.successRate),
                    dashboardCount(race.requests),
                    dashboardLatency(race.averageElapsedMs),
                  ),
            progress: race?.successRate ?? 0,
          ),
          SizedBox(height: 14 * scale),
          DashboardRateRow(
            label: context.l10n.logBootstrapSuccessRate,
            value: bootstrap == null
                ? '—'
                : context.l10n.logRateValue(
                    dashboardPercent(bootstrap.successRate),
                    dashboardCount(bootstrap.attempts),
                    dashboardLatency(bootstrap.averageElapsedMs),
                  ),
            progress: bootstrap?.successRate ?? 0,
          ),
          SizedBox(height: 2 * scale),
        ],
      ),
    );
  }
}

Color _statusColor(ColorScheme colorScheme, LogRowStatus status) =>
    switch (status) {
      LogRowStatus.passed || LogRowStatus.cached => colorScheme.primary,
      LogRowStatus.filtered || LogRowStatus.failed => colorScheme.error,
      LogRowStatus.bypassed => colorScheme.secondary,
    };
