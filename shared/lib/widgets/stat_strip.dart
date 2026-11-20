import 'package:diting_shared/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

class StatStrip extends StatelessWidget {
  const StatStrip({
    super.key,
    required this.stats,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.separator = true,
  });

  final List<StatItem> stats;
  final EdgeInsets padding;

  final bool separator;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          for (final (index, stat) in stats.indexed) ...[
            if (index > 0 && separator)
              Container(
                width: 1,
                height: 28,
                color: colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            Expanded(child: _StatCell(item: stat)),
          ],
        ],
      ),
    );
  }
}

class StatItem {
  const StatItem({
    required this.label,
    required this.value,
    this.unit,
    this.color,
  });

  final String label;
  final String value;
  final String? unit;

  final Color? color;
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.item});

  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final valueColor = item.color ?? colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                item.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextRole.sectionTitle
                    .of(context)
                    .copyWith(color: valueColor),
              ),
            ),
            if (item.unit case final unit?)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit,
                  style: AppTextRole.caption
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextRole.caption
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.tabular = false,
  });

  final String label;
  final String value;

  final bool tabular;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextRole.body
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTextRole.body
                  .of(context)
                  .copyWith(
                    color: colorScheme.onSurface,
                    fontFeatures: tabular ? appTabularFigures : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class SectionBlock extends StatelessWidget {
  const SectionBlock({
    super.key,
    this.title,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final String? title;
  final Widget child;
  final String? footer;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          if (title case final title?) ListHeader(title: title),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: padding.left,
              end: padding.right,
            ),
            child: child,
          ),
          if (footer case final footer?) ListFooter(text: footer),
        ],
      ),
    );
  }
}

class DockSpacer extends StatelessWidget {
  const DockSpacer({super.key, this.extra = 0});

  final double extra;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: DockInsetScope.of(context) + extra);
  }
}

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.dockSpacer = true,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final bool dockSpacer;

  @override
  Widget build(BuildContext context) {
    final inset = context.appBarInset;
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: FloatingBarScope(
        inset: 0,
        child: RouteArrivalScope(
          builder: (_, cacheExtent) => ListView(
            scrollCacheExtent: cacheExtent,
            padding: padding + EdgeInsets.only(top: inset),
            children: [...children, if (dockSpacer) const DockSpacer()],
          ),
        ),
      ),
    );
  }
}
