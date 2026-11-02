/// The cache page's two read-only cards: the acceleration engine (switch, hit rate, the two
/// actions) and the telemetry figures the service counts.
///
/// The old desktop console's `CachePanel.vue` is the blueprint. Every figure is the service's;
/// the page only formats it.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_cache_models.dart';
import 'package:diting_desktop/pages/hub/widgets/cache_common.dart';
import 'package:diting_desktop/pages/home/desktop_format.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class CacheEngineCard extends StatelessWidget {
  const CacheEngineCard({
    super.key,
    required this.stats,
    required this.enabled,
    required this.busy,
    required this.clearing,
    required this.onToggle,
    required this.onRefresh,
    required this.onClear,
  });

  final DesktopCacheStats stats;

  /// The switch follows the config, not the counters: a stats poll must not move a control the
  /// reader is about to press.
  final bool enabled;
  final bool busy;
  final bool clearing;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopCacheEngineTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.bolt,
            title: l10n.desktopCacheEngineTitle,
            leading: [
              DashboardChip(
                label: enabled
                    ? l10n.desktopCacheEngineOn
                    : l10n.desktopCacheEngineOff,
                tone: enabled ? DashboardChipTone.ok : DashboardChipTone.idle,
                dot: true,
              ),
            ],
            trailing: [
              DashboardSwitch(
                value: enabled,
                semanticLabel: l10n.desktopCacheEngineTitle,
                onChanged: busy ? null : onToggle,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.desktopCacheEngineBody,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.label(context),
          ),
          const SizedBox(height: 12),
          DashboardBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 8,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.desktopCacheHitRatio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardText.rowTitle(context),
                      ),
                    ),
                    Text(
                      desktopPercent(stats.hitRatio),
                      maxLines: 1,
                      style: DashboardText.figure(
                        context,
                        AppTextStyle.title2,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                CacheBar(value: stats.hitRatio, color: colorScheme.primary),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.refresh,
                label: l10n.desktopCacheRefresh,
                onPressed: busy ? null : onRefresh,
              ),
              TonalButton(
                size: TonalButtonSize.compact,
                glyph: AppGlyphs.delete,
                label: l10n.desktopCacheClear,
                onPressed: clearing || stats.entryCount == 0 ? null : onClear,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CacheTelemetryCard extends StatelessWidget {
  const CacheTelemetryCard({super.key, required this.stats});

  final DesktopCacheStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: l10n.desktopCacheTelemetryTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.resources,
            title: l10n.desktopCacheTelemetryTitle,
            leading: [
              DashboardChip(label: '${stats.entryCount} / ${stats.maxEntries}'),
            ],
          ),
          const SizedBox(height: 12),
          _MetricGrid(
            metrics: [
              (
                l10n.desktopCacheHits,
                dashboardCount(stats.hits),
                colorScheme.onSurface,
              ),
              (
                l10n.desktopCacheMisses,
                dashboardCount(stats.misses),
                colorScheme.onSurface,
              ),
              (
                l10n.desktopCacheStaleHits,
                dashboardCount(stats.staleHits),
                stats.staleHits > 0 ? colorScheme.warning : null,
              ),
              (
                l10n.desktopCacheNegativeHits,
                dashboardCount(stats.negativeHits),
                null,
              ),
              (
                l10n.desktopCachePrefetchCount,
                dashboardCount(stats.prefetchCount),
                null,
              ),
              (
                l10n.desktopCacheEvictions,
                dashboardCount(stats.evictions),
                null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.desktopCacheTelemetryCapacity(
                    stats.entryCount,
                    stats.maxEntries,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ),
              Text(
                desktopPercent(stats.fill),
                maxLines: 1,
                style: DashboardText.label(context),
              ),
            ],
          ),
          const SizedBox(height: 6),
          CacheBar(value: stats.fill),
        ],
      ),
    );
  }
}

/// Two columns of three figures; a narrow card stacks to one column of six.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<(String, String, Color?)> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 340;
        final items = [
          for (final (label, value, color) in metrics)
            DashboardMetric(label: label, value: value, color: color),
        ];
        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: items,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            for (var index = 0; index < items.length; index += 2)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 16,
                children: [
                  Expanded(child: items[index]),
                  Expanded(
                    child: index + 1 < items.length
                        ? items[index + 1]
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}
