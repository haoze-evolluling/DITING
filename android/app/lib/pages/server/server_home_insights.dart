import 'dart:math' as math;

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_home_charts.dart';
import 'package:diting_android/pages/server/server_home_parts.dart';
import 'package:diting_android/pages/server/server_home_style.dart';
import 'package:diting_android/widgets/note_card.dart';
import 'package:diting_android/widgets/status_pill.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Query count, blocking, cache and latency at a glance.
class ServerRequestOverview extends StatelessWidget {
  const ServerRequestOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    final tiles = [
      ServerMetricTile(
        glyph: AppGlyphs.dns,
        label: l10n.serverQueries,
        value: serverCount(stats.queries),
        color: scheme.primary,
      ),
      ServerMetricTile(
        glyph: AppGlyphs.block,
        label: l10n.serverBlocked,
        value: serverCount(stats.blocked),
        color: ServerHomeColors.mutedInk(context),
      ),
      ServerMetricTile(
        glyph: AppGlyphs.shield,
        label: l10n.serverBlockRate,
        value: serverPercent(stats.blockedRate),
        color: scheme.primary,
      ),
      ServerMetricTile(
        glyph: AppGlyphs.clock,
        label: l10n.serverAverageLatency,
        value: serverMs(stats.averageResponseMs),
        color: ServerHomeColors.mutedInk(context),
      ),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: l10n.serverOverviewTitle,
            trailing: [_WindowChip(label: l10n.serverLast24Hours)],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              if (scale < 1.3 && constraints.maxWidth >= 328) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (index, tile) in tiles.indexed) ...[
                      if (index > 0)
                        Container(
                          width: 1,
                          height: 54,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: ServerHomeColors.divider(context),
                        ),
                      Expanded(child: tile),
                    ],
                  ],
                );
              }
              if (scale >= 1.3) {
                return Column(
                  spacing: 10,
                  children: [
                    for (final (index, tile) in tiles.indexed) ...[
                      if (index > 0)
                        Divider(
                          height: 1,
                          color: ServerHomeColors.divider(context),
                        ),
                      tile,
                    ],
                  ],
                );
              }
              return Column(
                spacing: 14,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 20,
                    children: [
                      Expanded(child: tiles[0]),
                      Expanded(child: tiles[1]),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 20,
                    children: [
                      Expanded(child: tiles[2]),
                      Expanded(child: tiles[3]),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Rolling 24-hour traffic chart with peak, average and legend figures.
class ServerTrafficOverview extends StatelessWidget {
  const ServerTrafficOverview({
    super.key,
    required this.stats,
    required this.running,
  });

  final ServerStats stats;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    final points = stats.perHour;
    final hasTraffic = points.any((point) => point.queries > 0);
    final peak = points.isEmpty
        ? 0
        : points.map((point) => point.queries).reduce(math.max);
    final average = points.isEmpty
        ? 0
        : (points.fold<int>(0, (sum, point) => sum + point.queries) /
                  points.length)
              .round();
    final peakPoint = points.isEmpty
        ? null
        : points.reduce(
            (best, point) => point.queries > best.queries ? point : best,
          );
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: AppGlyphs.network,
            title: l10n.serverTrafficTitle,
            trailing: [_WindowChip(label: l10n.serverLast24Hours)],
          ),
          if (!hasTraffic)
            ServerEmptyPanel(
              glyph: AppGlyphs.network,
              title: l10n.serverNoTraffic,
              body: running
                  ? l10n.serverNoStatistics
                  : l10n.serverTrafficStopped,
            )
          else ...[
            ServerTrafficChart(
              points: points,
              semanticLabel:
                  '${l10n.serverLast24Hours} · ${l10n.serverQueries} '
                  '${serverCount(stats.queries)} · ${l10n.serverBlocked} '
                  '${serverCount(stats.blocked)}',
            ),
            Row(
              children: [
                Text(
                  serverHourLabel(points.first.hour),
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: appTabularFigures,
                      ),
                ),
                const Spacer(),
                Text(
                  serverHourLabel(points.last.hour),
                  style: AppTextStyle.caption2
                      .of(context)
                      .copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: appTabularFigures,
                      ),
                ),
              ],
            ),
            Row(
              spacing: 18,
              children: [
                Expanded(
                  child: ServerLegend(
                    label: l10n.serverQueries,
                    color: ServerHomeColors.chartBase(context),
                    trailing: serverCount(stats.queries),
                  ),
                ),
                Expanded(
                  child: ServerLegend(
                    label: l10n.serverBlocked,
                    color: ServerHomeColors.chartBlocked(context),
                    trailing: serverCount(stats.blocked),
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: ServerHomeColors.divider(context)),
            Row(
              spacing: 12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverTrafficPeak,
                    value: serverCount(peak),
                    hint: peakPoint == null
                        ? l10n.serverPerHour
                        : serverHourLabel(peakPoint.hour),
                  ),
                ),
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverTrafficAverage,
                    value: serverCount(average),
                    hint: l10n.serverPerHour,
                  ),
                ),
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverCacheHit,
                    value: serverPercent(stats.cacheHitRate),
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Blocked vs. allowed split plus the busiest blocked domain.
class ServerBlockingOverview extends StatelessWidget {
  const ServerBlockingOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    final allowed = math.max(0, stats.queries - stats.blocked);
    final topBlocked = stats.topBlockedDomains.isEmpty
        ? null
        : stats.topBlockedDomains.first;
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: AppGlyphs.shield,
            title: l10n.serverBlockingTitle,
            trailing: [
              StatusPill(
                label: serverPercent(stats.blockedRate),
                color: scheme.primary,
                alpha: 0.08,
                foregroundColor: scheme.primary,
                tabular: true,
              ),
            ],
          ),
          if (stats.queries == 0)
            ServerEmptyPanel(
              glyph: AppGlyphs.shield,
              title: l10n.serverNoStatistics,
              body: l10n.serverLogEmptyBody,
            )
          else ...[
            Row(
              spacing: 16,
              children: [
                ServerPercentRing(
                  progress: stats.blockedRate,
                  centerLabel: serverPercent(stats.blockedRate),
                  color: scheme.primary,
                  size: 92,
                  strokeWidth: 8,
                  semanticLabel:
                      '${l10n.serverBlockRate} '
                      '${serverPercent(stats.blockedRate)}',
                ),
                Expanded(
                  child: Column(
                    spacing: 10,
                    children: [
                      ServerLegend(
                        label: l10n.serverBlocked,
                        color: ServerHomeColors.accentStrong(context),
                        trailing: serverCount(stats.blocked),
                      ),
                      ServerLegend(
                        label: l10n.serverAllowed,
                        color: ServerHomeColors.accentMuted(context),
                        trailing: serverCount(allowed),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (topBlocked != null) ...[
              Divider(height: 1, color: ServerHomeColors.divider(context)),
              Row(
                spacing: 9,
                children: [
                  const GlyphIcon(AppGlyphs.block, size: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          l10n.serverTopBlocked,
                          style: AppTextStyle.caption1
                              .of(context)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          topBlocked.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.footnote.of(
                            context,
                            emphasized: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    serverCount(topBlocked.count),
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .toTabular
                        .copyWith(color: scheme.primary),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Cache hit rate with the cached, forwarded and failed counts behind it.
class ServerCacheOverview extends StatelessWidget {
  const ServerCacheOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.l10n;
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: AppGlyphs.database,
            title: l10n.serverCacheEfficiency,
            trailing: [
              StatusPill(
                label: serverPercent(stats.cacheHitRate),
                color: scheme.primary,
                alpha: 0.08,
                foregroundColor: scheme.primary,
                tabular: true,
              ),
            ],
          ),
          if (stats.queries == 0)
            ServerEmptyPanel(
              glyph: AppGlyphs.database,
              title: l10n.serverNoStatistics,
              body: l10n.serverLogEmptyBody,
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 2,
                    children: [
                      Text(
                        serverPercent(stats.cacheHitRate),
                        style: AppTextStyle.title2
                            .of(context, emphasized: true)
                            .toTabular
                            .copyWith(color: scheme.primary),
                      ),
                      Text(
                        l10n.serverCacheHit,
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${serverCount(stats.cached)} / ${serverCount(stats.queries)}',
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            ProgressLine(
              value: stats.cacheHitRate,
              minHeight: 9,
              color: scheme.primary,
            ),
            Row(
              spacing: 12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverLogCached,
                    value: serverCount(stats.cached),
                    color: scheme.primary,
                  ),
                ),
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverCacheForwarded,
                    value: serverCount(stats.forwarded),
                  ),
                ),
                Expanded(
                  child: ServerMiniMetric(
                    label: l10n.serverCacheErrors,
                    value: serverCount(stats.errors),
                    color: stats.errors > 0 ? scheme.error : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: ShapeDecoration(
        color: ServerHomeColors.accentWash(context),
        shape: AppShape.standard,
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: scheme.primary),
      ),
    );
  }
}
