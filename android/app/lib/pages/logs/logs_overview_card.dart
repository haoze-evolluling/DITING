import 'package:diting_android/widgets/icon_badge.dart';
import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// One figure of a [LogsOverviewCard].
class LogsOverviewTile {
  const LogsOverviewTile({
    required this.label,
    required this.value,
    this.glyph,
    this.color,
  });

  final String label;
  final String value;

  /// Mark left of the label; it carries the tile's colour, so a row of tiles reads as
  /// success / failure / latency without a second legend.
  final Glyph? glyph;

  /// Value and glyph colour; `null` keeps the plain on-surface tone.
  final Color? color;
}

/// A proportion line under the tiles of a [LogsOverviewCard].
class LogsRatioBar {
  const LogsRatioBar({
    required this.label,
    required this.value,
    required this.segments,
  });

  /// e.g. 成功率.
  final String label;

  /// Already formatted, e.g. `93.8%` or `—`.
  final String value;

  /// Parts of the whole; values are weights, not percentages.
  final List<({int value, Color color})> segments;
}

/// The `概览` block of a log drill-down page: figures in a two-column tile grid, framed as one
/// card, with an optional proportion bar underneath.
///
/// The bare `StatStrip` this replaces gave every figure a quarter of the phone width, so a count
/// in the millions, `132 ms` and the success count all ended up truncated, and with no card the
/// section read as text floating on the page background.
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
        // One step above the card, so the grid stays visible in both themes.
        color: context.raisedSurfaceLevel.colorOf(colorScheme),
        shape: AppShape.all(AppCorner.md),
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
                GlyphIcon(glyph, size: 13, color: accent),
              Expanded(
                child: Text(
                  tile.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          // Shrink a figure that still does not fit instead of ellipsizing it: `132 ms` cut to
          // `132 …` is a wrong number, not a shortened one.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              tile.value,
              maxLines: 1,
              style: AppTextStyle.title2
                  .of(context, emphasized: true)
                  .toTabular
                  .copyWith(color: tile.color ?? colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label and share on one line, the segments below: a single row of colour never needs a legend
/// when the tiles above already name both sides.
class _Ratio extends StatelessWidget {
  const _Ratio({required this.ratio});

  final LogsRatioBar ratio;

  static const _height = 8.0;
  static const _gap = 6.0;

  /// A non-zero share keeps a minimum width, so one failure in a thousand still shows.
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
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            Text(
              ratio.value,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
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
                    shape: const StadiumBorder(),
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
                            shape: const StadiumBorder(),
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

/// Section-level empty state: a badged glyph, a title and one line of explanation, in the same
/// card shape as the tiles above. A lone `ListItem` under a header read as a missing row rather
/// than as "nothing to show yet".
class LogsSectionEmpty extends StatelessWidget {
  const LogsSectionEmpty({
    super.key,
    required this.glyph,
    required this.title,
    required this.description,
  });

  final Glyph glyph;
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
              // A tinted disc instead of the adjacent surface: on a card the next level up is
              // nearly the same colour, and the mark disappeared into the empty state.
              color: colorScheme.surfaceContainerHighest,
              foregroundColor: colorScheme.onSurfaceVariant,
              shape: AppShape.circle,
              size: 44,
              glyphSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyle.headline.of(context, emphasized: true),
          ),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
