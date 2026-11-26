import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class LogsRankBadge extends StatelessWidget {
  const LogsRankBadge({super.key, required this.rank});

  final int rank;

  static const _size = 26.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final (foreground, background) = switch (rank) {
      1 => (colorScheme.onPrimary, colorScheme.primary),
      2 ||
      3 => (colorScheme.primary, colorScheme.primary.withValues(alpha: 0.12)),
      _ => (
        colorScheme.onSurfaceVariant,
        context.raisedSurfaceLevel.colorOf(colorScheme),
      ),
    };
    return Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: background, shape: AppShape.standard),
      child: Text(
        '$rank',
        maxLines: 1,
        style: AppTextRole.badge
            .of(context)
            .toTabular
            .copyWith(color: foreground),
      ),
    );
  }
}

class LogsRowBar extends StatelessWidget {
  const LogsRowBar({super.key, required this.share, this.color});

  final double share;
  final Color? color;

  static const _height = 5.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ClipRRect(
      borderRadius: AppRadius.standard,
      child: SizedBox(
        height: _height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.onSurface.withValues(alpha: 0.08),
              ),
            ),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: share.clamp(0.0, 1.0),
                child: ColoredBox(color: color ?? colorScheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
