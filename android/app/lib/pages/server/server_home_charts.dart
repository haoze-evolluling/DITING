import 'dart:math' as math;

import 'package:diting_android/data/server/server_runtime_models.dart';
import 'package:diting_android/pages/server/server_home_style.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

String serverHourLabel(DateTime hour) =>
    '${hour.hour.toString().padLeft(2, '0')}:00';

class ServerTrafficChart extends StatelessWidget {
  const ServerTrafficChart({
    super.key,
    required this.points,
    required this.semanticLabel,
    this.height = 136,
  });

  final List<ServerHourPoint> points;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrafficPainter(
              points: points,
              color: ServerHomeColors.chartBase(context),
              blockedColor: ServerHomeColors.chartBlocked(context),
              trackColor: ServerHomeColors.accentSubtle(context),
              gridColor: scheme.onSurfaceVariant.withValues(alpha: 0.10),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({
    required this.points,
    required this.color,
    required this.blockedColor,
    required this.trackColor,
    required this.gridColor,
  });

  final List<ServerHourPoint> points;
  final Color color;
  final Color blockedColor;
  final Color trackColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (final ratio in const [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height * ratio;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (points.isEmpty) {
      canvas.restore();
      return;
    }

    final maxQueries = points.fold<int>(
      1,
      (value, point) => math.max(value, point.queries),
    );
    final slot = size.width / points.length;
    final barWidth = math.max(2.0, slot * 0.54);
    final barRadius = Radius.circular(math.min(3.0, barWidth / 2));
    final trackPaint = Paint()..color = trackColor;
    final basePaint = Paint()..color = color;
    final blockedPaint = Paint()..color = blockedColor;
    final baseline = size.height - 1;
    final chartHeight = size.height - 7;

    for (final (index, point) in points.indexed) {
      final left = slot * index + (slot - barWidth) / 2;
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, barWidth, math.max(1, baseline)),
        barRadius,
      );
      canvas.drawRRect(track, trackPaint);

      if (point.queries <= 0) continue;
      final totalHeight = math.max(
        3.0,
        chartHeight * point.queries / maxQueries,
      );
      final blockedHeight = point.blocked <= 0
          ? 0.0
          : math.max(
              2.0,
              totalHeight *
                  point.blocked.clamp(0, point.queries) /
                  point.queries,
            );
      final baseHeight = math.max(1.0, totalHeight - blockedHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, baseline - baseHeight, barWidth, baseHeight),
          barRadius,
        ),
        basePaint,
      );
      if (blockedHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              baseline - totalHeight,
              barWidth,
              blockedHeight,
            ),
            barRadius,
          ),
          blockedPaint,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TrafficPainter oldDelegate) =>
      !identical(oldDelegate.points, points) ||
      oldDelegate.color != color ||
      oldDelegate.blockedColor != blockedColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.gridColor != gridColor;
}

class ServerPercentRing extends StatelessWidget {
  const ServerPercentRing({
    super.key,
    required this.progress,
    required this.centerLabel,
    required this.color,
    required this.semanticLabel,
    this.size = 104,
    this.strokeWidth = 10,
  });

  final double progress;
  final String centerLabel;
  final Color color;
  final String semanticLabel;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RingPainter(
                    progress: progress,
                    color: color,
                    trackColor: scheme.onSurfaceVariant.withValues(alpha: 0.11),
                    strokeWidth: strokeWidth,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(strokeWidth + 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  centerLabel,
                  maxLines: 1,
                  style: AppTextRole.metricSmall
                      .of(context)
                      .toTabular
                      .copyWith(color: scheme.onSurface),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);

    final amount = progress.clamp(0.0, 1.0);
    if (amount <= 0) return;
    final value = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * amount, false, value);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
