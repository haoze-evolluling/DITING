import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_common.dart';
import 'package:diting_android/pages/server/server_home_parts.dart';
import 'package:diting_android/pages/server/server_home_style.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:material_ui/material_ui.dart';

/// FlClash-style request summary: a card of equal stat blocks rather than a table.
class ServerRequestOverview extends StatelessWidget {
  const ServerRequestOverview({super.key, required this.stats});

  final ServerStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = context.colorScheme;
    final allowed = (stats.queries - stats.blocked).clamp(0, stats.queries);
    final tiles = [
      _RequestStat(
        glyph: AppGlyphs.dns,
        label: l10n.serverQueries,
        value: serverCount(stats.queries),
        hint: '${l10n.serverCacheHit} ${serverPercent(stats.cacheHitRate)}',
        color: scheme.primary,
      ),
      _RequestStat(
        glyph: AppGlyphs.block,
        label: l10n.serverBlocked,
        value: serverCount(stats.blocked),
        hint: '${l10n.serverAllowed} ${serverCount(allowed)}',
        color: scheme.onSurfaceVariant,
      ),
      _RequestStat(
        glyph: AppGlyphs.shield,
        label: l10n.serverBlockRate,
        value: serverPercent(stats.blockedRate),
        hint: '${serverCount(stats.blocked)} / ${serverCount(stats.queries)}',
        color: scheme.primary,
      ),
      _RequestStat(
        glyph: AppGlyphs.clock,
        label: l10n.serverAverageLatency,
        value: serverMs(stats.averageResponseMs),
        hint: l10n.serverAverageLatencyHint,
        color: scheme.onSurfaceVariant,
      ),
    ];
    final singleColumn = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return ServerSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          ServerCardHeader(
            glyph: AppGlyphs.dataUsage,
            title: l10n.serverOverviewTitle,
            trailing: [ServerWindowChip(label: l10n.serverLast24Hours)],
          ),
          if (singleColumn)
            Column(
              spacing: 10,
              children: [
                for (final tile in tiles) _RequestStatBlock(data: tile),
              ],
            )
          else
            Column(
              spacing: 10,
              children: [
                Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _RequestStatBlock(data: tiles[0])),
                    Expanded(child: _RequestStatBlock(data: tiles[1])),
                  ],
                ),
                Row(
                  spacing: 10,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _RequestStatBlock(data: tiles[2])),
                    Expanded(child: _RequestStatBlock(data: tiles[3])),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RequestStat {
  const _RequestStat({
    required this.glyph,
    required this.label,
    required this.value,
    required this.hint,
    required this.color,
  });

  final Glyph glyph;
  final String label;
  final String value;
  final String hint;
  final Color color;
}

class _RequestStatBlock extends StatelessWidget {
  const _RequestStatBlock({required this.data});

  final _RequestStat data;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return DashboardBlock(
      color: ServerHomeColors.accentSubtle(context),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Row(
            spacing: 6,
            children: [
              GlyphIcon(data.glyph, size: 15, color: data.color),
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              data.value,
              maxLines: 1,
              style: DashboardText.figure(
                context,
                AppTextRole.metricSmall,
                color: scheme.onSurface,
              ),
            ),
          ),
          Text(
            data.hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.micro
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
