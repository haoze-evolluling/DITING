part of 'dashboard_detail_parts.dart';

/// Metric tiles in a two-column grid, framed as its own card.
///
/// A single `StatStrip` row of four cells gave each value a quarter of the phone width, so
/// `73.46 MB` was cut to `73.46 …`. Two columns always fit a binary byte figure, and the tile
/// shrinks a still-too-long value instead of ellipsizing it.
class DashboardDetailStats extends StatelessWidget {
  const DashboardDetailStats({
    super.key,
    required this.stats,
    this.columns = 2,
  });

  final List<StatItem> stats;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return DashboardDetailCard(
      padding: const EdgeInsets.all(10),
      child: DashboardStatGrid(stats: stats, columns: columns),
    );
  }
}

/// The tile grid itself, for pages that already own a card.
class DashboardStatGrid extends StatelessWidget {
  const DashboardStatGrid({super.key, required this.stats, this.columns = 2});

  final List<StatItem> stats;
  final int columns;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: _MetricTile(item: stat),
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final valueColor = item.color ?? colorScheme.onSurface;
    final unit = item.unit;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: ShapeDecoration(
        color: DashboardColors.of(context).tone,
        shape: AppShape.all(AppCorner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 3,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    item.value,
                    maxLines: 1,
                    style: DashboardText.figure(
                      context,
                      AppTextStyle.headline,
                      color: valueColor,
                    ),
                  ),
                ),
              ),
              if (unit != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 3),
                  child: Text(
                    unit,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One read-only `label: value` row inside a [DashboardDetailCard].
class DashboardDetailRow {
  const DashboardDetailRow({
    required this.label,
    required this.value,
    this.monospace = false,
    this.color,
  });

  final String label;
  final String value;

  /// Monospace for addresses, ports and package names.
  final bool monospace;

  /// Value colour for a state that needs to stand out (ok / error).
  final Color? color;
}

/// Rows with hairline separators; values wrap instead of truncating, so a long IPv6 address or a
/// DNS reply stays readable.
class DashboardDetailRows extends StatelessWidget {
  const DashboardDetailRows({super.key, required this.rows});

  final List<DashboardDetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final divider = colorScheme.onSurface.withValues(alpha: 0.08);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) Container(height: 1, color: divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                Text(
                  row.label,
                  style: AppTextStyle.subheadline
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.subheadline
                        .of(context)
                        .copyWith(
                          color: row.color ?? colorScheme.onSurface,
                          fontFamily: row.monospace
                              ? appMonospaceFontFamily
                              : null,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Page-bottom note: the standing explanation of where the numbers come from.
class DashboardDetailNote extends StatelessWidget {
  const DashboardDetailNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Text(
        text,
        style: AppTextStyle.caption1
            .of(context)
            .copyWith(color: context.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
