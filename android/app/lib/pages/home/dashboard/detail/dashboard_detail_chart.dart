import 'package:diting_android/widgets/dashboard/dashboard_style.dart';
import 'package:diting_android/app/l10n/l10n.dart';
import 'package:diting_android/pages/home/dashboard/detail/dashboard_detail_parts.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

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
                  style: AppTextRole.caption
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

class DashboardShareBar extends StatelessWidget {
  const DashboardShareBar({
    super.key,
    required this.segments,
    this.height = 12,
  });

  final List<({double value, Color color})> segments;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, part) => sum + part.value);
    return ClipRRect(
      borderRadius: AppRadius.standard,
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
            decoration: ShapeDecoration(color: color, shape: AppShape.standard),
          ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextRole.body.of(context),
            ),
          ),
          Text(
            share == null ? value : '$value · ${(share * 100).round()}%',
            maxLines: 1,
            style: AppTextRole.bodyStrong
                .of(context)
                .copyWith(
                  color: colorScheme.onSurface,
                  fontFeatures: appTabularFigures,
                ),
          ),
        ],
      ),
    );
  }
}
