import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class LogsOverviewTile {
  const LogsOverviewTile({
    required this.label,
    required this.value,
    this.glyph,
    this.color,
  });

  final String label;
  final String value;

  final IconData? glyph;

  final Color? color;
}

class LogsRatioBar {
  const LogsRatioBar({
    required this.label,
    required this.value,
    required this.segments,
  });

  final String label;

  final String value;

  final List<({int value, Color color})> segments;
}

class LogsOverviewCard extends StatelessWidget {
  const LogsOverviewCard({super.key, required this.tiles, this.ratio});

  final List<LogsOverviewTile> tiles;
  final LogsRatioBar? ratio;

  static const _gap = 10.0;
  static const _columns = 2;

  @override
  Widget build(BuildContext context) {
    return CommonCard(
      padding: const EdgeInsets.all(_gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  (constraints.maxWidth - _gap * (_columns - 1)) / _columns;
              return Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final tile in tiles)
                    SizedBox(
                      width: width,
                      child: _Tile(tile: tile),
                    ),
                ],
              );
            },
          ),
          if (ratio case final ratio?) _Ratio(ratio: ratio),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile});

  final LogsOverviewTile tile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final accent = tile.color ?? colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.standard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Row(
            spacing: 5,
            children: [
              if (tile.glyph case final glyph?)
                Icon(glyph, size: 13, color: accent),
              Expanded(
                child: Text(
                  tile.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextRole.caption
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              tile.value,
              maxLines: 1,
              style: AppTextRole.metricSmall
                  .of(context)
                  .toTabular
                  .copyWith(color: tile.color ?? colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ratio extends StatelessWidget {
  const _Ratio({required this.ratio});

  final LogsRatioBar ratio;

  static const _height = 8.0;
  static const _gap = 6.0;

  static const _minShare = 0.02;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final visible = [
      for (final segment in ratio.segments)
        if (segment.value > 0) segment,
    ];
    final total = visible.fold(0, (sum, segment) => sum + segment.value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: Text(
                ratio.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.supportingText
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            Text(
              ratio.value,
              style: AppTextRole.sectionLabel
                  .of(context)
                  .toTabular
                  .copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
        SizedBox(
          height: _height,
          child: total == 0
              ? DecoratedBox(
                  decoration: ShapeDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: AppShape.standard,
                  ),
                )
              : Row(
                  spacing: _gap,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final segment in visible)
                      Expanded(
                        flex:
                            (1000 * (segment.value / total).clamp(_minShare, 1))
                                .round(),
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: segment.color,
                            shape: AppShape.standard,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class LogsSectionEmpty extends StatelessWidget {
  const LogsSectionEmpty({
    super.key,
    required this.glyph,
    required this.title,
    required this.description,
  });

  final IconData glyph;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return CommonCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Center(
            child: IconBadge(
              glyph: glyph,
              color: colorScheme.surfaceContainerHighest,
              foregroundColor: colorScheme.onSurfaceVariant,
              shape: AppShape.standard,
              size: 44,
              glyphSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextRole.cardTitle.of(context),
          ),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTextRole.body
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
