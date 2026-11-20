import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// Standard header for a server-home dashboard card.
class ServerCardHeader extends StatelessWidget {
  const ServerCardHeader({
    super.key,
    required this.glyph,
    required this.title,
    this.trailing = const [],
  });

  final Glyph glyph;
  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      spacing: 8,
      children: [
        GlyphIcon(glyph, size: 18, color: scheme.onSurfaceVariant),
        Expanded(child: Text(title, style: context.listTitleStyle)),
        for (final child in trailing) child,
      ],
    );
  }
}

/// Quiet placeholder used by a card that has no samples yet.
class ServerEmptyPanel extends StatelessWidget {
  const ServerEmptyPanel({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
  });

  final Glyph glyph;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(scheme),
        shape: AppShape.standard,
      ),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.08),
              shape: AppShape.standard,
            ),
            child: GlyphIcon(glyph, size: 18, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(
                  title,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                Text(
                  body,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One icon-led figure in the request overview grid.
class ServerMetricTile extends StatelessWidget {
  const ServerMetricTile({
    super.key,
    required this.glyph,
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  final Glyph glyph;
  final String label;
  final String value;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: ShapeDecoration(
        color: context.raisedSurfaceLevel.colorOf(scheme),
        shape: AppShape.standard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 7,
        children: [
          Row(
            spacing: 6,
            children: [
              GlyphIcon(glyph, size: 14, color: color),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.title2
                .of(context, emphasized: true)
                .toTabular
                .copyWith(color: color),
          ),
          if (hint case final hint?)
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption2
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Compact label/value pair under a chart.
class ServerMiniMetric extends StatelessWidget {
  const ServerMiniMetric({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.hint,
  });

  final String label;
  final String value;
  final Color? color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.subheadline
              .of(context, emphasized: true)
              .toTabular
              .copyWith(color: color ?? scheme.onSurface),
        ),
        if (hint case final hint?)
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption2
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Colored dot plus label, shared by chart legends.
class ServerLegend extends StatelessWidget {
  const ServerLegend({
    super.key,
    required this.label,
    required this.color,
    this.trailing,
  });

  final String label;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      spacing: 7,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: ShapeDecoration(color: color, shape: AppShape.standard),
        ),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (trailing case final trailing?)
          Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context, emphasized: true)
                .toTabular
                .copyWith(color: scheme.onSurface),
          ),
      ],
    );
  }
}
