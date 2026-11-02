import 'package:diting_shared/app/l10n/l10n.dart';
import 'dart:math' as math;

import 'package:diting_android/data/dashboard_models.dart';
import 'package:diting_android/pages/home/dashboard/cards/dashboard_block_parts.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/state/dashboard_providers.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Upload and download side by side, after FlClash widgets/traffic.dart: each tile bleeds
/// its curve under the figures, so the chart is the tile's background rather than a strip.
class NetworkSpeedCard extends ConsumerWidget {
  const NetworkSpeedCard({super.key, this.onDetail});

  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only the source shapes the tiles. Samples land every second and are watched by the
    // figures and the chart alone, so the header and tile frames do not rebuild with them.
    final source = ref.watch(speedSeriesProvider.select((s) => s.source));
    final scale = DashboardDensityScope.scaleOf(context);
    return DashboardCard(
      semanticLabel: context.l10n.speedTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.speed,
            title: context.l10n.speedTitle,
            trailing: [
              if (onDetail != null)
                DashboardIconButton(
                  glyph: AppGlyphs.chevronForward,
                  tooltip: context.l10n.dashboardDetailTooltip,
                  onPressed: onDetail,
                ),
            ],
          ),
          SizedBox(height: 12 * scale),
          Row(
            spacing: 10,
            children: [
              for (final direction in _SpeedDirection.values)
                Expanded(
                  child: _SpeedTile(direction: direction, source: source),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SpeedDirection {
  upload,
  download;

  double of(SpeedSample sample) => this == upload ? sample.up : sample.down;

  Glyph get glyph => this == upload ? AppGlyphs.arrowUp : AppGlyphs.arrowDown;

  String label(AppL10n l10n) =>
      this == upload ? l10n.speedUpload : l10n.speedDownload;

  Color colorOf(BuildContext context) => this == upload
      ? DashboardColors.of(context).series2
      : context.colorScheme.primary;

  List<double> valuesOf(SpeedSeries series) =>
      this == upload ? series.upValues() : series.downValues();

  double? totalOf(TrafficTotals? totals) =>
      totals == null ? null : (this == upload ? totals.up : totals.down);
}

/// Number and unit, so the unit can shrink next to a large figure: `1.2` + `MB`.
(String, String) _split(String text) {
  final at = text.lastIndexOf(' ');
  return at < 0 ? (text, '') : (text.substring(0, at), text.substring(at + 1));
}

/// Value plus its unit, sized from the surrounding tile.
class _SpeedFigure extends StatelessWidget {
  const _SpeedFigure({
    required this.value,
    required this.unit,
    required this.style,
    required this.unitStyle,
    this.color,
  });

  final String value;
  final String unit;
  final AppTextStyle style;
  final AppTextStyle unitStyle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: DashboardText.figure(context, style, color: color),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: ' $unit/s',
              style: DashboardText.unit(context, unitStyle),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}

/// Keeps one shape at every width: the chart takes what the tile's aspect ratio leaves
/// under the text, down to [_minChartHeight].
class _SpeedTile extends StatelessWidget {
  const _SpeedTile({required this.direction, required this.source});

  final _SpeedDirection direction;
  final SpeedSource source;

  static const _aspectRatio = 1.06;
  static const _padding = EdgeInsets.fromLTRB(16, 14, 16, 0);
  static const _titleGap = 4.0;
  static const _chartGap = 12.0;
  static const _bleed = 2.0;
  static const _minChartHeight = 36.0;

  @override
  Widget build(BuildContext context) {
    final color = direction.colorOf(context);
    final unsupported = source != SpeedSource.available;
    final scale = DashboardDensityScope.scaleOf(context);
    final textHeight =
        _padding.top +
        _titleGap +
        (AppTextStyle.footnote.leading +
                AppTextStyle.title1.leading +
                AppTextStyle.caption1.leading) *
            scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartHeight = math.max(
          _minChartHeight,
          constraints.maxWidth / _aspectRatio - textHeight - _chartGap + _bleed,
        );
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: DashboardColors.of(context).tone,
            shape: AppShape.all(DashboardCorner.mobileBlock),
          ),
          child: Stack(
            children: [
              Positioned(
                left: -_bleed,
                right: -_bleed,
                bottom: -_bleed,
                height: chartHeight,
                child: RepaintBoundary(
                  child: unsupported
                      ? Center(
                          child: Text(
                            source == SpeedSource.expressMode
                                ? context.l10n.speedExpressNoStats
                                : context.l10n.speedNoChannel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardText.label(context),
                          ),
                        )
                      : Consumer(
                          builder: (context, ref, _) {
                            final series = ref.watch(speedSeriesProvider);
                            return LineChart(
                              values: direction.valuesOf(series),
                              revision: series.revision,
                              capacity: speedSampleCapacity,
                              // Same as upstream: idle jitter must not pin the curve to full
                              // height.
                              minScale: 8 * 1024,
                              color: color,
                              baselineRatio: 1,
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: _padding.copyWith(
                  bottom: chartHeight - _bleed + _chartGap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: 4,
                      children: [
                        GlyphIcon(direction.glyph, size: 16, color: color),
                        Flexible(
                          child: Text(
                            direction.label(context.l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.footnote
                                .of(context, emphasized: true)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _titleGap),
                    Consumer(
                      builder: (context, ref, _) {
                        final rate = ref.watch(
                          speedSeriesProvider.select(
                            (s) => direction.of(s.last),
                          ),
                        );
                        final (value, unit) = unsupported
                            ? ('—', '')
                            : _split(dashboardBinaryBytes(rate));
                        return _SpeedFigure(
                          value: value,
                          unit: unit,
                          style: AppTextStyle.title1,
                          unitStyle: AppTextStyle.footnote,
                          color: context.colorScheme.onSurface,
                        );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final total = direction.totalOf(
                          ref.watch(trafficTotalsProvider).value,
                        );
                        return Text(
                          total == null
                              ? context.l10n.speedTotalDash
                              : context.l10n.speedTotalAccumulated(
                                  dashboardBinaryBytes(total),
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardText.label(context),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
