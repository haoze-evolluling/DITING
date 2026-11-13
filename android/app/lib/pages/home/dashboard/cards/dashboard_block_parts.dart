import 'package:diting_shared/app/l10n/l10n.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_card.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_density.dart';
import 'package:diting_shared/widgets/dashboard/dashboard_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Shared log-dashboard block primitives, defined once so ring width and padding cannot
/// drift between cards.
/// One donut segment. Callers filter out zero-value segments first.
typedef DonutSegment = ({int value, Color color});

/// Percent text: `12.3%`, trailing `.0` dropped.
String dashboardPercent(double ratio) {
  final rounded = (ratio.clamp(0.0, 1.0) * 1000).round() / 10;
  return rounded % 1 == 0 ? '${rounded.toInt()}%' : '$rounded%';
}

String dashboardLatency(double milliseconds) => '${milliseconds.round()} ms';

/// Duration text that truncates instead of rounding up, so 3420s reads as 57 min.
String dashboardDuration(int seconds, AppL10n l10n) {
  if (seconds >= 3600) return l10n.durationHours(seconds ~/ 3600);
  if (seconds >= 60) return l10n.durationMinutes(seconds ~/ 60);
  return l10n.durationSeconds(seconds);
}

/// Bytes in base 1024, two decimals. Deliberately not [dashboardTraffic] (base 1000):
/// one feeds the traffic card, the other the speed card.
String dashboardBinaryBytes(num bytes) {
  const k = 1024.0;
  final value = bytes.toDouble();
  if (value >= k * k * k * k) {
    return '${(value / (k * k * k * k)).toStringAsFixed(2)} TB';
  }
  if (value >= k * k * k) {
    return '${(value / (k * k * k)).toStringAsFixed(2)} GB';
  }
  if (value >= k * k) {
    return '${(value / (k * k)).toStringAsFixed(2)} MB';
  }
  if (value >= k) {
    return '${(value / k).toStringAsFixed(1)} KB';
  }
  return '${value.round()} B';
}

/// Speed text, e.g. `1.8 MB/s`.
String dashboardBinarySpeed(num bytesPerSecond) {
  const k = 1024.0;
  final value = bytesPerSecond.toDouble();
  if (value >= k * k) return '${(value / (k * k)).toStringAsFixed(2)} MB/s';
  if (value >= k) return '${(value / k).toStringAsFixed(0)} KB/s';
  return '${value.round()} B/s';
}

/// Hand-drawn like `lib/ui/line_chart.dart`; ring stroke and hole ratio mirror upstream.
class DashboardResultDonut extends StatelessWidget {
  const DashboardResultDonut({
    super.key,
    required this.segments,
    required this.total,
    this.diameter = 128,
  });

  final List<DonutSegment> segments;

  /// Center total. Zero draws a full ring in the outline color.
  final int total;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final scale = DashboardDensityScope.scaleOf(context);
    final size = diameter * scale;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DonutPainter(
                  segments: segments,
                  total: total,
                  track: colorScheme.outline.withValues(alpha: 0.35),
                  hole: DashboardColors.of(context).card,
                  scale: scale,
                ),
              ),
            ),
          ),
          Text(
            dashboardCount(total),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.figure(context, AppTextStyle.title3),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.total,
    required this.track,
    required this.hole,
    required this.scale,
  });

  final List<DonutSegment> segments;
  final int total;
  final Color track;
  final Color hole;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 18 * scale;
    final diameter = size.shortestSide;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: diameter / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    if (total <= 0 || segments.isEmpty) {
      canvas.drawArc(rect, -1.5708, 6.2832, false, paint..color = track);
      return;
    }
    var start = -1.5708;
    for (final segment in segments) {
      final sweep = 6.2832 * segment.value / total;
      canvas.drawArc(rect, start, sweep, false, paint..color = segment.color);
      start += sweep;
    }
    // Paint the hole with the card color so it reads as a ring, not a stroked circle.
    canvas.drawCircle(
      size.center(Offset.zero),
      diameter * 0.72 / 2,
      Paint()..color = hole,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.total != total ||
      oldDelegate.track != track ||
      oldDelegate.hole != hole ||
      oldDelegate.segments != segments;
}

class DashboardLegendRow extends StatelessWidget {
  const DashboardLegendRow({
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
    return Row(
      spacing: 8,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: ShapeDecoration(
            color: color,
            shape: const CircleBorder(),
          ),
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardText.rowTitle(context)
                .copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashboardText.figure(
            context,
            AppTextStyle.footnote,
            color: color,
          ),
        ),
      ],
    );
  }
}

class DashboardRateRow extends StatelessWidget {
  const DashboardRateRow({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
  });

  final String label;
  final String value;

  /// 0..1; clamped, never asserts. `null` renders the value alone, with no bar,
  /// for figures that are not a ratio (e.g. average latency).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final color = DashboardColors.of(context);
    final scale = DashboardDensityScope.scaleOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.rowTitle(context),
              ),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: DashboardText.label(
                  context,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
        if (progress case final progress?)
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 9 * scale,
              color: color.tone,
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: colorScheme.primary),
              ),
            ),
          ),
      ],
    );
  }
}

class DashboardLogRow extends StatelessWidget {
  const DashboardLogRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.tag,
    this.tagColor,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? tag;
  final Color? tagColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final tagColor = this.tagColor ?? colorScheme.onSurfaceVariant;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.rowTitle(context),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardText.label(context),
                ),
              ],
            ),
          ),
          if (tag case final tag?)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: ShapeDecoration(
                color: tagColor.withValues(alpha: 0.12),
                shape: AppShape.all(DashboardCorner.badge - 4),
              ),
              child: Text(
                tag,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.figure(
                  context,
                  AppTextStyle.caption1,
                  color: tagColor,
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      customBorder: AppShape.all(AppCorner.sm),
      onTap: onTap,
      child: content,
    );
  }
}

/// List card: title, detail link, then rows or [emptyText].
class DashboardLogListCard extends StatelessWidget {
  const DashboardLogListCard({
    super.key,
    required this.glyph,
    required this.title,
    required this.emptyText,
    required this.rows,
    this.onDetail,
    this.detailTooltip,
  });

  final Glyph glyph;
  final String title;
  final String emptyText;
  final List<Widget> rows;
  final VoidCallback? onDetail;
  final String? detailTooltip;

  @override
  Widget build(BuildContext context) {
    final separator = DashboardColors.of(context).tone;
    return DashboardCard(
      semanticLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 2,
        children: [
          DashboardCardHeader(
            glyph: glyph,
            title: title,
            trailing: [
              if (onDetail != null)
                DashboardIconButton(
                  glyph: AppGlyphs.chevronForward,
                  tooltip: detailTooltip ?? context.l10n.dashboardDetailTooltip,
                  onPressed: onDetail,
                ),
            ],
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(emptyText, style: DashboardText.label(context)),
            )
          else
            for (final (index, row) in rows.indexed) ...[
              if (index > 0) Container(height: 1, color: separator),
              row,
            ],
          SizedBox(height: 2),
        ],
      ),
    );
  }
}
