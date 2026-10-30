import 'package:diting/ui/ui.dart';
import 'package:material_ui/material_ui.dart';

/// A row of equally wide value/label cells, shared by every stats page.
class StatStrip extends StatelessWidget {
  const StatStrip({
    super.key,
    required this.stats,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    this.separator = true,
  });

  final List<StatItem> stats;
  final EdgeInsets padding;

  /// Whether to draw a divider between cells.
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

/// One cell of a [StatStrip].
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

  /// Value colour, e.g. error for blocked counts, success for hit rates.
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
                style: AppTextStyle.title3
                    .of(context, emphasized: true)
                    .copyWith(color: valueColor),
              ),
            ),
            if (item.unit case final unit?)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  unit,
                  style: AppTextStyle.caption1
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
          style: AppTextStyle.caption1
              .of(context)
              .copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// A read-only `label: value` row.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;

  /// Monospace for addresses, ports and package names.
  final bool monospace;

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
              style: AppTextStyle.subheadline
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
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(
                    color: colorScheme.onSurface,
                    fontFamily: monospace ? appMonospaceFontFamily : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled group: header, [child], optional footer. Horizontal padding applies to [child] only;
/// `ListHeader`/`ListFooter` already carry 16, and doubling it indents the title by 32.
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

/// Bottom spacer that clears whatever bar the shell draws; appended to scrollable pages. Ask
/// [DockInsetScope] rather than [NavigationDock] directly: pages pushed over the shell have no bar,
/// and reserving dock-sized space there only shows as dead white at the end of the list.
class DockSpacer extends StatelessWidget {
  const DockSpacer({super.key, this.extra = 0});

  final double extra;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: DockInsetScope.of(context) + extra);
  }
}

/// Scrollable page body with the app bar inset, dock spacer and scrollbar. The inset must come from
/// `context.appBarInset` and go into `ListView.padding`, not an outer `Padding`: the scaffold uses
/// `extendBodyBehindAppBar`, so otherwise the viewport is clipped instead of scrolling behind it.
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
        // Rows below the fold wait for the route to settle, so they do not land in the
        // transition's first frame.
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
