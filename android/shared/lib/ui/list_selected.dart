// Portions derived from DITING (https://github.com/chen08209/DITING), Copyright (c) the DITING authors, GPL-3.0-or-later.
part of 'list.dart';

class DecorationListItem extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool? isSelected;
  final double? horizontalTitleGap;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onPressed;
  final double? minVerticalPadding;
  final bool invalid;

  const DecorationListItem({
    super.key,
    this.contentPadding,
    required this.title,
    this.leading,
    this.trailing,
    this.subtitle,
    this.isSelected,
    this.onPressed,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.invalid = false,
  });

  @override
  State<DecorationListItem> createState() => _DecorationListItemState();
}

class _DecorationListItemState extends State<DecorationListItem> {
  final _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proxy = ProxyDecoratorProvider.of(context);
    final proxyDecorator = proxy?.isProxyDecorator ?? false;
    final sortable = SortableItem.maybeOf(context);
    final sorting = sortable?.sorting ?? false;
    final position = ItemPositionProvider.of(context)?.position;
    final isStart = [
      ItemPosition.start,
      ItemPosition.startAndEnd,
    ].contains(position);
    final isEnd = [
      ItemPosition.end,
      ItemPosition.startAndEnd,
    ].contains(position);
    final borderRadius = AppRadius.vertical(
      top: isStart ? AppCorner.standard : AppCorner.none,
      bottom: isEnd ? AppCorner.standard : AppCorner.none,
    );
    final row = _ListRowSeparator(
      separated: !proxyDecorator && !isEnd,
      emphasized: widget.invalid,
      states: _states,
      endIndent: 14,
      child: CommonCard(
        shape: AppShape.of(borderRadius),
        isError: widget.invalid,
        isSelected: widget.isSelected,
        padding: EdgeInsets.zero,
        statesController: _states,
        inert: sorting,
        onPressed: proxyDecorator ? null : widget.onPressed,
        child: LayoutBuilder(
          builder: (_, constraints) {
            final tile = ListTile(
              leading: widget.leading == null
                  ? null
                  : IgnorePointer(ignoring: sorting, child: widget.leading),
              contentPadding:
                  widget.contentPadding ??
                  const EdgeInsets.only(right: 16, left: 16),
              title: _ListRowSeparatorStart(child: widget.title),
              subtitle: widget.subtitle,
              titleTextStyle: AppTextRole.rowTitle.of(context),
              subtitleTextStyle: AppTextRole.supportingText.of(context),
              minVerticalPadding:
                  widget.minVerticalPadding ?? listRowVerticalPadding,
              minTileHeight: listRowMinHeight,
              horizontalTitleGap: widget.horizontalTitleGap,
              trailing: sortable == null
                  ? widget.trailing
                  : SortableTrailing(item: sortable, child: widget.trailing),
            );
            if (constraints.maxHeight >= double.infinity) {
              return tile;
            }
            return SizedBox(height: constraints.maxHeight, child: tile);
          },
        ),
      ),
    );
    if (!proxyDecorator) {
      return row;
    }
    return ClipRSuperellipse(
      borderRadius: AppRadius.all(AppCorner.standard * proxy!.lift),
      child: row,
    );
  }
}
