import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_chart.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class StatusDetailPage extends ConsumerWidget {
  const StatusDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreStateProvider);
    final mode = ref.watch(workModeProvider);
    final stats = ref.watch(serviceStatsProvider);
    final primary = ref.watch(primaryProviderProvider);
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final health = _healthOf(core, colorScheme);
    return DashboardDetailScaffold(
      title: context.l10n.statusDetailTitle,
      children: [
        DashboardDetailHero(
          glyph: TablerIcons.clock,
          label: context.l10n.statusUptime,
          value: core.isRunning
              ? stats.uptimeLabel
              : context.l10n.statusNotTiming,
          color: core.isRunning ? colorScheme.onSurface : null,
          chipLabel: core.label(context.l10n),
          chipColor: health.color,
          hint: core.isRunning
              ? health.summary
              : context.l10n.statusPausedSummary(
                  mode.title(context.l10n),
                  core.label(context.l10n),
                ),
        ),
        DashboardDetailCard(
          glyph: TablerIcons.circle_check,
          title: context.l10n.healthTitle,
          child: InkWell(
            onTap: () => context.push('/health'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                context.l10n.healthEntrySubtitle,
                style: AppTextRole.body
                    .of(context)
                    .copyWith(color: colorScheme.primary),
              ),
            ),
          ),
        ),
        DashboardDetailCard(
          glyph: TablerIcons.activity,
          title: context.l10n.statusCoreSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 10,
                children: [
                  Icon(health.glyph, size: 20, color: health.color),
                  Expanded(
                    child: Text(
                      health.summary,
                      style: AppTextRole.body
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DashboardDetailRows(
                rows: [
                  DashboardDetailRow(
                    label: context.l10n.statusWorkMode,
                    value: mode.title(context.l10n),
                  ),
                  DashboardDetailRow(
                    label: context.l10n.statusCoreState,
                    value: core.label(context.l10n),
                  ),
                ],
              ),
            ],
          ),
        ),
        DashboardDetailCard(
          glyph: TablerIcons.cloud_upload,
          title: context.l10n.statusActiveProvider,
          footer: primary == null ? null : context.l10n.statusProviderFooter,
          child: primary == null
              ? Text(
                  context.l10n.statusNoProviderHint,
                  style: AppTextRole.body
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                )
              : Row(
                  spacing: 12,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        spacing: 3,
                        children: [
                          Text(
                            primary.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextRole.bodyStrong
                                .of(context)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                          Text(
                            '${primary.protocol.label} · ${primary.address}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextRole.caption
                                .of(context)
                                .copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontFeatures: appTabularFigures,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _LatencyBadge(provider: primary),
                  ],
                ),
        ),
        DashboardDetailCard(
          glyph: TablerIcons.clock,
          title: context.l10n.statusTodayCounts,
          footer: context.l10n.statusCountsFooter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DashboardStatGrid(
                  stats: [
                    StatItem(
                      label: context.l10n.statusQueries,
                      value: dashboardCount(stats.queries),
                    ),
                    StatItem(
                      label: context.l10n.logCacheHits,
                      value: dashboardCount(stats.cacheHits),
                      color: colorScheme.primary,
                    ),
                    StatItem(
                      label: context.l10n.statusBlocked,
                      value: dashboardCount(stats.blocked),
                      color: colorScheme.error,
                    ),
                    StatItem(
                      label: context.l10n.statusAverageLatency,
                      value: stats.averageLatencyMs <= 0
                          ? '—'
                          : '${stats.averageLatencyMs}',
                      unit: stats.averageLatencyMs <= 0 ? null : 'ms',
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  Row(
                    children: [
                      Text(
                        context.l10n.statusCacheHitRate,
                        style: AppTextRole.caption
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Text(
                        dashboardPercent(stats.cacheHitRate),
                        style: DashboardText.figure(
                          context,
                          AppTextRole.metricCompact,
                          color: stats.cacheHits > 0
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  DashboardShareBar(
                    segments: [
                      (
                        value: stats.cacheHits.toDouble(),
                        color: colorScheme.primary,
                      ),
                      (
                        value: stats.blocked.toDouble(),
                        color: colorScheme.error,
                      ),
                      (
                        value: (stats.queries - stats.cacheHits - stats.blocked)
                            .clamp(0, stats.queries)
                            .toDouble(),
                        color: colors.track,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static ({IconData glyph, Color color, String summary}) _healthOf(
    CoreState core,
    ColorScheme colorScheme,
  ) {
    final glyph = switch (core) {
      CoreState.running => TablerIcons.circle_check,
      CoreState.failed => TablerIcons.alert_circle,
      CoreState.starting || CoreState.stopped => TablerIcons.info_circle,
    };
    final color = switch (core) {
      CoreState.running => colorScheme.success,
      CoreState.failed => colorScheme.error,
      CoreState.starting || CoreState.stopped => colorScheme.onSurfaceVariant,
    };
    final summary = core.isRunning
        ? currentL10n.statusTunnelActive
        : currentL10n.statusCoreStopped;
    return (glyph: glyph, color: color, summary: summary);
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.provider});

  final MockProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final measured = provider.latencyMs >= 0;
    return StatusPill(
      label: providerLatencyLabel(provider),
      color: DashboardColors.of(context).tone,
      foregroundColor: measured
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tabular: true,
    );
  }
}
