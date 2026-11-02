import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Chart card: title row, the plot on a faint baseline and an optional caption.
///
/// The empty state keeps the plot area and the baseline instead of a lone centered sentence,
/// which is what made the speed page look broken when the tunnel was idle.
class DashboardDetailChart extends StatelessWidget {
  const DashboardDetailChart({
    super.key,
    required this.title,
    required this.color,
    required this.values,
    required this.revision,
    required this.capacity,
    required this.minScale,
    this.caption,
    this.emptyLabel,
    this.height = 148,
  });

  final String title;
  final Color color;
  final List<double> values;
  final int revision;
  final int capacity;
  final double minScale;
  final String? caption;
  final String? emptyLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return DashboardDetailCard(
      title: title,
      footer: caption,
      child: SizedBox(
        height: height * scale.clamp(1, 1.4),
        child: Stack(
          children: [
            // Baseline: a zero-length series would otherwise leave the card blank.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 1,
                color: colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            if (values.length < 2)
              Center(
                child: Text(
                  emptyLabel ?? context.l10n.homeChartEmptyLabel,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              Positioned.fill(
                child: LineChart(
                  values: values,
                  revision: revision,
                  capacity: capacity,
                  minScale: minScale,
                  color: color,
                  baselineRatio: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Composition bar for one total split into parts; a zero total draws the track only, so the
/// widget never divides by zero.
class DashboardShareBar extends StatelessWidget {
  const DashboardShareBar({
    super.key,
    required this.segments,
    this.height = 12,
  });

  /// Parts of the whole; values are weights, not percentages.
  final List<({double value, Color color})> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, part) => sum + part.value);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? ColoredBox(color: DashboardColors.of(context).track)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final part in segments)
                    if (part.value > 0)
                      Expanded(
                        // Per-mille flex: a 0.3% sliver must stay a sliver, not round up to
                        // a visible block.
                        flex: (part.value * 1000 / total).round().clamp(
                          1,
                          1000,
                        ),
                        child: ColoredBox(color: part.color),
                      ),
                ],
              ),
      ),
    );
  }
}

/// Legend line under a [DashboardShareBar]: dot, label and the value with its share.
class DashboardShareLegend extends StatelessWidget {
  const DashboardShareLegend({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.share,
  });

  final String label;
  final String value;
  final Color color;

  /// 0..1 share of the whole; omitted when it makes no sense (device free memory).
  final double? share;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final share = this.share;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        spacing: 8,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: ShapeDecoration(color: color, shape: AppShape.circle),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.subheadline.of(context),
            ),
          ),
          Text(
            share == null ? value : '$value · ${(share * 100).round()}%',
            maxLines: 1,
            style: AppTextStyle.subheadline
                .of(context, emphasized: true)
                .copyWith(
                  color: colorScheme.onSurface,
                  fontFamily: appMonospaceFontFamily,
                ),
          ),
        ],
      ),
    );
  }
}
