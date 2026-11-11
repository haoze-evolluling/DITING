/// Read-only cards of the desktop dashboard. Each one renders one slice of the polled
/// `/api/v1/status` snapshot; the values are the service's, never a locally remembered guess.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_desktop/pages/home/desktop_format.dart';
import 'package:diting_desktop/widgets/desktop_spacing.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// The listener itself: whether it is up, where it listens and whether the LAN can reach it.
class DnsServiceCard extends StatelessWidget {
  const DnsServiceCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dns = status.dns;
    final running = dns.running;
    final listen = dns.listenSummary;
    return DashboardCard(
      semanticLabel: l10n.desktopDnsServiceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dns,
            title: l10n.desktopDnsServiceTitle,
            leading: [
              DashboardChip(
                label: running ? l10n.stateRunning : l10n.stateStopped,
                tone: running ? DashboardChipTone.ok : DashboardChipTone.idle,
                dot: true,
              ),
            ],
          ),
          DashboardMetric(
            label: l10n.desktopListeningOn,
            value: listen.isEmpty ? l10n.statusNotListening : listen,
            color: context.colorScheme.onSurface,
            style: AppTextStyle.title2,
          ),
          DashboardMetricGrid(
            maxColumns: 3,
            metrics: [
              DashboardMetric(
                label: l10n.desktopLanAllowed,
                value: dns.allowLan
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
              ),
              DashboardMetric(
                label: l10n.desktopTakeoverTitle,
                value: status.takeover.active
                    ? l10n.desktopTakeoverOn
                    : l10n.desktopTakeoverOff,
              ),
              DashboardMetric(
                label: l10n.statusUptime,
                value: desktopUptime(status.uptime),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Counts since the service started, plus the live rate.
class QueryMetricsCard extends StatelessWidget {
  const QueryMetricsCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metrics = status.metrics;
    return DashboardCard(
      semanticLabel: l10n.desktopQueriesTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: l10n.desktopQueriesTitle,
            leading: [
              DashboardChip(
                label: '${desktopQps(metrics.qps)} ${l10n.desktopQps}',
                dot: true,
              ),
            ],
          ),
          DashboardMetric(
            label: l10n.desktopQueriesTotal,
            value: dashboardCount(metrics.total),
            color: context.colorScheme.onSurface,
            style: AppTextStyle.title2,
          ),
          DashboardMetricGrid(
            metrics: [
              DashboardMetric(
                label: l10n.desktopQueriesSuccess,
                value: dashboardCount(metrics.success),
                color: context.colorScheme.success,
              ),
              DashboardMetric(
                label: l10n.desktopQueriesFailed,
                value: dashboardCount(metrics.failed),
                color: metrics.failed > 0 ? context.colorScheme.warning : null,
              ),
              DashboardMetric(
                label: l10n.statusBlocked,
                value: dashboardCount(status.filter.blocked),
              ),
              DashboardMetric(
                label: l10n.statusAverageLatency,
                value: desktopLatency(metrics.averageLatencyMs),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Two rows of two figures; the middle row of the desktop grid is built from these.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<DashboardMetric> metrics;

  @override
  Widget build(BuildContext context) =>
      DashboardMetricGrid(maxColumns: 2, metrics: metrics);
}

class CacheCard extends StatelessWidget {
  const CacheCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cache = status.cache;
    return DashboardCard(
      semanticLabel: l10n.desktopCacheTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.resources,
            title: l10n.desktopCacheTitle,
            leading: [
              DashboardChip(
                label: cache.enabled ? l10n.commonEnabled : l10n.commonDisabled,
                tone: cache.enabled
                    ? DashboardChipTone.ok
                    : DashboardChipTone.idle,
              ),
            ],
          ),
          _MetricGrid(
            metrics: [
              DashboardMetric(
                label: l10n.statusCacheHitRate,
                value: desktopPercent(cache.hitRatio),
              ),
              DashboardMetric(
                label: l10n.logCacheEntries,
                value:
                    '${dashboardCount(cache.entries)}'
                    '${cache.maxEntries > 0 ? ' / ${dashboardCount(cache.maxEntries)}' : ''}',
              ),
              DashboardMetric(
                label: l10n.desktopCacheHits,
                value: dashboardCount(cache.hits),
              ),
              DashboardMetric(
                label: l10n.desktopCacheEvictions,
                value: dashboardCount(cache.evictions),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FilterStatsCard extends StatelessWidget {
  const FilterStatsCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = status.filter;
    return DashboardCard(
      semanticLabel: l10n.desktopFilterTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.block,
            title: l10n.desktopFilterTitle,
            leading: [
              DashboardChip(
                label: filter.paused
                    ? l10n.desktopFilterPaused
                    : l10n.desktopFilterActive,
                tone: filter.paused
                    ? DashboardChipTone.warn
                    : DashboardChipTone.ok,
                dot: true,
              ),
            ],
          ),
          _MetricGrid(
            metrics: [
              DashboardMetric(
                label: l10n.desktopFilterBlockRate,
                value: desktopPercent(filter.blockRate),
              ),
              DashboardMetric(
                label: l10n.statusBlocked,
                value: dashboardCount(filter.blocked),
              ),
              DashboardMetric(
                label: l10n.desktopFilterRules,
                value: dashboardCount(filter.rules),
              ),
              DashboardMetric(
                label: l10n.statusQueries,
                value: dashboardCount(filter.totalQueries),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PerformanceCard extends StatelessWidget {
  const PerformanceCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final metrics = status.metrics;
    final answered = metrics.success + metrics.failed;
    return DashboardCard(
      semanticLabel: l10n.desktopPerformanceTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: l10n.desktopPerformanceTitle,
          ),
          _MetricGrid(
            metrics: [
              DashboardMetric(
                label: l10n.desktopQps,
                value: desktopQps(metrics.qps),
              ),
              DashboardMetric(
                label: l10n.statusAverageLatency,
                value: desktopLatency(metrics.averageLatencyMs),
              ),
              DashboardMetric(
                label: l10n.desktopQueriesSuccess,
                value: answered == 0
                    ? desktopNoValue
                    : desktopPercent(metrics.success / answered),
              ),
              DashboardMetric(
                label: l10n.desktopQueriesFailed,
                value: answered == 0
                    ? desktopNoValue
                    : desktopPercent(metrics.failed / answered),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which build is answering, so a bug report from this window names the running service.
class RuntimeCard extends StatelessWidget {
  const RuntimeCard({super.key, required this.status});

  final DesktopStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DashboardCard(
      semanticLabel: l10n.desktopRuntimeTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppGap.sm,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.info,
            title: l10n.desktopRuntimeTitle,
          ),
          _MetricGrid(
            metrics: [
              DashboardMetric(
                label: l10n.desktopVersion,
                value: status.version.isEmpty ? desktopNoValue : status.version,
              ),
              DashboardMetric(
                label: l10n.desktopProcessId,
                value: status.pid > 0 ? '${status.pid}' : desktopNoValue,
              ),
              DashboardMetric(
                label: l10n.statusUptime,
                value: desktopUptime(status.uptime),
              ),
              DashboardMetric(
                label: l10n.desktopLanAllowed,
                value: status.dns.allowLan
                    ? l10n.commonEnabled
                    : l10n.commonDisabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
