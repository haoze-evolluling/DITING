import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class TrafficMonitorCard extends ConsumerWidget {
  const TrafficMonitorCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = context.colorScheme;
    return DashboardCard(
      semanticLabel: context.l10n.trafficMonitorTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          DashboardCardHeader(
            glyph: TablerIcons.chart_pie,
            title: context.l10n.trafficMonitorTitle,
            trailing: [
              if (onDetail != null)
                DashboardIconButton(
                  glyph: TablerIcons.chevron_right,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: onDetail,
                ),
            ],
          ),
          Row(
            spacing: 12,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      context.l10n.trafficMonitorToday,
                      style: DashboardText.label(context),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final totals = ref.watch(trafficTotalsProvider).value;
                        return Text(
                          totals == null
                              ? '—'
                              : dashboardBinaryBytes(totals.total),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.figure(
                            context,
                            AppTextRole.metricSmall,
                            color: colorScheme.primary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      context.l10n.trafficMonitorLiveRate,
                      style: DashboardText.label(context),
                    ),
                    Consumer(
                      builder: (context, ref, _) => Text(
                        ref.watch(
                          speedSeriesProvider.select(
                            (series) => _speedText(series, context.l10n),
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: DashboardText.figure(
                          context,
                          AppTextRole.metricCompact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _speedText(SpeedSeries series, AppL10n l10n) {
  if (series.unsupported) return l10n.trafficMonitorNoStats;
  if (series.samples.isEmpty) return '—';
  final last = series.last;
  return '↓ ${dashboardBinarySpeed(last.down)}  '
      '↑ ${dashboardBinarySpeed(last.up)}';
}

class DashboardMetricCell extends StatelessWidget {
  const DashboardMetricCell({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.label(context),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.figure(
            context,
            AppTextRole.metricSmall,
            color: color,
          ),
        ),
      ],
    );
  }
}

class DashboardMetricQuadCard extends StatelessWidget {
  const DashboardMetricQuadCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.cells,
    this.onDetail,
    this.trailing,
  });

  final IconData glyph;
  final String title;

  final List<({String label, String value, Color color})> cells;
  final VoidCallback? onDetail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scale = DashboardDensityScope.scaleOf(context);
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      final pair = cells.skip(i).take(2).toList();
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 14 * scale),
          child: Row(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cell in pair)
                Expanded(
                  child: DashboardMetricCell(
                    label: cell.label,
                    value: cell.value,
                    color: cell.color,
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return DashboardCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: glyph,
            title: title,
            trailing: [
              ?trailing,
              if (onDetail != null)
                DashboardIconButton(
                  glyph: TablerIcons.chevron_right,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: onDetail,
                ),
            ],
          ),
          SizedBox(height: 12 * scale),
          ...rows,
        ],
      ),
    );
  }
}
