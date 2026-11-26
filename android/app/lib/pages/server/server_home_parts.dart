import 'package:diting_android/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

import 'server_home_style.dart';

class ServerCardHeader extends StatelessWidget {
  const ServerCardHeader({
    super.key,
    required this.glyph,
    required this.title,
    this.trailing = const [],
  });

  final IconData glyph;
  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Row(
      spacing: 8,
      children: [
        Icon(glyph, size: 18, color: scheme.onSurfaceVariant),
        Expanded(child: Text(title, style: AppTextRole.rowTitle.of(context))),
        for (final child in trailing) child,
      ],
    );
  }
}

class ServerEmptyPanel extends StatelessWidget {
  const ServerEmptyPanel({
    super.key,
    required this.glyph,
    required this.title,
    required this.body,
  });

  final IconData glyph;
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
            child: Icon(glyph, size: 18, color: scheme.onSurfaceVariant),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 3,
              children: [
                Text(title, style: AppTextRole.bodyStrong.of(context)),
                Text(
                  body,
                  style: AppTextRole.caption
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

class ServerWindowChip extends StatelessWidget {
  const ServerWindowChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: ShapeDecoration(
        color: ServerHomeColors.accentWash(context),
        shape: AppShape.standard,
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppTextRole.badge
            .of(context)
            .copyWith(color: context.colorScheme.primary),
      ),
    );
  }
}

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
      spacing: 3,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextRole.caption
              .of(context)
              .copyWith(color: scheme.onSurfaceVariant),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextRole.bodyStrong
              .of(context)
              .toTabular
              .copyWith(color: color ?? scheme.onSurface),
        ),
        if (hint case final hint?)
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.micro
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

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
      spacing: 8,
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
            style: AppTextRole.caption
                .of(context)
                .copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (trailing case final trailing?)
          Text(
            trailing,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextRole.badge
                .of(context)
                .toTabular
                .copyWith(color: scheme.onSurface),
          ),
      ],
    );
  }
}
