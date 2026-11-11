import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Rank mark of a leaderboard row: a filled disc for the top step, a tint for the podium and a
/// quiet tone below it. The plain `1`/`2`/`3` it replaces carried no weight at all next to the
/// resolver name.
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
      decoration: ShapeDecoration(color: background, shape: AppShape.circle),
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

/// Share of the row against the best row, drawn as a slim bar so the ranking stays readable when
/// two neighbouring counts are close. Same shape as the traffic page's per-app share bar.
class LogsRowBar extends StatelessWidget {
  const LogsRowBar({super.key, required this.share, this.color});

  /// 0..1; values outside the range are clamped rather than overflowing the track.
  final double share;
  final Color? color;

  static const _height = 5.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(_height / 2),
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
