import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/data/mock_data.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_chart.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/state/primary_provider_providers.dart';
import 'package:diting_android/state/server_status_providers.dart';
import 'package:diting_android/state/work_mode_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/stat_strip.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Status detail: the card only fits run time, the provider name and today's query count. This
/// page adds what the card had to drop — core state wording per work mode, the full service
/// counters (hit / block / latency / hit rate), the provider's protocol and address, and the
/// listening port when server mode owns one.
class StatusDetailPage extends ConsumerWidget {
  const StatusDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(coreStateProvider);
    final mode = ref.watch(workModeProvider);
    final stats = ref.watch(serviceStatsProvider);
    final primary = ref.watch(primaryProviderProvider);
    final serverStatus = ref.watch(serverStatusProvider);
    final port = ref.watch(serverPortProvider);
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final health = _healthOf(mode, core, serverStatus, colorScheme);
    return DashboardDetailScaffold(
      title: context.l10n.statusDetailTitle,
      children: [
        DashboardDetailHero(
          glyph: AppGlyphs.clock,
          label: context.l10n.statusUptime,
          // Not running has no figure: "未计时" says it in words where a lone em dash looked
          // like a stray line under the label.
          value: core.isRunning ? stats.uptimeLabel : context.l10n.statusNotTiming,
          color: core.isRunning ? colorScheme.onSurface : null,
          chipLabel: core.label(context.l10n),
          chipColor: health.color,
          hint: core.isRunning
              ? health.summary
              : context.l10n.statusPausedSummary(mode.title(context.l10n), core.label(context.l10n)),
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.status,
          title: context.l10n.statusCoreSection,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                spacing: 10,
                children: [
                  GlyphIcon(health.glyph, size: 20, color: health.color),
                  Expanded(
                    child: Text(
                      health.summary,
                      style: AppTextStyle.subheadline
                          .of(context)
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DashboardDetailRows(
                rows: [
                  DashboardDetailRow(label: context.l10n.statusWorkMode, value: mode.title(context.l10n)),
                  DashboardDetailRow(label: context.l10n.statusCoreState, value: core.label(context.l10n)),
                  if (mode == AppWorkMode.server)
                    DashboardDetailRow(
                      label: context.l10n.statusListenPort,
                      value: serverStatus == ServerStatus.running
                          ? '$port'
                          : context.l10n.statusNotListening,
                      tabular: true,
                      color: serverStatus == ServerStatus.running
                          ? colorScheme.primary
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
        DashboardDetailCard(
          glyph: AppGlyphs.dns,
          title: context.l10n.statusActiveProvider,
          footer: primary == null ? null : context.l10n.statusProviderFooter,
          child: primary == null
              ? Text(
                  context.l10n.statusNoProviderHint,
                  style: AppTextStyle.subheadline
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
                            style: AppTextStyle.body
                                .of(context, emphasized: true)
                                .copyWith(color: colorScheme.onSurface),
                          ),
                          Text(
                            '${primary.protocol.label} · ${primary.address}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption1
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
          glyph: AppGlyphs.requests,
          title: context.l10n.statusTodayCounts,
          footer:
              context.l10n.statusCountsFooter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DashboardStatGrid(
                  stats: [
                    StatItem(label: context.l10n.statusQueries, value: dashboardCount(stats.queries)),
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
                      // No unit on a missing value: "— ms" reads as a broken number.
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
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      Text(
                        dashboardPercent(stats.cacheHitRate),
                        style: DashboardText.figure(
                          context,
                          AppTextStyle.subheadline,
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

  /// Wording and colour for the core, per work mode: "running" means the tunnel in normal and
  /// express mode but a listening DNS port in server mode.
  static ({Glyph glyph, Color color, String summary}) _healthOf(
    AppWorkMode mode,
    CoreState core,
    ServerStatus serverStatus,
    ColorScheme colorScheme,
  ) {
    final glyph = core.isRunning
        ? AppGlyphs.checkCircle
        : core == CoreState.failed
        ? AppGlyphs.error
        : AppGlyphs.info;
    final l10n = currentL10n;
    final summary = core.isRunning
        ? mode == AppWorkMode.server
              ? l10n.statusServerPortReady
              : l10n.statusTunnelActive
        : mode == AppWorkMode.server
        ? l10n.statusServerPortClosed
        : l10n.statusCoreStopped;
    return (
      glyph: glyph,
      color: core.isRunning
          ? colorScheme.success
          : core == CoreState.failed
          ? colorScheme.error
          : colorScheme.onSurfaceVariant,
      summary: summary,
    );
  }
}

/// Last measured latency of one provider. A provider that has never been probed stores `-1`, which
/// used to be rendered as the literal `-1 ms`; [providerLatencyLabel] turns it into 未测速.
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
