/// One ranked list from the service's statistics answer: the busiest domains, the most blocked
/// names, or the busiest clients.
///
/// The ranking is the service's (`/api/v1/querylog/stats` returns `topDomains` / `topBlocked` /
/// `topClients` already ordered and capped). The page shows it as the old desktop console's
/// statistics panel does (`frontend/src/components/overview/QueryStatsPanel.vue`): a numbered row
/// per name, and a proportion bar where the list is about volume rather than about being blocked.
library;

import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_desktop/data/api/desktop_api_models.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// How a row's count is coloured: the blocked list reads as an alarm, the others as plain volume.
enum LogRankingTone { volume, blocked }

class LogRankingCard extends StatelessWidget {
  const LogRankingCard({
    super.key,
    required this.title,
    required this.glyph,
    required this.items,
    this.tone = LogRankingTone.volume,
    this.emptyLabel,
    this.bar = false,
  });

  final String title;
  final Glyph glyph;
  final List<QueryNameCount> items;
  final LogRankingTone tone;

  /// Shown instead of the rows; the blocked list says it has nothing blocked rather than no data.
  final String? emptyLabel;

  /// Draws a proportion bar under each name, scaled to the largest count in the list.
  final bool bar;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: glyph,
            title: title,
            leading: [
              if (items.isNotEmpty)
                DashboardChip(
                  label: '${items.length}',
                  tone: DashboardChipTone.idle,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            // Centred with room around it: a lone left-aligned "no data" line under a header
            // reads as content that failed to load rather than as an empty list.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyLabel ?? context.l10n.commonNoData,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.label(context),
              ),
            )
          else
            for (final (index, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _RankingRow(
                  rank: index + 1,
                  item: item,
                  tone: tone,
                  ratio: bar ? _ratio(item) : null,
                ),
              ),
        ],
      ),
    );
  }

  /// Bars compare within the list, which is all the service ranked; a zero maximum would divide by
  /// zero, so an empty list or an all-zero one draws nothing.
  double _ratio(QueryNameCount item) {
    var max = 0;
    for (final other in items) {
      if (other.count > max) max = other.count;
    }
    return max == 0 ? 0 : item.count / max;
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.rank,
    required this.item,
    required this.tone,
    this.ratio,
  });

  final int rank;
  final QueryNameCount item;
  final LogRankingTone tone;

  /// 0..1 when the row carries a bar; null for the lists that do not.
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final countColor = tone == LogRankingTone.blocked
        ? colorScheme.error
        : colorScheme.onSurface;
    final name = Row(
      spacing: 8,
      children: [
        _RankBadge(rank: rank, tone: tone),
        Expanded(
          child: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context),
          ),
        ),
        Text(
          dashboardCount(item.count),
          maxLines: 1,
          style: DashboardText.label(context, color: countColor),
        ),
      ],
    );
    final ratio = this.ratio;
    if (ratio == null) return name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 3,
      children: [
        name,
        _ProportionBar(
          ratio: ratio,
          color: tone == LogRankingTone.blocked
              ? colorScheme.error
              : colorScheme.primary,
        ),
      ],
    );
  }
}

/// `1`, `2`, `3` in the accent for the leading three, plain for the rest.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.tone});

  final int rank;
  final LogRankingTone tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final leading = rank <= 3;
    final background = leading
        ? (tone == LogRankingTone.blocked
              ? colorScheme.error
              : colorScheme.primary)
        : SurfaceLevel.block.colorOf(colorScheme);
    final foreground = leading
        ? colorScheme.onPrimary
        : colorScheme.onSurfaceVariant;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: background,
        shape: AppShape.all(AppCorner.sm),
      ),
      child: Text(
        '$rank',
        maxLines: 1,
        style: AppTextStyle.caption1
            .of(context, emphasized: true)
            .toTabular
            .copyWith(color: foreground),
      ),
    );
  }
}

class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.ratio, required this.color});

  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppShape.all(AppCorner.sm).borderRadius,
      child: SizedBox(
        height: 4,
        child: ColoredBox(
          color: DashboardColors.of(context).track,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: ratio.clamp(0, 1),
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}
