import 'package:diting_android/app/l10n/l10n.dart';

import 'dart:math' as math;

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_chart.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:diting_android/widgets/stat_strip.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class NetworkSpeedDetailPage extends ConsumerWidget {
  const NetworkSpeedDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(speedSeriesProvider);
    final totals = ref.watch(trafficTotalsProvider).value;
    final colorScheme = context.colorScheme;
    final colors = DashboardColors.of(context);
    final up = _Stats.of([for (final sample in series.samples) sample.up]);
    final down = _Stats.of([for (final sample in series.samples) sample.down]);
    final unsupported = series.unsupported;
    return DashboardDetailScaffold(
      title: context.l10n.speedDetailTitle,
      children: [
        DashboardDetailHero(
          glyph: TablerIcons.gauge,
          label: context.l10n.speedCurrentDownload,
          value: unsupported
              ? context.l10n.commonNoData
              : dashboardBinarySpeed(series.last.down),
          chipLabel: unsupported
              ? context.l10n.speedSamplingPaused
              : context.l10n.speedLive,
          chipColor: unsupported
              ? colorScheme.onSurfaceVariant
              : colorScheme.success,
          hint: unsupported
              ? _unsupportedHint(series.source, context.l10n)
              : context.l10n.speedSamplingHint,
        ),
        DashboardDetailStats(
          stats: [
            StatItem(
              label: context.l10n.speedCurrentUpload,
              value: unsupported ? '—' : dashboardBinarySpeed(series.last.up),
              color: colors.series2,
            ),
            StatItem(
              label: context.l10n.speedDownloadPeak,
              value: unsupported ? '—' : dashboardBinarySpeed(down.peak),
              color: colorScheme.primary,
            ),
            StatItem(
              label: context.l10n.speedUploadPeak,
              value: unsupported ? '—' : dashboardBinarySpeed(up.peak),
              color: colors.series2,
            ),
            StatItem(
              label: context.l10n.speedSamples,
              value: '${series.samples.length}',
              unit: '/$speedSampleCapacity',
            ),
          ],
        ),
        _CurveCard(
          title: context.l10n.speedDownload,
          color: colorScheme.primary,
          stats: down,
          values: series.downValues(),
          series: series,
        ),
        _CurveCard(
          title: context.l10n.speedUpload,
          color: colors.series2,
          stats: up,
          values: series.upValues(),
          series: series,
        ),
        DashboardDetailCard(
          glyph: TablerIcons.chart_pie,
          title: context.l10n.speedTodayTotal,
          child: totals == null
              ? Text(
                  context.l10n.speedNoTrafficToday,
                  style: AppTextRole.body
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 12,
                  children: [
                    _TotalsBar(totals: totals, colors: colors),
                    DashboardDetailRows(
                      rows: [
                        DashboardDetailRow(
                          label: context.l10n.speedDownload,
                          value: dashboardBinaryBytes(totals.down),
                          tabular: true,
                          color: colorScheme.primary,
                        ),
                        DashboardDetailRow(
                          label: context.l10n.speedUpload,
                          value: dashboardBinaryBytes(totals.up),
                          tabular: true,
                          color: colors.series2,
                        ),
                        DashboardDetailRow(
                          label: context.l10n.speedTotal,
                          value: dashboardBinaryBytes(totals.total),
                          tabular: true,
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        DashboardDetailNote(
          text: unsupported
              ? _unsupportedHint(series.source, context.l10n)
              : context.l10n.speedRateFooter,
        ),
      ],
    );
  }

  static String _unsupportedHint(SpeedSource source, AppL10n l10n) =>
      switch (source) {
        SpeedSource.noNativeChannel => l10n.speedNoChannelSource,
        SpeedSource.available => '',
      };
}

class _TotalsBar extends StatelessWidget {
  const _TotalsBar({required this.totals, required this.colors});

  final TrafficTotals totals;
  final DashboardColors colors;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        DashboardShareBar(
          height: 10,
          segments: [
            (value: totals.down.toDouble(), color: colorScheme.primary),
            (value: totals.up.toDouble(), color: colors.series2),
          ],
        ),
        Row(
          children: [
            Text(
              context.l10n.speedTotalsDown(
                dashboardPercent(
                  totals.total <= 0 ? 0 : totals.down / totals.total,
                ),
              ),
              style: AppTextRole.caption
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const Spacer(),
            Text(
              context.l10n.speedTotalsUp(
                dashboardPercent(
                  totals.total <= 0 ? 0 : totals.up / totals.total,
                ),
              ),
              style: AppTextRole.caption
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurveCard extends StatelessWidget {
  const _CurveCard({
    required this.title,
    required this.color,
    required this.stats,
    required this.values,
    required this.series,
  });

  final String title;
  final Color color;
  final _Stats stats;
  final List<double> values;
  final SpeedSeries series;

  @override
  Widget build(BuildContext context) {
    final unsupported = series.unsupported;
    return DashboardDetailChart(
      title: title,
      color: color,
      values: unsupported ? const [] : values,
      revision: series.revision,
      capacity: speedSampleCapacity,
      minScale: 8 * 1024,
      emptyLabel: unsupported
          ? context.l10n.speedNoDataInMode
          : context.l10n.speedWaitingSample,
      caption: unsupported
          ? null
          : context.l10n.speedPeakAverage(
              dashboardBinarySpeed(stats.average),
              dashboardBinarySpeed(stats.peak),
            ),
    );
  }
}

class _Stats {
  const _Stats({required this.peak, required this.average});

  final double peak;
  final double average;

  static _Stats of(List<double> values) {
    if (values.isEmpty) return const _Stats(peak: 0, average: 0);
    final peak = values.reduce(math.max);
    final sum = values.fold<double>(0, (total, value) => total + value);
    return _Stats(peak: peak, average: sum / values.length);
  }
}
